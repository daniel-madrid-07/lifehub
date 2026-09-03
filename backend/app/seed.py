import os
import re

from sqlmodel import Session, select

from .db import engine
from .models import Exercise, Habit, Routine, RoutineDay, RoutineExercise

# Marcador: una vez sembrados los ejemplos personales (habitos/comidas), no se
# vuelven a crear aunque el usuario los borre. Asi sus cambios persisten.
SEED_MARKER = os.path.join(os.path.dirname(__file__), "..", ".seeded")


def mark_seeded():
    try:
        open(SEED_MARKER, "a").close()
    except OSError:
        pass

# Detecta el material por el NOMBRE del ejercicio (mas fiable que el campo
# de wger, que mete muchos press de mancuerna bajo "barra"). Orden = prioridad.
EQUIPMENT_KEYWORDS = [
    ("mancuernas", r"mancuerna|dumbbell|\bdb\b|kettlebell|pesa rusa|goblet"),
    ("polea", r"polea|cable|cruce|cross-?over|jal[oó]n|pull-?down|pulldown|face pull|trx"),
    ("maquina", r"m[aá]quina|machine|smith|prensa|leg press|hack|pec\s?deck|peck deck|pec-deck"),
    ("barra", r"\bbarra\b|barbell|\bez\b|\bsz\b|landmine"),
    ("peso corporal", r"peso corporal|bodyweight|flexion|flexión|dominada|fondo|plancha|"
                      r"pull-?up|push-?up|chin-?up|\bdip\b|calistenia|muscle-?up|"
                      r"l-sit|sit-?up|crunch|burpee"),
]


def infer_equipment(name: str, fallback: str) -> str:
    low = name.lower()
    for equip, pattern in EQUIPMENT_KEYWORDS:
        if re.search(pattern, low):
            return equip
    return fallback

EXAMPLES = [
    dict(name="Agua", category="water", schedule_type="daily_times",
         schedule=["09:00", "11:00", "13:00", "15:00", "17:00", "19:00", "21:00"]),
    dict(name="Medicina", category="medicine", schedule_type="daily_times",
         schedule=["09:00"]),
    dict(name="Ejercicio", category="exercise", schedule_type="daily_times",
         schedule=["18:00"]),
    dict(name="Rutina de dormir", category="sleep", schedule_type="daily_times",
         schedule=["22:30"]),
    dict(name="Rutina de despertar", category="sleep", schedule_type="daily_times",
         schedule=["07:30"]),
    dict(name="Sacar la basura", category="chore", schedule_type="interval_days",
         schedule=3),
    dict(name="Limpiar el baño", category="chore", schedule_type="interval_days",
         schedule=7),
]


DIET_EXAMPLES = [
    dict(name="Desayuno", category="diet", schedule_type="daily_times",
         schedule=["08:00"]),
    dict(name="Comida", category="diet", schedule_type="daily_times",
         schedule=["13:30"]),
    dict(name="Cena", category="diet", schedule_type="daily_times",
         schedule=["21:00"]),
]


def run():
    # si ya se sembro una vez, respetar lo que tenga el usuario (aunque borre todo)
    if os.path.exists(SEED_MARKER):
        return
    with Session(engine) as session:
        if session.exec(select(Habit)).first():
            return
        for data in EXAMPLES:
            session.add(Habit(**data))
        session.commit()


def add_diet_habits():
    if os.path.exists(SEED_MARKER):
        return
    with Session(engine) as session:
        if session.exec(select(Habit).where(Habit.category == "diet")).first():
            return
        for data in DIET_EXAMPLES:
            session.add(Habit(**data))
        session.commit()


# Catalogo base de ejercicios del modulo Gym (name, muscle, equipment)
EXERCISES = [
    # Pecho
    ("Press banca", "Pecho", "barra"),
    ("Press banca inclinado", "Pecho", "barra"),
    ("Press con mancuernas", "Pecho", "mancuernas"),
    ("Press inclinado con mancuernas", "Pecho", "mancuernas"),
    ("Aperturas con mancuernas", "Pecho", "mancuernas"),
    ("Cruces en polea", "Pecho", "polea"),
    ("Press en maquina", "Pecho", "maquina"),
    ("Fondos en paralelas", "Pecho", "peso corporal"),
    ("Flexiones", "Pecho", "peso corporal"),
    # Espalda
    ("Dominadas", "Espalda", "peso corporal"),
    ("Jalon al pecho", "Espalda", "polea"),
    ("Remo con barra", "Espalda", "barra"),
    ("Remo con mancuerna", "Espalda", "mancuernas"),
    ("Remo en polea baja", "Espalda", "polea"),
    ("Remo en maquina", "Espalda", "maquina"),
    ("Peso muerto", "Espalda", "barra"),
    ("Pullover en polea", "Espalda", "polea"),
    ("Encogimientos (trapecio)", "Espalda", "mancuernas"),
    # Hombros
    ("Press militar", "Hombros", "barra"),
    ("Press de hombro con mancuernas", "Hombros", "mancuernas"),
    ("Elevaciones laterales", "Hombros", "mancuernas"),
    ("Elevaciones frontales", "Hombros", "mancuernas"),
    ("Pajaros (deltoide posterior)", "Hombros", "mancuernas"),
    ("Face pull", "Hombros", "polea"),
    # Biceps
    ("Curl con barra", "Biceps", "barra"),
    ("Curl con mancuernas", "Biceps", "mancuernas"),
    ("Curl martillo", "Biceps", "mancuernas"),
    ("Curl en polea", "Biceps", "polea"),
    ("Curl predicador", "Biceps", "maquina"),
    # Triceps
    ("Press frances", "Triceps", "barra"),
    ("Extension de triceps en polea", "Triceps", "polea"),
    ("Extension sobre la cabeza", "Triceps", "mancuernas"),
    ("Fondos entre bancos", "Triceps", "peso corporal"),
    # Pierna
    ("Sentadilla", "Pierna", "barra"),
    ("Prensa de pierna", "Pierna", "maquina"),
    ("Zancadas", "Pierna", "mancuernas"),
    ("Peso muerto rumano", "Pierna", "barra"),
    ("Extension de cuadriceps", "Pierna", "maquina"),
    ("Curl femoral", "Pierna", "maquina"),
    ("Hip thrust", "Pierna", "barra"),
    ("Elevacion de gemelos", "Pierna", "maquina"),
    ("Sentadilla bulgara", "Pierna", "mancuernas"),
    # Core
    ("Plancha", "Core", "peso corporal"),
    ("Crunch abdominal", "Core", "peso corporal"),
    ("Elevaciones de piernas", "Core", "peso corporal"),
    ("Rueda abdominal", "Core", "peso corporal"),
    ("Russian twist", "Core", "peso corporal"),
    # Rutina de verano (nombres en ingles)
    ("Cable Lateral Raise", "Hombros", "polea"),
    ("Smith Machine Shoulder Press", "Hombros", "maquina"),
    ("Smith Machine Incline Press", "Pecho", "maquina"),
    ("Machine Chest Press", "Pecho", "maquina"),
    ("Machine Pec Fly", "Pecho", "maquina"),
    ("Cable Hammer Curl", "Biceps", "polea"),
    ("Machine Biceps Curl", "Biceps", "maquina"),
    ("Leg Extension", "Pierna", "maquina"),
    ("Seated Cable Row", "Espalda", "polea"),
    ("Machine Lat Pulldown", "Espalda", "maquina"),
    ("Machine Front Delt Raise", "Hombros", "maquina"),
    ("Machine Leg Curl", "Pierna", "maquina"),
    ("Calf Raise on Leg Press", "Pierna", "maquina"),
]


def add_gym_exercises():
    """Siembra el catalogo base + el de wger (~900) y reconcilia el material
    de los ejercicios no-custom (la clasificacion de wger es imprecisa, asi
    que se infiere del nombre). Idempotente."""
    from .exercises_catalog import WGER_EXERCISES

    catalog = EXERCISES + WGER_EXERCISES
    with Session(engine) as session:
        by_name = {e.name.strip().lower(): e for e in session.exec(select(Exercise)).all()}
        changed = False

        for name, muscle, equipment in catalog:
            key = name.strip().lower()
            equip = infer_equipment(name, equipment)
            existing = by_name.get(key)
            if existing is None:
                session.add(Exercise(name=name, muscle=muscle, equipment=equip))
                by_name[key] = True  # marca dentro del lote para no duplicar
                changed = True
            elif existing is not True and not existing.custom and existing.equipment != equip:
                existing.equipment = equip  # corrige el material (no toca los custom)
                session.add(existing)
                changed = True

        if changed:
            session.commit()


# El calendario semanal (que rutina toca cada dia) vive en la tabla RoutineDay:
# lo elige el usuario, o lo rellena una plantilla de routine_templates.py.


def routine_by_weekday() -> dict:
    """Mapeo weekday -> nombre de rutina, segun lo que tenga configurado el
    usuario. Vacio si aun no ha asignado dias."""
    with Session(engine) as session:
        rows = session.exec(select(RoutineDay)).all()
        if not rows:
            return {}
        names = {r.id: r.name for r in session.exec(select(Routine)).all()}
        return {row.weekday: names[row.routine_id] for row in rows if row.routine_id in names}


def set_routine_day(weekday: int, routine_id: int | None) -> dict:
    """Asigna (o quita, con routine_id=None) la rutina de un dia."""
    weekday = max(0, min(6, weekday))
    with Session(engine) as session:
        row = session.exec(select(RoutineDay).where(RoutineDay.weekday == weekday)).first()
        if routine_id is None:
            if row:
                session.delete(row)
                session.commit()
            return routine_by_weekday()
        if row:
            row.routine_id = routine_id
        else:
            row = RoutineDay(weekday=weekday, routine_id=routine_id)
        session.add(row)
        session.commit()
    return routine_by_weekday()


