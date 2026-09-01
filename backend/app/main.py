import os
import secrets
from contextlib import asynccontextmanager
from datetime import datetime, timedelta

from apscheduler.schedulers.background import BackgroundScheduler
from fastapi import BackgroundTasks, FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from sqlmodel import Session, select

from . import ai, auth, briefing, config, diet, food, google_client, gym, health, icloud_client, portfolio, profile, push, seed, studies, study_coach, tasks
from .db import engine, init_db
from .models import Habit, HabitLog
from .schemas import HabitCreate, HabitOut, HabitUpdate
from .scheduler import check_reminders
from .stats import habit_to_out

scheduler = BackgroundScheduler()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    seed.run()
    seed.add_diet_habits()
    seed.add_gym_exercises()
    seed.add_real_routines()
    seed.add_summer_routines()  # rutinas de verano (Front/Back), idempotente
    seed.migrate_hombro_gemelo()  # añade Face pull y Calf Raise on Leg Press
    seed.mark_seeded()  # a partir de aqui no se recrean los ejemplos borrados
    scheduler.add_job(check_reminders, "cron", minute="*")
    # Precarga los datos de Epitech por la manana para que la pestana abra al instante
    scheduler.add_job(studies.prefetch, "cron", hour=8, minute=30)
    # Mensajes proactivos de Telegram
    scheduler.add_job(briefing.morning_briefing, "cron", hour=8, minute=0)
    scheduler.add_job(briefing.night_summary, "cron", hour=21, minute=30)
    scheduler.add_job(briefing.check_portfolio_drop, "cron", minute="*/30")
    scheduler.add_job(briefing.weekly_summary, "cron", day_of_week="sun", hour=21, minute=0)
    scheduler.start()
    yield
    scheduler.shutdown()


app = FastAPI(title="Life Hub", lifespan=lifespan)
app.include_router(gym.router)
app.include_router(food.router)
app.include_router(tasks.router)
app.include_router(push.router)
app.include_router(health.router)
app.include_router(diet.router)
app.include_router(profile.router)

# Clave unica de acceso a la API (app personal de un solo usuario). Si no
# esta definida (dev local) la API queda abierta; en el servidor es
# OBLIGATORIA: sin ella cualquiera podria leer correo/agenda/cartera.
APP_PASSWORD = config.load_env().get("APP_PASSWORD", "")


# El callback de Google lo abre el navegador tras el consentimiento: no puede
# llevar el Bearer, asi que se deja publico (solo intercambia el code por token).
PUBLIC_PATHS = {"/api/auth/google/callback"}


@app.middleware("http")
async def security(request, call_next):
    path = request.url.path
    if path.startswith("/api/") and APP_PASSWORD and path not in PUBLIC_PATHS:
        ok = False
        # Los endpoints del reloj (/api/gym/device/*) aceptan un token de
        # dispositivo propio (X-Device-Token), para no meter la contrasena
        # principal en el firmware/app del sensor.
        if path.startswith("/api/gym/device/"):
            dtok = config.load_env().get("GYM_DEVICE_TOKEN", "")
            provided = request.headers.get("x-device-token", "")
            if dtok and secrets.compare_digest(provided.encode(), dtok.encode()):
                ok = True
        if not ok:
            header = request.headers.get("authorization", "")
            token = header[7:] if header.startswith("Bearer ") else ""
            # las <img> de fotos no pueden mandar header: aceptan ?token= en la URL
            if not token:
                token = request.query_params.get("token", "")
            if secrets.compare_digest(token.encode(), APP_PASSWORD.encode()):
                ok = True
        if not ok:
            return JSONResponse({"detail": "No autorizado"}, status_code=401)
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    return response


@app.get("/api/today", response_model=list[HabitOut])
def get_today():
    with Session(engine) as session:
        habits = session.exec(select(Habit).where(Habit.active == True)).all()
        out = [habit_to_out(session, h) for h in habits]
        # Pendientes primero, ordenados por la proxima hora del dia
        out.sort(key=lambda h: (not h.due_today, h.next_time or "00:00", h.name))
        return out


@app.get("/api/habits", response_model=list[HabitOut])
def list_habits():
    with Session(engine) as session:
        habits = session.exec(select(Habit)).all()
        return [habit_to_out(session, h) for h in habits]


@app.post("/api/habits", response_model=HabitOut)
def create_habit(payload: HabitCreate):
    with Session(engine) as session:
        habit = Habit(**payload.model_dump())
        session.add(habit)
        session.commit()
        session.refresh(habit)
        return habit_to_out(session, habit)


@app.patch("/api/habits/{habit_id}", response_model=HabitOut)
def update_habit(habit_id: int, payload: HabitUpdate):
    with Session(engine) as session:
        habit = session.get(Habit, habit_id)
        if not habit:
            raise HTTPException(404, "No encontrada")
        for key, value in payload.model_dump(exclude_unset=True).items():
            setattr(habit, key, value)
        session.add(habit)
        session.commit()
        session.refresh(habit)
        return habit_to_out(session, habit)


@app.delete("/api/habits/{habit_id}")
def delete_habit(habit_id: int):
    with Session(engine) as session:
        habit = session.get(Habit, habit_id)
        if not habit:
            raise HTTPException(404, "No encontrada")
        session.delete(habit)
        session.commit()
        return {"status": "deleted"}


@app.post("/api/habits/{habit_id}/done")
def mark_done(habit_id: int):
    with Session(engine) as session:
        habit = session.get(Habit, habit_id)
        if not habit:
            raise HTTPException(404, "No encontrada")
        log = HabitLog(habit_id=habit_id)
        session.add(log)
        session.commit()
        session.refresh(log)
        return habit_to_out(session, habit)


@app.post("/api/habits/{habit_id}/undo")
def undo_done(habit_id: int):
    """Borra el ultimo log de hoy (deshacer un 'hecho' accidental)."""
    with Session(engine) as session:
        habit = session.get(Habit, habit_id)
        if not habit:
            raise HTTPException(404, "No encontrada")
        today = config.now_local().date()
        logs = session.exec(
            select(HabitLog)
            .where(HabitLog.habit_id == habit_id)
            .order_by(HabitLog.done_at.desc())
        ).all()
        target = next((l for l in logs if config.to_local(l.done_at).date() == today), None)
        if not target:
            raise HTTPException(404, "Nada que deshacer hoy")
        session.delete(target)
        session.commit()
        return habit_to_out(session, habit)


@app.delete("/api/habits/{habit_id}/logs/{log_id}")
def delete_log(habit_id: int, log_id: int):
    with Session(engine) as session:
        log = session.get(HabitLog, log_id)
        if not log or log.habit_id != habit_id:
            raise HTTPException(404, "No encontrado")
        habit = session.get(Habit, habit_id)
        session.delete(log)
        session.commit()
        return habit_to_out(session, habit)


@app.get("/api/habits/{habit_id}/history")
def habit_history(habit_id: int, days: int = 30):
    with Session(engine) as session:
        since = datetime.utcnow() - timedelta(days=days)
        logs = session.exec(
            select(HabitLog)
            .where(HabitLog.habit_id == habit_id, HabitLog.done_at >= since)
            .order_by(HabitLog.done_at.desc())
        ).all()
        return logs


@app.get("/api/studies")
def get_studies(refresh: bool = False):
    return studies.get_overview(force=refresh)


@app.get("/api/mail")
def get_mail():
    return google_client.get_mail_overview()


@app.get("/api/calendar")
def get_calendar():
    return icloud_client.get_calendar_overview()


@app.get("/api/finance/alpaca")
def finance_alpaca():
    return portfolio.get_alpaca_overview()


@app.get("/api/finance/bitvavo")
def finance_bitvavo():
    return portfolio.get_bitvavo_overview()


@app.get("/api/finance/summary")
def finance_summary():
    return portfolio.get_summary()


@app.get("/api/ai/today")
def ai_today():
    return {"text": ai.coach_today()}


@app.get("/api/ai/workout/{workout_id}")
def ai_workout(workout_id: int):
    return {"text": ai.coach_workout(workout_id)}


@app.get("/api/ai/macros")
def ai_macros(kcal: int, kcal_target: int, protein: float, protein_target: float):
    return {"text": ai.coach_macros(kcal, kcal_target, protein, protein_target)}


@app.get("/api/ai/studies")
def ai_studies():
    return {"text": study_coach.coach()}


@app.get("/api/ai/finance")
def ai_finance():
    return {"text": ai.coach_finance()}


@app.get("/api/ai/mail")
def ai_mail():
    return {"text": ai.coach_mail()}


@app.get("/api/ai/mail-events")
def ai_mail_events():
    return {"events": ai.detect_events_from_mail()}


@app.post("/api/calendar/events")
def create_calendar_event(body: dict):
    title    = body.get("title", "Evento")
    start    = body.get("start_iso")
    end      = body.get("end_iso")
    location = body.get("location")
    if not start:
        raise HTTPException(400, "start_iso requerido")
    try:
        icloud_client.create_event(title, start, end, location)
        return {"status": "ok", "link": None}
    except Exception as e:
        raise HTTPException(500, str(e))


@app.post("/api/ai/prewarm")
def ai_prewarm(background: BackgroundTasks):
    """Genera en segundo plano las respuestas de IA del dia para que la cache
    este lista (se llama al abrir la app la primera vez cada dia)."""
    background.add_task(ai.coach_today)
    background.add_task(ai.coach_finance)
    background.add_task(ai.coach_mail)
    background.add_task(study_coach.coach)
    return {"status": "warming"}


@app.get("/api/auth/status")
def auth_status():
    return auth.status()


@app.get("/api/auth/google/url")
def auth_google_url():
    return {"url": auth.consent_url()}


@app.get("/api/auth/google/callback")
def auth_google_callback(code: str = "", error: str = ""):
    ok = auth.handle_callback(code) if code else False
    return RedirectResponse(url=f"/?google={'ok' if ok else 'fail'}")



FRONTEND_DIST = os.path.join(os.path.dirname(__file__), "..", "..", "frontend", "dist")
if os.path.isdir(FRONTEND_DIST):
    app.mount("/assets", StaticFiles(directory=os.path.join(FRONTEND_DIST, "assets")), name="assets")

    @app.get("/{full_path:path}")
    def spa(full_path: str):
        # realpath + prefijo: sin esto, un "../" codificado en la URL
        # serviria archivos de fuera de dist/ (.env, token.json, life.db)
        root = os.path.realpath(FRONTEND_DIST)
        file_path = os.path.realpath(os.path.join(root, full_path))
        if full_path and file_path.startswith(root + os.sep) and os.path.isfile(file_path):
            return FileResponse(file_path)
        return FileResponse(os.path.join(root, "index.html"))
