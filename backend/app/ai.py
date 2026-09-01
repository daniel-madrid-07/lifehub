"""IA (Gemini) para Life Hub: coach del dia, analisis post-entreno y consejo
de nutricion. Bajo demanda (solo cuando abres la pantalla) y con cache, para
no gastar. Gemini Flash es muy barato; aun asi se puede apagar con
AI_ENABLED=off o quitando GEMINI_API_KEY.
"""
import json
import re
import time
from datetime import datetime, timedelta

import requests
from sqlmodel import Session, select

from . import config
from .db import engine
from .models import Exercise, Habit, HealthDay, Routine, RoutineExercise, Task, Workout, WorkoutSet
from .stats import habit_to_out

API = "https://generativelanguage.googleapis.com/v1beta/models"

_cache: dict[str, tuple[str, float]] = {}


def _enabled(env) -> bool:
    return bool(env.get("GEMINI_API_KEY")) and (env.get("AI_ENABLED", "on").lower() != "off")


def ask(prompt: str, cache_key: str | None = None, ttl: float = 3600) -> str | None:
    env = config.load_env()
    if not _enabled(env):
        return None
    if cache_key and cache_key in _cache:
        text, exp = _cache[cache_key]
        if exp > time.time():
            return text
    model = env.get("GEMINI_MODEL", "gemini-2.5-flash")
    try:
        r = requests.post(
            f"{API}/{model}:generateContent",
            headers={"x-goog-api-key": env["GEMINI_API_KEY"], "Content-Type": "application/json"},
            data=json.dumps({"contents": [{"parts": [{"text": prompt}]}]}),
            timeout=30,
        )
        if r.status_code != 200:
            return None
        text = r.json()["candidates"][0]["content"]["parts"][0]["text"].strip()
    except Exception:
        return None
    if cache_key and text:
        _cache[cache_key] = (text, time.time() + ttl)
    return text


# Voz + estilo. La decision de SI hablar la toma un algoritmo en cada coach
# (no la IA); cuando se llega a la IA, es porque ya hay algo que decir.
VOICE = (
    " Hablale en segunda persona (tu, te, tus), como si se lo dijeras a el a la cara. "
    "NUNCA digas 'Daniel' ni hables de el en tercera persona (nada de 'la cartera de Daniel' "
    "ni 'los correos de Daniel': di 'tu cartera', 'tus correos')."
)
STYLE = VOICE + " Se concreto y especifico a TUS datos; nada de consejos genericos de manual."


def filter_important_mail(messages: list[dict]) -> list[dict]:
    """Decide cuales de los correos no leidos son IMPORTANTES de verdad (no nos
    fiamos solo de la etiqueta de Gmail, que se deja fuera correos clave). Si la
    IA esta apagada o falla, devuelve todo lo que vino (no esconde nada)."""
    env = config.load_env()
    if not _enabled(env) or not messages:
        return messages
    numbered = "\n".join(
        f"{i + 1}. De: {m.get('from', '')} | Asunto: {m.get('subject', '')} | {m.get('snippet', '')[:120]}"
        for i, m in enumerate(messages)
    )
    prompt = (
        "De esta lista de correos no leidos, devuelve SOLO los numeros de los que son IMPORTANTES "
        "de verdad para Daniel: de personas reales, su universidad (Epitech), banco, medico, citas, "
        "pagos, tramites, entrevistas/trabajo, o algo que requiera su atencion o accion. EXCLUYE "
        "newsletters, marketing, promociones, redes sociales, recibos rutinarios y notificaciones "
        "automaticas (incluidos los avisos de Google sobre inicios de sesion o datos compartidos "
        "con apps que el mismo ha conectado). Responde SOLO con los numeros separados por comas "
        "(ej: 1,4,5). Si ninguno es importante, responde 0.\n" + numbered
    )
    sig = abs(hash(numbered)) % 100000
    raw = ask(prompt, cache_key=f"mailfilter-{config.now_local().date()}-{sig}", ttl=3600)
    if raw is None:  # IA caida: no filtramos
        return messages
    nums = set(re.findall(r"\d+", raw))
    if not nums or nums == {"0"}:  # la IA dice que ninguno es importante
        return []
    idx = {int(n) for n in nums}
    return [m for i, m in enumerate(messages) if (i + 1) in idx]


def _useful(text: str | None) -> str | None:
    """Filtra respuestas vacias o el sentinel OMITIR (la IA decidio callar)."""
    if not text:
        return None
    t = text.strip()
    if len(t) < 3 or t.upper().replace(".", "").startswith("OMITIR"):
        return None
    return t


def _secs_to_midnight() -> float:
    now = config.now_local()
    tomorrow = (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    return (tomorrow - now).total_seconds()


def _recent_health(session) -> str:
    """Resumen corto del ultimo dia con datos de Apple Health (si hay)."""
    h = session.exec(select(HealthDay).order_by(HealthDay.day.desc()).limit(1)).first()
    if not h:
        return ""
    parts = []
    if h.sleep_hours is not None:
        parts.append(f"durmio {h.sleep_hours:g}h")
    if h.steps is not None:
        parts.append(f"{h.steps} pasos")
    if h.resting_hr is not None:
        parts.append(f"FC reposo {h.resting_hr}")
    if h.active_kcal is not None:
        parts.append(f"{h.active_kcal} kcal activas")
    return ", ".join(parts)


# ── Coach del dia ───────────────────────────────────────────────────────────

def coach_today() -> str | None:
    now = config.now_local()
    with Session(engine) as session:
        habits = session.exec(select(Habit).where(Habit.active == True)).all()  # noqa: E712
        outs = [habit_to_out(session, h) for h in habits]
        pending = [o.name for o in outs if o.due_today and o.category != "diet"]
        from . import seed
        gym_today = seed.routine_by_weekday().get(now.weekday()) or "descanso"
        # tareas/proyectos pendientes, los de fecha limite mas cercana primero
        tasks_open = session.exec(select(Task).where(Task.done == False)).all()  # noqa: E712
        hrow = session.exec(select(HealthDay).order_by(HealthDay.day.desc()).limit(1)).first()
        health = _recent_health(session)

    # ── Gate algoritmico: solo habla si hay algo real ────────────────────────
    sleep = hrow.sleep_hours if hrow else None
    rhr = hrow.resting_hr if hrow else None
    urgent = any(t.due and (t.due.date() - now.date()).days <= 2 for t in tasks_open)
    poor_recovery = (sleep is not None and sleep < 6) or (rhr is not None and rhr >= 70)
    if not (urgent or poor_recovery):
        return None

    def task_label(t):
        if t.due:
            days = (t.due.date() - now.date()).days
            when = "hoy" if days == 0 else f"en {days}d" if days > 0 else f"hace {-days}d (atrasada)"
            return f"{t.text} (limite {when})"
        return t.text

    tasks_open.sort(key=lambda t: (t.due is None, t.due or now))
    tasks_txt = "; ".join(task_label(t) for t in tasks_open[:6]) or "ninguna"

    ctx = (
        f"Rutinas pendientes hoy: {', '.join(pending) or 'ninguna'}. "
        f"Gym hoy: {gym_today}. "
        f"Tareas/proyectos pendientes (con su fecha limite): {tasks_txt}."
    )
    if health:
        ctx += f" Salud (Apple Health, ultimo dia): {health}."
    prompt = (
        "Eres su coach personal (19 anos, estudiante, gimnasio 5 dias, objetivo volumen). Hay algo "
        "que importa hoy: una tarea con deadline cercano o mala recuperacion. Dale UN empujon corto "
        "y util centrado en eso (max 3 frases, tono directo, sin saludos ni emojis, en espanol). Si "
        "hay tarea urgente, dile en cual centrarse; si durmio poco o FC reposo alta, ajusta la "
        "intensidad de hoy." + STYLE + "\n" + ctx
    )
    return _useful(
        ask(prompt, cache_key=f"today-{now.date()}-{len(tasks_open)}-{health}", ttl=_secs_to_midnight())
    )


# ── Analisis post-entreno ───────────────────────────────────────────────────

def coach_workout(workout_id: int) -> str | None:
    from .gym import _est_1rm

    with Session(engine) as session:
        w = session.get(Workout, workout_id)
        if not w:
            return None
        sets = session.exec(select(WorkoutSet).where(WorkoutSet.workout_id == workout_id)).all()
        if not sets:
            return None
        routine = session.get(Routine, w.routine_id) if w.routine_id else None
        by_ex: dict[str, list] = {}
        for s in sets:
            ex = session.get(Exercise, s.exercise_id)
            if ex:
                by_ex.setdefault(ex.name, []).append(f"{s.weight:g}x{s.reps}")
        detail = "; ".join(f"{name}: {', '.join(series)}" for name, series in by_ex.items())
        volume = sum(s.weight * s.reps for s in sets)

        # ── Gate algoritmico: PR o cambio de volumen >=12% vs el ultimo entreno ──
        has_pr = any(getattr(s, "pr", None) for s in sets)
        prev_stmt = select(Workout).where(
            Workout.finished_at != None, Workout.id != workout_id  # noqa: E711
        )
        if w.routine_id:
            prev_stmt = prev_stmt.where(Workout.routine_id == w.routine_id)
        prev = session.exec(prev_stmt.order_by(Workout.started_at.desc())).first()
        prev_vol = 0.0
        if prev:
            psets = session.exec(select(WorkoutSet).where(WorkoutSet.workout_id == prev.id)).all()
            prev_vol = sum(s.weight * s.reps for s in psets)
        notable = has_pr or prev_vol == 0 or abs(volume - prev_vol) / prev_vol >= 0.12
        if not notable:
            return None

        health = _recent_health(session)

    health_txt = f" Salud reciente (Apple Health): {health}." if health else ""
    vs = f" El anterior fue {prev_vol:.0f} kg." if prev_vol else ""
    prompt = (
        "Eres su coach de gym (entrena al fallo, 6-8 repes, objetivo volumen). "
        f"Acabas de terminar este entreno ({routine.name if routine else 'libre'}, "
        f"volumen {volume:.0f} kg): {detail}.{vs}{health_txt} "
        "Dale un analisis MUY breve (max 2 frases): destaca lo concreto de ESTE entreno (PR, "
        "subida/bajada de volumen, descompensacion) y un consejo accionable. Tono directo, sin "
        "emojis, en espanol." + STYLE
    )
    return _useful(ask(prompt, cache_key=f"workout-{workout_id}", ttl=30 * 86400))


# ── Consejo de nutricion ────────────────────────────────────────────────────

def coach_macros(kcal: int, kcal_target: int, protein: float, protein_target: float) -> str | None:
    now = config.now_local()
    # ── Gate algoritmico: solo habla si vas claramente desviado a estas horas ──
    ratio_k = kcal / kcal_target if kcal_target else 0
    ratio_p = protein / protein_target if protein_target else 0
    hour = now.hour
    behind = hour >= 17 and (ratio_p < 0.6 or ratio_k < 0.6)  # tarde y muy corto
    over = ratio_k > 1.12  # pasado de calorias
    if not (behind or over):
        return None

    prompt = (
        f"Llevas hoy {kcal} de {kcal_target} kcal y {protein:.0f} de {protein_target:.0f} g de "
        "proteina (objetivo volumen). " + (
            "Vas corto para la hora que es: dame 1-2 frases con un ejemplo de alimento para llegar."
            if behind else
            "Te has pasado de calorias: dimelo en 1 frase, sin dramatizar."
        ) + " Sin emojis, en espanol, directo." + STYLE
    )
    bucket = f"{kcal // 150}-{int(protein) // 15}"  # agrupa para cachear
    return _useful(ask(prompt, cache_key=f"macros-{now.date()}-{bucket}", ttl=2 * 3600))


# ── Comentario de la cartera ────────────────────────────────────────────────

def coach_finance() -> str | None:
    from . import portfolio

    s = portfolio.get_summary()
    if s.get("status") != "ok":
        return None
    al = portfolio.get_alpaca_overview()
    bv = portfolio.get_bitvavo_overview()

    # ── Gate algoritmico: solo habla si hubo un movimiento que merezca comentar ─
    def notable(o):
        if o.get("status") != "ok":
            return False
        if abs(o.get("day_change_pct") or 0) >= 1.5:
            return True
        return any(abs(p.get("day_pct") or 0) >= 4 for p in (o.get("positions") or []))

    if not (notable(al) or notable(bv)):
        return None

    def movers(o):
        if o.get("status") != "ok":
            return ""
        ps = o.get("positions") or []
        return ", ".join(f"{p['symbol']} {p.get('day_pct', 0):+.1f}%" for p in ps[:4])

    ctx = (
        f"Patrimonio total {s.get('total_eur')} EUR. "
        f"Alpaca (USD, paper) {s.get('alpaca_usd')} ({(al.get('day_change_pct') or 0):+.1f}% hoy): "
        f"{movers(al) or 'sin posiciones'}. "
        f"Bitvavo (EUR, real) {s.get('bitvavo_eur')}: {movers(bv) or 'sin posiciones'}."
    )
    prompt = (
        "Hoy tu cartera ha tenido un movimiento destacable. Resumelo en 1-2 frases: que se ha "
        "movido y por que. En espanol, directo, sin emojis ni saludos. NO des consejo de inversion "
        "ni de compra/venta; solo describe." + STYLE + "\n" + ctx
    )
    now = config.now_local()
    bucket = round((s.get("total_eur") or 0) / 50)  # agrupa para cachear
    return _useful(ask(prompt, cache_key=f"finance-{now.date()}-{bucket}", ttl=2 * 3600))


# ── Resumen de correo ───────────────────────────────────────────────────────

def coach_mail() -> str | None:
    from . import google_client

    m = google_client.get_mail_overview()
    if m.get("status") != "ok":
        return None
    msgs = m.get("messages") or []
    if not msgs:
        return None
    lines = "\n".join(
        f"- De {x.get('from', '')}: {x.get('subject', '')} — {x.get('snippet', '')[:140]}"
        for x in msgs[:8]
    )
    prompt = (
        "Estos son tus correos sin leer ya filtrados (sin suscripciones). Resumelos en 1-2 frases "
        "y di si alguno necesita respuesta o accion concreta (cual y que hacer). Espanol, directo, "
        "sin emojis ni saludos." + STYLE + "\n" + lines
    )
    now = config.now_local()
    sig = abs(hash(lines)) % 100000  # cambia el cache si cambian los correos
    return _useful(ask(prompt, cache_key=f"mail-{now.date()}-{sig}", ttl=3600))


# ── Detección de eventos en correo ──────────────────────────────────────────

def detect_events_from_mail() -> list[dict]:
    import uuid
    from datetime import date
    from . import google_client

    overview = google_client.get_mail_overview()
    msgs = overview.get("messages") or []
    if not msgs:
        return []

    today = date.today().isoformat()
    mail_json = json.dumps(
        [{"subject": m.get("subject", ""), "snippet": m.get("snippet", "")[:200]}
         for m in msgs[:20]],
        ensure_ascii=False,
    )

    prompt = (
        f"Hoy es {today}. Aqui tienes correos no leidos recientes en JSON.\n"
        "Para cada correo con un evento CONCRETO (reunion, cita, cena, plazo, entrevista, "
        "concierto, viaje...) extrae el evento. Ignora newsletters, facturas y correos sin fecha.\n"
        f"Correos:\n{mail_json}\n\n"
        "Devuelve SOLO un JSON exactamente asi (sin texto extra):\n"
        '{"events": [{"id":"<uuid>","title":"<max 6 palabras>","start_iso":"2026-07-15T19:00:00",'
        '"end_iso":null,"location":null,"confidence":0.85,"source_snippet":"<fragmento>"}]}\n'
        f'Si no hay eventos concretos devuelve {{"events": []}}.'
    )

    raw = ask(prompt, cache_key=f"mail-events-{today}", ttl=1800)
    if not raw:
        return []

    # Gemini a veces envuelve el JSON en ```json ... ```
    match = re.search(r"\{.*\}", raw, re.DOTALL)
    if not match:
        return []
    try:
        data = json.loads(match.group())
    except Exception:
        return []

    events = data.get("events", [])
    for e in events:
        if not e.get("id"):
            e["id"] = str(uuid.uuid4())

    # Solo eventos futuros (hoy inclusive)
    return [e for e in events if not e.get("start_iso") or e["start_iso"][:10] >= today][:10]
