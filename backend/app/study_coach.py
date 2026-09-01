"""Coach de Estudios: la IA mira tu proyecto Epitech actual (repo de la org en
GitHub) y, con el enunciado + deadline del intra y el contexto de como evalua
Epitech, te dice que llevas hecho, que te falta y como vas de tiempo.

Acceso GitHub: token de tu cuenta de Epitech (daniel-madrid-07) en EPITECH_GH_TOKEN.
Enunciado/deadline: via intra-bot (/project-metas), que casa cada repo con su
proyecto del intra por modulo+instancia+slug y baja el enunciado si existe.

Eleccion del proyecto: entre tus repos recientes, el que tiene el deadline
futuro mas cercano (el que de verdad corre prisa). Si ninguno tiene proyecto
activo (vacaciones), el repo con push mas reciente.

Bajo demanda y cacheado (no gasta de mas).
"""
import base64
import re
from datetime import datetime
from urllib.parse import quote

import requests

from . import ai, config

GH = "https://api.github.com"

EPITECH_CONTEXT = (
    "Epitech (Programme Grande Ecole, primer ano / Tek1-Tek2, campus Madrid, "
    "instancia BAR). Pedagogia por proyectos, sin clases magistrales: se aprende "
    "haciendo. Cada proyecto se corrige con la Moulinette (tests automaticos) y a "
    "veces soutenance (defensa oral). Hay una NORMA de estilo estricta que la "
    "Moulinette penaliza (cabeceras, nombres, funciones cortas, sin variables "
    "globales, etc.). Se entrega via repo de la organizacion de GitHub; cuenta lo "
    "que esta en la rama por defecto antes del deadline. Suele exigirse Makefile "
    "(all, clean, fclean, re), gestion de errores y, en proyectos grandes, tests."
)

_REPO_RE = re.compile(r"^(G-[A-Z]+-\d+)-([A-Z]{2,4}-\d+-\d+)-(.+)-\d+$")


def _env():
    return config.load_env()


# ── GitHub ──────────────────────────────────────────────────────────────────

def _gh_headers(env):
    h = {"Accept": "application/vnd.github+json"}
    tok = env.get("EPITECH_GH_TOKEN")
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
    org = env.get("EPITECH_ORG")
    if not org:
        return []
    data = _gh(f"/orgs/{org}/repos?per_page=100&sort=pushed&direction=desc", env)
    return data if isinstance(data, list) else []


def _parse_repo(name: str):
    """G-WEB-200-BAR-2-1-epytodo-5 -> (code, instance, slug)."""
    m = _REPO_RE.match(name)
    return (m.group(1), m.group(2), m.group(3)) if m else None


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
    org = env.get("EPITECH_ORG")
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
    if not env.get("EPITECH_GH_TOKEN") or not env.get("EPITECH_ORG"):
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
            f"Se corrige con los MISMOS requisitos que el proyecto original '{base}' de Epitech "
            "(que conoces). No es un proyecto nuevo: es rehacer/terminar ese.\n\n"
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
        else "Enunciado: no disponible en el intra para este proyecto; deducelo por el "
        "codigo, el nombre del repo y el tipo de proyecto Epitech.\n\n"
    )

    dump = _repo_dump(repo, env)
    prompt = (
        f"Eres el mentor de Daniel en Epitech. {EPITECH_CONTEXT}\n\n"
        f"Proyecto: {title} (repo {repo['name']}). {when}. Ultimo push: {pushed}.\n\n"
        f"{recup}"
        f"{subj_section}"
        f"Estado del repositorio:\n{dump}\n\n"
        "Analiza en espanol, directo, sin emojis ni saludos. Hablale de TU (tu/te/tus), como si se "
        "lo dijeras a el; NUNCA en tercera persona ni digas su nombre. Maximo 8 lineas, en este orden:\n"
        "1) Que tiene hecho ya (concreto).\n"
        "2) Que le falta para cumplir el proyecto (segun el enunciado si lo hay, o la norma y los "
        "requisitos tipicos de este tipo de proyecto en Epitech).\n"
        "3) Como va de tiempo (si hay deadline).\n"
        "4) El siguiente paso concreto a hacer ahora."
    )
    key = f"studies-{repo['name']}-{pushed}-{config.now_local().date()}"
    return ai.ask(prompt, cache_key=key, ttl=6 * 3600)
