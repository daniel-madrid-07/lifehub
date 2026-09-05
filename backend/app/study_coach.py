"""Coach de Estudios: la IA mira el repo del proyecto en el que estas
trabajando y te dice que llevas hecho, que te falta y como vas de tiempo.

Configuracion (.env), todo opcional — sin STUDIES_GH_ORG el modulo se apaga:
  STUDIES_GH_TOKEN   token de GitHub con acceso a la organizacion
  STUDIES_GH_ORG     organizacion donde estan los repos de tus proyectos
  STUDIES_CONTEXT    como se evalua en tu centro (norma, tests, defensa...).
                     Se le pasa a la IA como contexto.
  STUDIES_REPO_RE    regex opcional para sacar (codigo, instancia, slug) del
                     nombre del repo, si tu centro los nombra con un patron.

Enunciado y deadline: opcionalmente via una API propia (INTRA_API_URL), para
centros que expongan esos datos. Sin ella, el coach trabaja solo con el repo.

Eleccion del proyecto: el de deadline futuro mas cercano; si no hay ninguno,
el repo con push mas reciente.

Bajo demanda y cacheado (no gasta de mas).
"""
import base64
import re
from datetime import datetime
from urllib.parse import quote

import requests

from . import ai, config

GH = "https://api.github.com"

# Contexto academico por defecto. Cada centro corrige distinto, asi que esto
# se sobreescribe con STUDIES_CONTEXT en el .env.
DEFAULT_CONTEXT = (
    "Estudios tecnicos por proyectos: se entrega via repositorio de GitHub y "
    "cuenta lo que este en la rama por defecto antes del deadline. Se valora "
    "que compile/ejecute sin errores, la gestion de casos limite, un README "
    "claro y, si el proyecto lo pide, tests."
)


def _context(env) -> str:
    return env.get("STUDIES_CONTEXT") or DEFAULT_CONTEXT


def _repo_pattern(env):
    """Regex para (codigo, instancia, slug) si el centro nombra asi los repos."""
    raw = env.get("STUDIES_REPO_RE")
    if not raw:
        return None
    try:
        return re.compile(raw)
    except re.error:
        return None


def _env():
    return config.load_env()


# ── GitHub ──────────────────────────────────────────────────────────────────

def _gh_headers(env):
    h = {"Accept": "application/vnd.github+json"}
    tok = env.get("STUDIES_GH_TOKEN")
    if tok:
        h["Authorization"] = f"Bearer {tok}"
    return h


def _gh(path: str, env):
    try:
        r = requests.get(GH + path, headers=_gh_headers(env), timeout=25)
        return r.json() if r.ok else None
    except requests.RequestException:
        return None


def list_repos(env) -> list[dict]:
    org = env.get("STUDIES_GH_ORG")
    if not org:
        return []
    data = _gh(f"/orgs/{org}/repos?per_page=100&sort=pushed&direction=desc", env)
    return data if isinstance(data, list) else []


def _parse_repo(name: str, env=None):
    """Saca (codigo, instancia, slug) del nombre del repo, si hay patron
    configurado. Sin patron no se puede casar con el intra: devuelve None."""
    pattern = _repo_pattern(env if env is not None else _env())
    if pattern is None:
        return None
    m = pattern.match(name)
    return m.groups()[:3] if m and len(m.groups()) >= 3 else None


# ── Intra (deadline + enunciado) ────────────────────────────────────────────

def _intra_post(path: str, payload, env):
    base = env.get("INTRA_API_URL", "http://127.0.0.1:8000")
    key = env.get("INTRA_API_KEY")
    try:
        r = requests.post(
            base + path, json=payload,
            headers={"X-API-Key": key} if key else {}, timeout=120,
        )
        return r.json() if r.ok else None
    except requests.RequestException:
        return None


def _intra_get(path: str, env):
    base = env.get("INTRA_API_URL", "http://127.0.0.1:8000")
    key = env.get("INTRA_API_KEY")
    try:
        r = requests.get(base + path, headers={"X-API-Key": key} if key else {}, timeout=120)
        return r.json() if r.ok else None
    except requests.RequestException:
        return None


def _subject_for(meta, env) -> str:
    """Enunciado del proyecto elegido (PDF del intra -> texto). Vacio si el
    proyecto no trae fichero (p.ej. los Back To The Future)."""
    if not meta or not meta.get("acti"):
        return ""
    sj = _intra_get(f"/subject?acti={quote(meta['acti'], safe='/')}", env) or {}
    return sj.get("text") or ""


def _parse_deadline(s: str | None):
    if not s:
        return None
    for fmt in ("%Y-%m-%d %H:%M:%S", "%d/%m/%Y, %H:%M", "%d/%m/%Y"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None


def _pick(env) -> tuple[dict | None, dict | None]:
    """Devuelve (meta_intra | None, repo). meta tiene title/deadline/subject."""
    repos = list_repos(env)
    if not repos:
        return None, None

    # casa los repos recientes con su proyecto del intra (deadline + enunciado)
    items, by_key = [], {}
    for r in repos[:10]:
        parsed = _parse_repo(r["name"])
        if not parsed:
            continue
        code, instance, slug = parsed
        items.append({"code": code, "instance": instance, "slug": slug})
        by_key[(code, instance, slug)] = r

    metas = _intra_post("/project-metas", items, env) or []
    today = config.now_local().date()
    best = None  # (dias_hasta_deadline, meta, repo)
    for m in metas:
        dl = _parse_deadline(m.get("deadline"))
        if not dl:
            continue
        days = (dl.date() - today).days
        if days < 0:
            continue  # ya paso
        repo = by_key.get((m.get("code"), m.get("instance"), m.get("slug")))
        if repo and (best is None or days < best[0]):
            best = (days, m, repo)

    if best:
        return best[1], best[2]
    # sin proyecto activo: ultimo repo tocado
    return None, repos[0]


# ── Lectura del repo ────────────────────────────────────────────────────────

_KEY_NAMES = ("makefile", "readme.md", "readme")
_CODE_EXT = (".c", ".h", ".cpp", ".hpp", ".py", ".sh", ".js", ".ts")
_SKIP = (".git/", "/.", "node_modules/")
_MAX_DUMP = 14000


def _repo_dump(repo: dict, env) -> str:
    org = env.get("STUDIES_GH_ORG")
    name = repo["name"]
    branch = repo.get("default_branch", "main")
    tree = _gh(f"/repos/{org}/{name}/git/trees/{branch}?recursive=1", env)
    blobs = [t for t in (tree or {}).get("tree", []) if t.get("type") == "blob"] if tree else []
    paths = [b["path"] for b in blobs]

    lines = [f"Archivos ({len(paths)}):"]
    lines += [f"  {p}" for p in paths[:120]]

    def want(path: str) -> bool:
        low = path.lower()
        if any(s in low for s in _SKIP):
            return False
        base = low.rsplit("/", 1)[-1]
        return base in _KEY_NAMES or low.endswith(_CODE_EXT)

    targets = sorted(
        [p for p in paths if want(p)],
        key=lambda p: (p.rsplit("/", 1)[-1].lower() not in _KEY_NAMES, len(p)),
    )
    picked, budget = [], _MAX_DUMP
    for path in targets:
        if budget <= 0:
            break
        blob = _gh(f"/repos/{org}/{name}/contents/{path}?ref={branch}", env)
        if not isinstance(blob, dict) or blob.get("encoding") != "base64":
            continue
        try:
            content = base64.b64decode(blob["content"]).decode("utf-8", "replace")
        except Exception:
            continue
        snippet = content[:3000]
        budget -= len(snippet)
        picked.append(f"\n----- {path} -----\n{snippet}")

    return "\n".join(lines) + "".join(picked)


# ── Coach ───────────────────────────────────────────────────────────────────

def coach() -> str | None:
    env = _env()
    if not env.get("STUDIES_GH_TOKEN") or not env.get("STUDIES_GH_ORG"):
        return None

    meta, repo = _pick(env)
    if not repo:
        return None

    title = (meta or {}).get("title") or repo["name"]
    pushed = repo.get("pushed_at", "")[:10]
    subject = _subject_for(meta, env)

    # "Back To The Future - X" = recuperacion (retake) del proyecto X: se evalua
    # con los MISMOS requisitos que el proyecto original X.
    bttf = re.match(r"\s*back to the future\s*-\s*(.+)", title, re.IGNORECASE)
    recup = ""
    if bttf:
        base = bttf.group(1).strip()
        title = base
        recup = (
            f"OJO: esto es una recuperacion (Back To The Future) del proyecto '{base}'. "
            f"Se corrige con los MISMOS requisitos que el proyecto original '{base}'. "
            "No es un proyecto nuevo: es rehacer/terminar ese.\n\n"
        )

    if meta and meta.get("deadline"):
        dl = _parse_deadline(meta["deadline"])
        days = (dl.date() - config.now_local().date()).days if dl else None
        when = f"Entrega: {meta['deadline']}" + (f" (faltan {days} dias)" if days is not None else "")
    else:
        when = "Sin proyecto activo en el intra ahora (vacaciones); analizo tu ultimo repo."

    subj_section = (
        f"Enunciado del proyecto (del intra):\n{subject}\n\n"
        if subject.strip()
        else "Enunciado: no disponible; deducelo por el codigo, el nombre del repo y "
        "el tipo de proyecto.\n\n"
    )

    dump = _repo_dump(repo, env)
    prompt = (
        f"Eres el mentor del usuario en sus estudios. {_context(env)}\n\n"
        f"Proyecto: {title} (repo {repo['name']}). {when}. Ultimo push: {pushed}.\n\n"
        f"{recup}"
        f"{subj_section}"
        f"Estado del repositorio:\n{dump}\n\n"
        "Analiza en espanol, directo, sin emojis ni saludos. Hablale de TU (tu/te/tus), como si se "
        "lo dijeras a el; NUNCA en tercera persona ni digas su nombre. Maximo 8 lineas, en este orden:\n"
        "1) Que tiene hecho ya (concreto).\n"
        "2) Que le falta para cumplir el proyecto (segun el enunciado si lo hay, o los "
        "requisitos tipicos de este tipo de proyecto).\n"
        "3) Como va de tiempo (si hay deadline).\n"
        "4) El siguiente paso concreto a hacer ahora."
    )
    key = f"studies-{repo['name']}-{pushed}-{config.now_local().date()}"
    return ai.ask(prompt, cache_key=key, ttl=6 * 3600)
