"""Modulo Gym (tipo Hevy): rutinas de ejercicios, registro de series
(peso x repes), progreso por ejercicio y recomendacion de peso.

Algoritmo de recomendacion — calibrado para Daniel (junio 2026), que lleva
TODAS las series al fallo:
- Doble progresion sobre la ultima sesion, rango por defecto 6-8 repes.
- Sube peso solo si la MEJOR serie llego a reps_max Y la ULTIMA serie
  (la mas fatigada) no se cayo del minimo — al fallo la caida entre series
  es normal y no debe disparar subidas prematuras.
- El peso nuevo se calcula desde el 1RM estimado (media de Epley y
  Brzycki, mas estable que una sola formula) apuntando a reps_min, y se
  predicen las repes que deberian salir con el peso nuevo.
- Saltos disponibles en su gym: 1 kg en barra/maquina/polea (hay
  microdiscos), 2,5 kg en mancuernas. Peso corporal progresa por repes y
  sugiere lastre al superar el rango.
- Estancamiento (2 sesiones al mismo peso sin mejorar repes ni volumen):
  SOLO avisa (eleccion suya), sugiriendo el deload del 10% como opcion.
"""
import os
import uuid
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from . import config, seed
from .db import engine
from .models import (
    BodyMeasure,
    BodyWeight,
    Exercise,
    Habit,
    HabitLog,
    ProgressPhoto,
    Routine,
    RoutineExercise,
    Workout,
    WorkoutSet,
)
from .stats import habit_to_out

PHOTOS_DIR = os.path.join(os.path.dirname(__file__), "..", "photos")
MEASURE_SITES = {"brazo", "pecho", "cintura", "pierna"}

router = APIRouter(prefix="/api/gym")


# ── Schemas ────────────────────────────────────────────────────────────────

class ExerciseIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    muscle: str = Field(min_length=1, max_length=50)
    equipment: str = Field(default="barra", max_length=50)


class RoutineExerciseIn(BaseModel):
    exercise_id: int
    sets: int = Field(default=2, ge=1, le=12)
    reps_min: int = Field(default=6, ge=1, le=100)
    reps_max: int = Field(default=8, ge=1, le=100)


class RoutineIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    exercises: list[RoutineExerciseIn] = []


class WorkoutStart(BaseModel):
    routine_id: Optional[int] = None


class SetIn(BaseModel):
    exercise_id: int
    weight: float = Field(ge=0, le=2000)
    reps: int = Field(ge=1, le=500)


class BodyWeightIn(BaseModel):
    weight: float = Field(gt=20, lt=400)


# ── Helpers ────────────────────────────────────────────────────────────────

# Salto minimo de peso por material (respuestas de Daniel sobre su gym)
EQUIPMENT_STEP = {"mancuernas": 2.5}
DEFAULT_STEP = 1.0  # barra/maquina/polea: hay microdiscos, saltos de 1 kg
LASTRE_STEP = 2.5  # lastre sugerido en ejercicios de peso corporal
DEFAULT_SETS = 2  # Daniel hace 2 series de todo
DEFAULT_REPS_MIN = 6
DEFAULT_REPS_MAX = 8


def _est_1rm(weight: float, reps: int) -> float:
    """Media de Epley y Brzycki: mas estable que cualquiera de las dos sola."""
    if weight <= 0 or reps <= 0:
        return 0.0
    r = min(reps, 30)
    epley = weight * (1 + r / 30)
    brzycki = weight * 36 / (37 - r)
    return round((epley + brzycki) / 2, 1)


def _weight_for_reps(rm: float, target_reps: int) -> float:
    """Peso al que el 1RM estimado da ~target_reps (inversa de la media)."""
    epley = rm / (1 + target_reps / 30)
    brzycki = rm * (37 - target_reps) / 36
    return (epley + brzycki) / 2


def _reps_at(rm: float, weight: float) -> int:
    """Repes esperadas con `weight` dado un 1RM: la mayor r cuyo 1RM estimado
    no supera rm (mismo modelo Epley+Brzycki, sin inconsistencias)."""
    if weight <= 0 or rm <= 0:
        return 0
    reps = 0
    for cand in range(1, 31):
        if _est_1rm(weight, cand) <= rm:
            reps = cand
        else:
            break
    return reps


def _round_to(x: float, step: float) -> float:
    return round(round(x / step) * step, 2)


def _step_for(exercise: Exercise) -> float:
    return EQUIPMENT_STEP.get(exercise.equipment, DEFAULT_STEP)


def _last_sessions(session: Session, exercise_id: int, n: int = 2) -> list[list[WorkoutSet]]:
    """Series de los ultimos n entrenos TERMINADOS con este ejercicio,
    el mas reciente primero, cada uno en orden de serie."""
    rows = session.exec(
        select(WorkoutSet)
        .join(Workout, Workout.id == WorkoutSet.workout_id)
        .where(WorkoutSet.exercise_id == exercise_id, Workout.finished_at != None)  # noqa: E711
        .order_by(Workout.started_at.desc(), WorkoutSet.set_number)
    ).all()
    sessions: list[list[WorkoutSet]] = []
    for s in rows:
        if not sessions or sessions[-1][0].workout_id != s.workout_id:
            if len(sessions) == n:
                break
            sessions.append([])
        sessions[-1].append(s)
    return sessions


def _last_sets(session: Session, exercise_id: int) -> list[WorkoutSet]:
    sessions = _last_sessions(session, exercise_id, 1)
    return sessions[0] if sessions else []


def _detect_stall(sessions: list[list[WorkoutSet]], w0: float, best_reps: int, reps_max: int) -> bool:
    """Estancado = 2 sesiones seguidas al mismo peso sin mejorar ni la mejor
    serie ni el volumen, y sin haber llegado aun al tope del rango."""
    if len(sessions) < 2 or best_reps >= reps_max:
        return False
    prev = sessions[1]
    w_prev = max(s.weight for s in prev)
    if w_prev != w0:
        return False
    prev_best = max(s.reps for s in prev if s.weight == w_prev)
    vol_now = sum(s.weight * s.reps for s in sessions[0])
    vol_prev = sum(s.weight * s.reps for s in prev)
    return best_reps <= prev_best and vol_now <= vol_prev


def _recommend(session: Session, exercise: Exercise, reps_min: int, reps_max: int) -> dict:
    sessions = _last_sessions(session, exercise.id, 2)
    if not sessions:
        return {"weight": None, "reps": reps_min, "note": "", "stall": False}

    last = sessions[0]
    step = _step_for(exercise)
    w0 = max(s.weight for s in last)
    top_sets = [s for s in last if s.weight == w0] or last
    best_reps = max(s.reps for s in top_sets)
    last_set_reps = top_sets[-1].reps
    rm = max(_est_1rm(s.weight, s.reps) for s in last)
    stall = _detect_stall(sessions, w0, best_reps, reps_max)

    # Peso corporal sin lastre: progresa por repes; al tope, mete lastre
    if exercise.equipment == "peso corporal" and w0 == 0:
        if best_reps >= reps_max:
            rec = {
                "weight": LASTRE_STEP,
                "reps": reps_min,
                "note": f"Superaste {reps_max} repes a peso corporal: mete {LASTRE_STEP:g} kg de lastre",
            }
        else:
            rec = {
                "weight": 0,
                "reps": best_reps + 1,
                "note": f"Peso corporal: busca {best_reps + 1} repes al fallo (hiciste {best_reps})",
            }
    elif best_reps >= reps_max and last_set_reps >= reps_min:
        # Tope del rango y la ultima serie aguanta: sube peso apuntando a reps_min
        w1 = max(_round_to(_weight_for_reps(rm, reps_min), step), w0 + step)
        est = _reps_at(rm, w1)
        # si el salto deja la prediccion bajo el minimo, recorta de paso en paso
        while est < reps_min and w1 - step > w0:
            w1 = round(w1 - step, 2)
            est = _reps_at(rm, w1)
        est = max(min(est, reps_max), 1)
        rec = {
            "weight": w1,
            "reps": est,
            "note": f"Sube a {w1:g} kg: con tu 1RM (~{rm:g} kg) deberian salir ~{est} repes",
        }
    elif best_reps >= reps_max:
        # La mejor serie llega pero la ultima se cae del minimo: consolida
        rec = {
            "weight": w0,
            "reps": reps_max,
            "note": f"La primera llega a {best_reps} pero la ultima cae a {last_set_reps}: repite {w0:g} kg y cierra todas sobre {reps_min}",
        }
    elif best_reps < reps_min:
        rec = {
            "weight": w0,
            "reps": reps_min,
            "note": f"Te quedaste en {best_reps} (minimo {reps_min}): repite {w0:g} kg y pelea las repes",
        }
    else:
        rec = {
            "weight": w0,
            "reps": min(best_reps + 1, reps_max),
            "note": f"Mismo peso ({w0:g} kg): la sesion pasada hiciste {best_reps}, busca {min(best_reps + 1, reps_max)}",
        }

    rec["stall"] = stall
    if stall:
        deload = _round_to(w0 * 0.9, step)
        rec["note"] += f" — OJO: 2 sesiones estancado con {w0:g} kg; si vuelve a pasar, valora bajar a {deload:g} kg y coger carrerilla"
    return rec


def _exercise_out(ex: Exercise) -> dict:
    return {
        "id": ex.id,
        "name": ex.name,
        "muscle": ex.muscle,
        "equipment": ex.equipment,
        "custom": ex.custom,
    }


def _set_out(s: WorkoutSet) -> dict:
    return {
        "id": s.id,
        "exercise_id": s.exercise_id,
        "set_number": s.set_number,
        "weight": s.weight,
        "reps": s.reps,
    }


def _workout_detail(session: Session, workout: Workout) -> dict:
    sets = session.exec(
        select(WorkoutSet)
        .where(WorkoutSet.workout_id == workout.id)
        .order_by(WorkoutSet.set_number)
    ).all()
    sets_by_ex: dict[int, list[WorkoutSet]] = {}
    for s in sets:
        sets_by_ex.setdefault(s.exercise_id, []).append(s)

    # Ejercicios del plan: los de la rutina (en orden) + los anadidos sueltos
    plan_items: list[tuple[Exercise, int, int, int]] = []
    seen: set[int] = set()
    if workout.routine_id:
        routine_exs = session.exec(
            select(RoutineExercise)
            .where(RoutineExercise.routine_id == workout.routine_id)
            .order_by(RoutineExercise.position)
        ).all()
        for re_ in routine_exs:
            ex = session.get(Exercise, re_.exercise_id)
            if ex:
                plan_items.append((ex, re_.sets, re_.reps_min, re_.reps_max))
                seen.add(ex.id)
    for ex_id in sets_by_ex:
        if ex_id not in seen:
            ex = session.get(Exercise, ex_id)
            if ex:
                plan_items.append((ex, DEFAULT_SETS, DEFAULT_REPS_MIN, DEFAULT_REPS_MAX))

    routine = session.get(Routine, workout.routine_id) if workout.routine_id else None
    return {
        "id": workout.id,
        "routine_id": workout.routine_id,
        "routine_name": routine.name if routine else None,
        "started_at": workout.started_at,
        "finished_at": workout.finished_at,
        "plan": [
            {
                "exercise": _exercise_out(ex),
                "target_sets": target_sets,
                "reps_min": reps_min,
                "reps_max": reps_max,
                "recommendation": _recommend(session, ex, reps_min, reps_max),
                "last": [
                    {"weight": s.weight, "reps": s.reps} for s in _last_sets(session, ex.id)
                ],
                "sets": [_set_out(s) for s in sets_by_ex.get(ex.id, [])],
            }
            for ex, target_sets, reps_min, reps_max in plan_items
        ],
    }


# ── Ejercicios ─────────────────────────────────────────────────────────────

@router.get("/exercises")
def list_exercises():
    with Session(engine) as session:
        exercises = session.exec(select(Exercise).order_by(Exercise.muscle, Exercise.name)).all()
        return [_exercise_out(e) for e in exercises]


@router.post("/exercises")
def create_exercise(payload: ExerciseIn):
    with Session(engine) as session:
        ex = Exercise(**payload.model_dump(), custom=True)
        session.add(ex)
        session.commit()
        session.refresh(ex)
        return _exercise_out(ex)


@router.get("/exercises/{exercise_id}/recommendation")
def exercise_recommendation(exercise_id: int, reps_min: int = DEFAULT_REPS_MIN, reps_max: int = DEFAULT_REPS_MAX):
    with Session(engine) as session:
        ex = session.get(Exercise, exercise_id)
        if not ex:
            raise HTTPException(404, "Ejercicio no encontrado")
        return {
            "recommendation": _recommend(session, ex, reps_min, reps_max),
            "last": [{"weight": s.weight, "reps": s.reps} for s in _last_sets(session, exercise_id)],
        }


# ── Rutinas ────────────────────────────────────────────────────────────────

def _routine_out(session: Session, routine: Routine) -> dict:
    items = session.exec(
        select(RoutineExercise)
        .where(RoutineExercise.routine_id == routine.id)
        .order_by(RoutineExercise.position)
    ).all()
    exercises = []
    for it in items:
        ex = session.get(Exercise, it.exercise_id)
        if ex:
            exercises.append({
                "exercise_id": ex.id,
                "name": ex.name,
                "muscle": ex.muscle,
                "equipment": ex.equipment,
                "sets": it.sets,
                "reps_min": it.reps_min,
                "reps_max": it.reps_max,
            })
    today_name = seed.routine_by_weekday().get(config.now_local().weekday())
    return {
        "id": routine.id,
        "name": routine.name,
        "today": routine.name == today_name,
        "group": "verano" if routine.name in seed.SUMMER_NAMES else "normal",
        "exercises": exercises,
    }


class RoutineModeIn(BaseModel):
    mode: str


@router.get("/routine-mode")
def routine_mode_get():
    return {"mode": seed.get_routine_mode()}


@router.post("/routine-mode")
def routine_mode_set(payload: RoutineModeIn):
    return {"mode": seed.set_routine_mode(payload.mode)}


@router.get("/routines")
def list_routines():
    with Session(engine) as session:
        routines = session.exec(select(Routine).order_by(Routine.position, Routine.id)).all()
        return [_routine_out(session, r) for r in routines]


@router.post("/routines")
def create_routine(payload: RoutineIn):
    with Session(engine) as session:
        routine = Routine(name=payload.name)
        session.add(routine)
        session.commit()
        session.refresh(routine)
        for i, item in enumerate(payload.exercises):
            session.add(RoutineExercise(routine_id=routine.id, position=i, **item.model_dump()))
        session.commit()
        return _routine_out(session, routine)


@router.patch("/routines/{routine_id}")
def update_routine(routine_id: int, payload: RoutineIn):
    with Session(engine) as session:
        routine = session.get(Routine, routine_id)
        if not routine:
            raise HTTPException(404, "Rutina no encontrada")
        routine.name = payload.name
        for old in session.exec(
            select(RoutineExercise).where(RoutineExercise.routine_id == routine_id)
        ).all():
            session.delete(old)
        for i, item in enumerate(payload.exercises):
            session.add(RoutineExercise(routine_id=routine_id, position=i, **item.model_dump()))
        session.add(routine)
        session.commit()
        return _routine_out(session, routine)


@router.delete("/routines/{routine_id}")
def delete_routine(routine_id: int):
    with Session(engine) as session:
        routine = session.get(Routine, routine_id)
        if not routine:
            raise HTTPException(404, "Rutina no encontrada")
        for old in session.exec(
            select(RoutineExercise).where(RoutineExercise.routine_id == routine_id)
        ).all():
            session.delete(old)
        session.delete(routine)
        session.commit()
        return {"status": "deleted"}


# ── Entrenos ───────────────────────────────────────────────────────────────

@router.get("/workouts/active")
def active_workout():
    with Session(engine) as session:
        workout = session.exec(
            select(Workout).where(Workout.finished_at == None).order_by(Workout.started_at.desc())  # noqa: E711
        ).first()
        return _workout_detail(session, workout) if workout else None


@router.get("/workouts")
def list_workouts(limit: int = 20):
    with Session(engine) as session:
        workouts = session.exec(
            select(Workout).where(Workout.finished_at != None)  # noqa: E711
            .order_by(Workout.started_at.desc()).limit(limit)
        ).all()
        out = []
        for w in workouts:
            sets = session.exec(select(WorkoutSet).where(WorkoutSet.workout_id == w.id)).all()
            routine = session.get(Routine, w.routine_id) if w.routine_id else None
            duration = (w.finished_at - w.started_at).total_seconds() / 60 if w.finished_at else 0
            out.append({
                "id": w.id,
                "started_at": w.started_at,
                "finished_at": w.finished_at,
                "routine_name": routine.name if routine else None,
                "exercises": len({s.exercise_id for s in sets}),
                "sets": len(sets),
                "volume": round(sum(s.weight * s.reps for s in sets), 1),
                "duration_min": round(duration),
            })
        return out


# ── Endpoints para el dispositivo de muñeca (Apple Watch / sensor) ──────────
# Autenticados con X-Device-Token (ver middleware). Pensados para ser MUY
# simples: el reloj pregunta los ejercicios de hoy y manda una serie por rep.

class DeviceSetIn(BaseModel):
    exercise_id: int
    weight: float = Field(ge=0, le=1000)
    reps: int = Field(ge=1, le=100)


@router.get("/device/today")
def device_today():
    """Rutina de hoy + ejercicios con peso recomendado, para el reloj."""
    with Session(engine) as session:
        today_name = seed.routine_by_weekday().get(config.now_local().weekday())
        routine = (
            session.exec(select(Routine).where(Routine.name == today_name)).first()
            if today_name else None
        )
        if not routine:
            return {"routine": None, "exercises": []}
        items = session.exec(
            select(RoutineExercise).where(RoutineExercise.routine_id == routine.id)
            .order_by(RoutineExercise.position)
        ).all()
        exercises = []
        for it in items:
            ex = session.get(Exercise, it.exercise_id)
            if not ex:
                continue
            rec = _recommend(session, ex, it.reps_min, it.reps_max)
            exercises.append({
                "exercise_id": ex.id,
                "name": ex.name,
                "muscle": ex.muscle,
                "target_sets": it.sets,
                "reps_min": it.reps_min,
                "reps_max": it.reps_max,
                "weight": rec.get("weight"),
            })
        return {"routine": routine.name, "exercises": exercises}


@router.get("/device/routines")
def device_routines():
    """Lista todas las rutinas disponibles, para el reloj."""
    with Session(engine) as session:
        routines = session.exec(select(Routine).order_by(Routine.position, Routine.id)).all()
        today_name = seed.routine_by_weekday().get(config.now_local().weekday())
        return [
            {
                "id": r.id,
                "name": r.name,
                "today": r.name == today_name,
                "group": "verano" if r.name in seed.SUMMER_NAMES else "normal",
            }
            for r in routines
        ]


@router.get("/device/routine/{routine_id}")
def device_routine(routine_id: int):
    """Ejercicios de una rutina concreta con peso recomendado, para el reloj."""
    with Session(engine) as session:
        routine = session.get(Routine, routine_id)
        if not routine:
            raise HTTPException(404, "Rutina no encontrada")
        items = session.exec(
            select(RoutineExercise).where(RoutineExercise.routine_id == routine_id)
            .order_by(RoutineExercise.position)
        ).all()
        exercises = []
        for it in items:
            ex = session.get(Exercise, it.exercise_id)
            if not ex:
                continue
            rec = _recommend(session, ex, it.reps_min, it.reps_max)
            exercises.append({
                "exercise_id": ex.id,
                "name": ex.name,
                "muscle": ex.muscle,
                "target_sets": it.sets,
                "reps_min": it.reps_min,
                "reps_max": it.reps_max,
                "weight": rec.get("weight"),
            })
        return {"routine": routine.name, "exercises": exercises}


@router.post("/device/set")
def device_set(payload: DeviceSetIn):
    """Registra una serie desde el reloj. Crea/usa el entreno activo solo."""
    with Session(engine) as session:
        workout = session.exec(
            select(Workout).where(Workout.finished_at == None)  # noqa: E711
            .order_by(Workout.started_at.desc())
        ).first()
        if not workout:
            today_name = seed.routine_by_weekday().get(config.now_local().weekday())
            routine = (
                session.exec(select(Routine).where(Routine.name == today_name)).first()
                if today_name else None
            )
            workout = Workout(routine_id=routine.id if routine else None)
            session.add(workout)
            session.commit()
            session.refresh(workout)

        if not session.get(Exercise, payload.exercise_id):
            raise HTTPException(404, "Ejercicio no encontrado")

        prev = session.exec(
            select(WorkoutSet).where(WorkoutSet.exercise_id == payload.exercise_id)
        ).all()
        pr = None
        if prev:
            prev_weight = max(p.weight for p in prev)
            prev_rm = max(_est_1rm(p.weight, p.reps) for p in prev)
            if payload.weight > prev_weight:
                pr = "peso"
            elif _est_1rm(payload.weight, payload.reps) > prev_rm:
                pr = "1rm"
        count = len([p for p in prev if p.workout_id == workout.id])
        s = WorkoutSet(
            workout_id=workout.id, set_number=count + 1,
            exercise_id=payload.exercise_id, weight=payload.weight, reps=payload.reps,
        )
        session.add(s)
        session.commit()
        session.refresh(s)

        # Feedback para el reloj: mejor peso de entrenos ANTERIORES (para saber
        # si hoy subes) y recomendacion actualizada para la proxima.
        prev_best = max((p.weight for p in prev if p.workout_id != workout.id), default=None)
        reps_min, reps_max = 6, 8
        if workout.routine_id:
            it = session.exec(select(RoutineExercise).where(
                RoutineExercise.routine_id == workout.routine_id,
                RoutineExercise.exercise_id == payload.exercise_id,
            )).first()
            if it:
                reps_min, reps_max = it.reps_min, it.reps_max
        ex = session.get(Exercise, payload.exercise_id)
        rec = _recommend(session, ex, reps_min, reps_max) if ex else {}
        return {
            "workout_id": workout.id, "set_number": s.set_number, "pr": pr,
            "prev_best": prev_best, "next_weight": rec.get("weight"),
        }


@router.post("/workouts")
def start_workout(payload: WorkoutStart):
    with Session(engine) as session:
        existing = session.exec(
            select(Workout).where(Workout.finished_at == None)  # noqa: E711
        ).first()
        if existing:
            return _workout_detail(session, existing)
        if payload.routine_id and not session.get(Routine, payload.routine_id):
            raise HTTPException(404, "Rutina no encontrada")
        workout = Workout(routine_id=payload.routine_id)
        session.add(workout)
        session.commit()
        session.refresh(workout)
        return _workout_detail(session, workout)


@router.get("/workouts/{workout_id}")
def get_workout(workout_id: int):
    with Session(engine) as session:
        workout = session.get(Workout, workout_id)
        if not workout:
            raise HTTPException(404, "Entreno no encontrado")
        return _workout_detail(session, workout)


@router.post("/workouts/{workout_id}/sets")
def add_set(workout_id: int, payload: SetIn):
    with Session(engine) as session:
        workout = session.get(Workout, workout_id)
        if not workout or workout.finished_at:
            raise HTTPException(404, "Entreno no encontrado o ya terminado")
        if not session.get(Exercise, payload.exercise_id):
            raise HTTPException(404, "Ejercicio no encontrado")

        # historico ANTES de insertar, para detectar PR (solo si ya habia datos)
        prev = session.exec(
            select(WorkoutSet).where(WorkoutSet.exercise_id == payload.exercise_id)
        ).all()
        pr = None
        if prev:
            prev_weight = max(p.weight for p in prev)
            prev_rm = max(_est_1rm(p.weight, p.reps) for p in prev)
            if payload.weight > prev_weight:
                pr = "peso"
            elif _est_1rm(payload.weight, payload.reps) > prev_rm:
                pr = "1rm"

        count = len([p for p in prev if p.workout_id == workout_id])
        s = WorkoutSet(workout_id=workout_id, set_number=count + 1, **payload.model_dump())
        session.add(s)
        session.commit()
        session.refresh(s)
        return {**_set_out(s), "pr": pr}


@router.delete("/workouts/{workout_id}/sets/{set_id}")
def delete_set(workout_id: int, set_id: int):
    with Session(engine) as session:
        s = session.get(WorkoutSet, set_id)
        if not s or s.workout_id != workout_id:
            raise HTTPException(404, "Serie no encontrada")
        session.delete(s)
        session.commit()
        return {"status": "deleted"}


@router.post("/workouts/{workout_id}/finish")
def finish_workout(workout_id: int):
    with Session(engine) as session:
        workout = session.get(Workout, workout_id)
        if not workout:
            raise HTTPException(404, "Entreno no encontrado")
        if workout.finished_at:
            return _workout_detail(session, workout)
        sets = session.exec(select(WorkoutSet).where(WorkoutSet.workout_id == workout_id)).all()
        if not sets:
            raise HTTPException(400, "No hay series registradas; descarta el entreno si no vas a entrenar")
        workout.finished_at = datetime.utcnow()
        session.add(workout)

        # El gym cuenta como la rutina "Ejercicio" del modulo Rutinas
        habits = session.exec(
            select(Habit).where(Habit.category == "exercise", Habit.active == True)  # noqa: E712
        ).all()
        for habit in habits:
            if not habit_to_out(session, habit).done_today:
                session.add(HabitLog(habit_id=habit.id, note="gym"))

        session.commit()
        session.refresh(workout)
        detail = _workout_detail(session, workout)
        detail["summary"] = _workout_summary(session, workout)
        return detail


def _workout_summary(session: Session, workout: Workout) -> dict | None:
    """Resumen post-entreno: volumen, PRs y comparacion con la ultima vez que
    se hizo la misma rutina."""
    sets = session.exec(select(WorkoutSet).where(WorkoutSet.workout_id == workout.id)).all()
    if not sets:
        return None
    duration = (workout.finished_at - workout.started_at).total_seconds() / 60 if workout.finished_at else 0
    volume = sum(s.weight * s.reps for s in sets)

    by_ex: dict[int, list[WorkoutSet]] = {}
    for s in sets:
        by_ex.setdefault(s.exercise_id, []).append(s)

    prs = []
    for ex_id, ex_sets in by_ex.items():
        prev = session.exec(
            select(WorkoutSet)
            .join(Workout, Workout.id == WorkoutSet.workout_id)
            .where(
                WorkoutSet.exercise_id == ex_id,
                Workout.finished_at != None,  # noqa: E711
                Workout.id != workout.id,
                Workout.started_at < workout.started_at,
            )
        ).all()
        if not prev:
            continue  # primera vez no cuenta como PR
        ex = session.get(Exercise, ex_id)
        if not ex:
            continue
        cur_w = max(s.weight for s in ex_sets)
        cur_rm = max(_est_1rm(s.weight, s.reps) for s in ex_sets)
        if cur_w > max(s.weight for s in prev):
            prs.append({"exercise": ex.name, "kind": "peso", "value": cur_w})
        elif cur_rm > max(_est_1rm(s.weight, s.reps) for s in prev):
            prs.append({"exercise": ex.name, "kind": "1rm", "value": round(cur_rm, 1)})

    vs_last = None
    if workout.routine_id:
        last = session.exec(
            select(Workout)
            .where(
                Workout.routine_id == workout.routine_id,
                Workout.finished_at != None,  # noqa: E711
                Workout.id != workout.id,
                Workout.started_at < workout.started_at,
            )
            .order_by(Workout.started_at.desc())
        ).first()
        if last:
            last_sets = session.exec(
                select(WorkoutSet).where(WorkoutSet.workout_id == last.id)
            ).all()
            last_vol = sum(s.weight * s.reps for s in last_sets)
            vs_last = {
                "date": last.started_at,
                "last_volume": round(last_vol, 1),
                "volume_delta": round(volume - last_vol, 1),
            }

    return {
        "duration_min": round(duration),
        "volume": round(volume, 1),
        "sets": len(sets),
        "exercises": len(by_ex),
        "prs": prs,
        "vs_last": vs_last,
    }


@router.delete("/workouts/{workout_id}")
def discard_workout(workout_id: int):
    with Session(engine) as session:
        workout = session.get(Workout, workout_id)
        if not workout:
            raise HTTPException(404, "Entreno no encontrado")
        for s in session.exec(select(WorkoutSet).where(WorkoutSet.workout_id == workout_id)).all():
            session.delete(s)
        session.delete(workout)
        session.commit()
        return {"status": "deleted"}


# ── Peso corporal ──────────────────────────────────────────────────────────

@router.get("/bodyweight")
def list_bodyweight(limit: int = 60):
    with Session(engine) as session:
        rows = session.exec(
            select(BodyWeight).order_by(BodyWeight.at.desc()).limit(limit)
        ).all()
        return [{"id": r.id, "at": r.at, "weight": r.weight} for r in rows]


@router.post("/bodyweight")
def add_bodyweight(payload: BodyWeightIn):
    """Tambien pensado para un Atajo de iOS que mande el peso de Apple Health."""
    with Session(engine) as session:
        row = BodyWeight(weight=payload.weight)
        session.add(row)
        session.commit()
        session.refresh(row)
        return {"id": row.id, "at": row.at, "weight": row.weight}


@router.delete("/bodyweight/{entry_id}")
def delete_bodyweight(entry_id: int):
    with Session(engine) as session:
        row = session.get(BodyWeight, entry_id)
        if not row:
            raise HTTPException(404, "No encontrado")
        session.delete(row)
        session.commit()
        return {"status": "deleted"}


# ── Medidas corporales ─────────────────────────────────────────────────────

class MeasureIn(BaseModel):
    site: str
    value: float = Field(gt=5, lt=300)  # cm


@router.get("/measures")
def list_measures():
    """Todas las medidas agrupadas por sitio, mas recientes primero."""
    with Session(engine) as session:
        rows = session.exec(select(BodyMeasure).order_by(BodyMeasure.at.desc())).all()
        out: dict[str, list] = {}
        for r in rows:
            out.setdefault(r.site, []).append({"id": r.id, "at": r.at, "value": r.value})
        return out


@router.post("/measures")
def add_measure(payload: MeasureIn):
    if payload.site not in MEASURE_SITES:
        raise HTTPException(400, "Sitio no valido")
    with Session(engine) as session:
        row = BodyMeasure(site=payload.site, value=payload.value)
        session.add(row)
        session.commit()
        session.refresh(row)
        return {"id": row.id, "site": row.site, "at": row.at, "value": row.value}


@router.delete("/measures/{measure_id}")
def delete_measure(measure_id: int):
    with Session(engine) as session:
        row = session.get(BodyMeasure, measure_id)
        if not row:
            raise HTTPException(404, "No encontrada")
        session.delete(row)
        session.commit()
        return {"status": "deleted"}


# ── Fotos de progreso ──────────────────────────────────────────────────────

@router.get("/photos")
def list_photos():
    with Session(engine) as session:
        rows = session.exec(select(ProgressPhoto).order_by(ProgressPhoto.at.desc())).all()
        return [
            {"id": p.id, "at": p.at, "url": f"/api/gym/photos/file/{p.filename}", "note": p.note}
            for p in rows
        ]


@router.post("/photos")
async def upload_photo(file: UploadFile = File(...)):
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in {".jpg", ".jpeg", ".png", ".webp", ".heic"}:
        raise HTTPException(400, "Formato no soportado")
    data = await file.read()
    if len(data) > 15 * 1024 * 1024:
        raise HTTPException(400, "Foto demasiado grande (max 15 MB)")
    os.makedirs(PHOTOS_DIR, exist_ok=True)
    name = f"{uuid.uuid4().hex}{ext}"
    with open(os.path.join(PHOTOS_DIR, name), "wb") as f:
        f.write(data)
    with Session(engine) as session:
        photo = ProgressPhoto(filename=name)
        session.add(photo)
        session.commit()
        session.refresh(photo)
        return {"id": photo.id, "at": photo.at, "url": f"/api/gym/photos/file/{name}"}


@router.get("/photos/file/{filename}")
def get_photo(filename: str):
    # nombre seguro: solo el basename (sin ../)
    safe = os.path.basename(filename)
    path = os.path.join(PHOTOS_DIR, safe)
    if not os.path.isfile(path):
        raise HTTPException(404, "Foto no encontrada")
    return FileResponse(path)


@router.delete("/photos/{photo_id}")
def delete_photo(photo_id: int):
    with Session(engine) as session:
        photo = session.get(ProgressPhoto, photo_id)
        if not photo:
            raise HTTPException(404, "No encontrada")
        path = os.path.join(PHOTOS_DIR, os.path.basename(photo.filename))
        if os.path.isfile(path):
            os.remove(path)
        session.delete(photo)
        session.commit()
        return {"status": "deleted"}


# ── Stats semanales ────────────────────────────────────────────────────────

@router.get("/stats/weekly")
def weekly_stats():
    """Series y volumen por grupo muscular en los ultimos 7 dias."""
    since = datetime.utcnow() - timedelta(days=7)
    with Session(engine) as session:
        rows = session.exec(
            select(WorkoutSet, Exercise)
            .join(Exercise, Exercise.id == WorkoutSet.exercise_id)
            .where(WorkoutSet.created_at >= since)
        ).all()
        by_muscle: dict[str, dict] = {}
        for s, ex in rows:
            entry = by_muscle.setdefault(ex.muscle, {"muscle": ex.muscle, "sets": 0, "volume": 0.0})
            entry["sets"] += 1
            entry["volume"] += s.weight * s.reps
        muscles = sorted(by_muscle.values(), key=lambda m: -m["sets"])
        for m in muscles:
            m["volume"] = round(m["volume"], 1)
        return {"muscles": muscles, "total_sets": sum(m["sets"] for m in muscles)}


# ── Progreso ───────────────────────────────────────────────────────────────

@router.get("/progress/{exercise_id}")
def exercise_progress(exercise_id: int):
    with Session(engine) as session:
        ex = session.get(Exercise, exercise_id)
        if not ex:
            raise HTTPException(404, "Ejercicio no encontrado")
        rows = session.exec(
            select(WorkoutSet, Workout)
            .join(Workout, Workout.id == WorkoutSet.workout_id)
            .where(WorkoutSet.exercise_id == exercise_id, Workout.finished_at != None)  # noqa: E711
            .order_by(Workout.started_at)
        ).all()
        by_workout: dict[int, dict] = {}
        for s, w in rows:
            entry = by_workout.setdefault(w.id, {"date": w.started_at, "sets": []})
            entry["sets"].append(s)

        sessions_out = []
        for entry in by_workout.values():
            sets = entry["sets"]
            top = max(sets, key=lambda s: (s.weight, s.reps))
            sessions_out.append({
                "date": entry["date"],
                "top_weight": top.weight,
                "top_reps": top.reps,
                "est_1rm": max(_est_1rm(s.weight, s.reps) for s in sets),
                "volume": round(sum(s.weight * s.reps for s in sets), 1),
                "sets": len(sets),
            })

        all_sets = [s for s, _ in rows]
        return {
            "exercise": _exercise_out(ex),
            "sessions": sessions_out[-20:],
            "pr_weight": max((s.weight for s in all_sets), default=0),
            "pr_1rm": max((_est_1rm(s.weight, s.reps) for s in all_sets), default=0),
            "recommendation": _recommend(session, ex, DEFAULT_REPS_MIN, DEFAULT_REPS_MAX),
        }
