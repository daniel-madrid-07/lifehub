"""Mensajes proactivos de Telegram (jobs de APScheduler, ver main.py):

- 08:00  briefing matinal: rutinas de hoy, agenda + cumpleanos, correos
         importantes y estado de la cartera.
- 21:30  resumen nocturno: SOLO si quedan rutinas sin marcar (un mensaje,
         no spam).
- cada 30 min  alerta de cartera: Alpaca <= -3% o Bitvavo <= -5% en el dia
         (maximo una vez al dia).

Cada seccion va en try/except: si un modulo externo falla, el mensaje sale
sin esa seccion en vez de no salir.
"""
import html
import re
from datetime import datetime, timedelta

import requests
from sqlmodel import Session, select

from . import config, google_client, gym, icloud_client, notify, portfolio, seed, tasks
from .db import engine
from .models import BodyWeight, Exercise, Habit, Routine, RoutineExercise, Workout, WorkoutSet
from .stats import habit_to_out

ALPACA_DROP_PCT = -3.0
BITVAVO_DROP_PCT = -5.0

# Madrid (para el clima del briefing)
MADRID_LAT, MADRID_LON = 40.4168, -3.7038

# Frases de empuje (una por dia, deterministica)
PHRASES = [
    "Disciplina sobre motivación. Hazlo igual.",
    "Hoy una rep más que ayer.",
    "El progreso es aburrido. Confía en el proceso.",
    "Nadie va a hacerlo por ti. Vamos.",
    "Pequeños hábitos, grandes resultados.",
    "El dolor de hoy es la fuerza de mañana.",
    "Constancia, no intensidad puntual.",
    "Eres lo que repites cada día.",
    "Sin prisa pero sin pausa.",
    "Gana el día. Luego repite.",
    "Lo difícil es lo que vale la pena.",
    "Cierra el día mejor de como lo empezaste.",
]

_last_drop_alert_day: str | None = None


def _esc(s: str) -> str:
    return html.escape(str(s))


def morning_briefing():
    now = config.now_local()
    date_label = now.strftime("%A %d/%m")
    sections = [f"<b>Buenos días</b> — {date_label}"]

    for builder in (_weather_section, _gym_section, _habit_section, _agenda_section,
                    _tasks_section, _mail_section, _portfolio_section):
        try:
            block = builder(now)
            if block:
                sections.append(block)
        except Exception:
            pass  # una seccion que falle no tumba el briefing

    # frase de empuje (una por dia)
    sections.append("<i>" + _esc(PHRASES[now.timetuple().tm_yday % len(PHRASES)]) + "</i>")

    notify.notify("\n\n".join(sections))


def weekly_summary():
    """Domingo por la noche: cierre de semana + foco de la siguiente."""
    sections = ["<b>Resumen de la semana</b>"]
    for builder in (_week_gym, _week_habits, _week_bodyweight, _week_portfolio):
        try:
            block = builder()
            if block:
                sections.append(block)
        except Exception:
            pass
    if len(sections) == 1:
        sections.append("Semana tranquila, sin datos que destacar.")
    try:
        coach = _week_coach(sections)
        if coach:
            sections.append("<i>" + _esc(coach) + "</i>")
    except Exception:
        pass
    notify.notify("\n\n".join(sections))


def _week_coach(sections: list[str]) -> str | None:
    """Cierre de IA: como fue la semana y en que centrarse la proxima."""
    from . import ai, study_coach

    # contexto: lo ya recopilado arriba (gym, rachas, peso, cartera) en texto plano
    plain = re.sub(r"<[^>]+>", "", "\n".join(sections[1:]))

    # tareas/proyectos pendientes con fecha
    now = config.now_local()
    with Session(engine) as session:
        from .models import Task
        open_tasks = session.exec(select(Task).where(Task.done == False)).all()  # noqa: E712
    open_tasks.sort(key=lambda t: (t.due is None, t.due or now))
    tasks_txt = "; ".join(t.text for t in open_tasks[:5]) or "ninguna"

    # estudios: proyecto activo + deadline (si hay)
    study = ""
    try:
        meta, repo = study_coach._pick(study_coach._env())
        if meta and meta.get("deadline"):
            study = f"Proyecto Epitech: {meta.get('title')} (entrega {meta['deadline']})."
    except Exception:
        pass

    ctx = f"{plain}\nTareas pendientes: {tasks_txt}. {study}"
    prompt = (
        "Eres su coach (estudiante Epitech, gym 5 dias, objetivo volumen). Con el resumen de tu "
        "semana, escribe 2-3 frases: una valoracion honesta de como fue y EN QUE deberias "
        "centrarte la semana que viene (gym, estudios o lo que mas urja). Hablale de TU (tu/te/tus), "
        "NUNCA en tercera persona ni digas su nombre. Tono directo, sin emojis ni saludos, en "
        "espanol.\n" + ctx
    )
    return ai.ask(prompt, cache_key=f"weekly-{now.date()}", ttl=2 * 86400)


def _week_gym() -> str | None:
    since = datetime.utcnow() - timedelta(days=7)
    with Session(engine) as session:
        workouts = session.exec(
            select(Workout).where(
                Workout.finished_at != None, Workout.started_at >= since  # noqa: E711
            )
        ).all()
        if not workouts:
            return "<b>Gym</b>: 0 entrenos esta semana"
        wids = [w.id for w in workouts]
        sets = session.exec(select(WorkoutSet).where(WorkoutSet.workout_id.in_(wids))).all()
        volume = sum(s.weight * s.reps for s in sets)
        by_muscle: dict[str, int] = {}
        for s in sets:
            ex = session.get(Exercise, s.exercise_id)
            if ex:
                by_muscle[ex.muscle] = by_muscle.get(ex.muscle, 0) + 1
        top = sorted(by_muscle.items(), key=lambda x: -x[1])[:3]
        muscles = ", ".join(f"{m} ({n})" for m, n in top)
        return (
            f"<b>Gym</b>: {len(workouts)} entrenos · {len(sets)} series · "
            f"{volume:,.0f} kg de volumen\nMas trabajado: {_esc(muscles)}"
        )


def _week_habits() -> str | None:
    with Session(engine) as session:
        habits = session.exec(
            select(Habit).where(Habit.active == True, Habit.category != "exercise")  # noqa: E712
        ).all()
        streaks = []
        for h in habits:
            out = habit_to_out(session, h)
            if out.streak >= 3:
                streaks.append((h.name, out.streak))
    streaks.sort(key=lambda x: -x[1])
    if not streaks:
        return None
    lines = [f"• {_esc(n)}: {s} dias" for n, s in streaks[:4]]
    return "<b>Rachas</b>\n" + "\n".join(lines)


def _week_bodyweight() -> str | None:
    since = datetime.utcnow() - timedelta(days=8)
    with Session(engine) as session:
        rows = session.exec(
            select(BodyWeight).where(BodyWeight.at >= since).order_by(BodyWeight.at)
        ).all()
    if len(rows) < 2:
        return None
    delta = rows[-1].weight - rows[0].weight
    arrow = "+" if delta >= 0 else ""
    return f"<b>Peso</b>: {rows[-1].weight:g} kg ({arrow}{delta:.1f} esta semana)"


def _week_portfolio() -> str | None:
    summary = portfolio.get_summary()
    if summary.get("status") != "ok" or summary.get("total_eur") is None:
        return None
    line = f"<b>Cartera</b>: {summary['total_eur']:,.0f} EUR total"
    hist = summary.get("history") or []
    week = [h for h in hist if h.get("total_eur") is not None][-7:]
    if len(week) >= 2:
        delta = week[-1]["total_eur"] - week[0]["total_eur"]
        arrow = "+" if delta >= 0 else ""
        line += f" ({arrow}{delta:,.0f} esta semana)"
    return line


def _weather_section(now) -> str | None:
    r = requests.get(
        "https://api.open-meteo.com/v1/forecast",
        params={
            "latitude": MADRID_LAT, "longitude": MADRID_LON,
            "current": "temperature_2m,weather_code",
            "daily": "temperature_2m_max,temperature_2m_min,precipitation_probability_max",
            "timezone": "Europe/Madrid", "forecast_days": 1,
        },
        timeout=15,
    )
    r.raise_for_status()
    d = r.json()
    cur = d.get("current", {})
    daily = d.get("daily", {})
    temp = round(cur.get("temperature_2m", 0))
    tmax = round(daily.get("temperature_2m_max", [0])[0])
    tmin = round(daily.get("temperature_2m_min", [0])[0])
    rain = daily.get("precipitation_probability_max", [0])[0]
    desc = _weather_desc(cur.get("weather_code", 0))
    line = f"<b>Madrid</b>: {temp}° ahora · {desc} · {tmin}–{tmax}°"
    if rain and rain >= 30:
        line += f" · lluvia {rain}%"
    return line


def _gym_section(now) -> str | None:
    name = seed.routine_by_weekday().get(now.weekday())
    if not name:
        return None  # hoy descanso
    with Session(engine) as session:
        routine = session.exec(select(Routine).where(Routine.name == name)).first()
        if not routine:
            return f"<b>Gym hoy</b>: {_esc(name)}"
        items = session.exec(
            select(RoutineExercise).where(RoutineExercise.routine_id == routine.id)
            .order_by(RoutineExercise.position)
        ).all()
        ex_names = []
        first_rec = None
        for i, it in enumerate(items):
            ex = session.get(Exercise, it.exercise_id)
            if not ex:
                continue
            ex_names.append(ex.name)
            if i == 0:
                rec = gym._recommend(session, ex, it.reps_min, it.reps_max)
                if rec.get("weight"):
                    first_rec = f"{ex.name}: {rec['weight']:g} kg × {rec['reps']}"
    text = f"<b>Gym hoy</b>: {_esc(name)}\n" + _esc(", ".join(ex_names[:6]))
    if first_rec:
        text += f"\nEmpieza con {_esc(first_rec)}"
    return text


def _habit_section(now) -> str | None:
    lines = _habit_lines()
    return "<b>Rutinas de hoy</b>\n" + "\n".join(lines) if lines else None


def _agenda_section(now) -> str | None:
    lines = _agenda_lines(now.date().isoformat())
    return "<b>Agenda</b>\n" + "\n".join(lines) if lines else None


def _tasks_section(now) -> str | None:
    lines = tasks.pending_task_lines()
    return "<b>Pendientes</b>\n" + "\n".join(lines) if lines else None


def _mail_section(now) -> str | None:
    mail = google_client.get_mail_overview()
    msgs = mail.get("messages") or []
    if mail.get("status") != "ok" or not msgs:
        return None
    lines = [f"• {_esc(m['subject'])}" for m in msgs[:3]]
    extra = f" (+{len(msgs) - 3} más)" if len(msgs) > 3 else ""
    return f"<b>Correo</b>: {len(msgs)} importantes{extra}\n" + "\n".join(lines)


def _portfolio_section(now) -> str | None:
    lines = _portfolio_lines()
    return "<b>Cartera</b>\n" + "\n".join(lines) if lines else None


def _weather_desc(code: int) -> str:
    if code == 0:
        return "despejado"
    if code in (1, 2):
        return "poco nublado"
    if code == 3:
        return "nublado"
    if code in (45, 48):
        return "niebla"
    if 51 <= code <= 67:
        return "llovizna"
    if 71 <= code <= 77:
        return "nieve"
    if 80 <= code <= 82:
        return "chubascos"
    if 95 <= code <= 99:
        return "tormenta"
    return "lluvia"


def night_summary():
    try:
        pending = []
        with Session(engine) as session:
            habits = session.exec(select(Habit).where(Habit.active == True)).all()  # noqa: E712
            for habit in habits:
                out = habit_to_out(session, habit)
                if out.due_today:
                    pending.append(f"• {_esc(habit.name)} — {_esc(out.progress_label)}")
        if not pending:
            return  # todo hecho: no molestar
        text = "<b>Antes de dormir</b> — te queda:\n" + "\n".join(pending)
        notify.notify(text)
    except Exception:
        pass


def check_portfolio_drop():
    global _last_drop_alert_day
    today = config.now_local().date().isoformat()
    if _last_drop_alert_day == today:
        return
    alerts = []
    try:
        a = portfolio.get_alpaca_overview()
        if a.get("status") == "ok" and a.get("day_change_pct", 0) <= ALPACA_DROP_PCT:
            alerts.append(
                f"• Alpaca: {a['day_change_pct']:+.1f}% hoy ({a['equity']:,.0f} US$)"
            )
    except Exception:
        pass
    try:
        b = portfolio.get_bitvavo_overview()
        if b.get("status") == "ok" and b.get("day_change_pct", 0) <= BITVAVO_DROP_PCT:
            alerts.append(f"• Bitvavo: {b['day_change_pct']:+.1f}% hoy ({b['equity']:,.2f} €)")
    except Exception:
        pass
    if alerts:
        _last_drop_alert_day = today
        notify.notify("<b>Ojo a la cartera</b>\n" + "\n".join(alerts))


def _habit_lines() -> list[str]:
    lines = []
    with Session(engine) as session:
        habits = session.exec(select(Habit).where(Habit.active == True)).all()  # noqa: E712
        outs = [habit_to_out(session, h) for h in habits]
    outs = [o for o in outs if o.due_today]
    outs.sort(key=lambda o: o.next_time or "00:00")
    for o in outs:
        when = f" ({o.next_time})" if o.next_time else ""
        lines.append(f"• {_esc(o.name)}{when}")
    return lines


def _agenda_lines(today_iso: str) -> list[str]:
    cal = icloud_client.get_calendar_overview()
    if cal.get("status") != "ok":
        return []
    lines = []
    for e in cal.get("events", []):
        start = e.get("start") or ""
        if not start.startswith(today_iso):
            continue
        if "T" in start:
            hhmm = start.split("T")[1][:5]
            lines.append(f"• {hhmm} {_esc(e['title'])}")
        else:
            lines.append(f"• {_esc(e['title'])}")
    return lines


def _portfolio_lines() -> list[str]:
    lines = []
    a = portfolio.get_alpaca_overview()
    if a.get("status") == "ok":
        lines.append(f"• Alpaca: {a['equity']:,.0f} US$ ({a['day_change_pct']:+.1f}%)")
    b = portfolio.get_bitvavo_overview()
    if b.get("status") == "ok":
        lines.append(f"• Bitvavo: {b['equity']:,.2f} €")
    return lines
