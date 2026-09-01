from datetime import datetime
from typing import Any, Optional

from sqlalchemy import JSON, Column
from sqlmodel import Field, SQLModel


class Habit(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str
    category: str
    schedule_type: str
    schedule: Any = Field(sa_column=Column(JSON))
    active: bool = Field(default=True)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class HabitLog(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    habit_id: int = Field(foreign_key="habit.id", index=True)
    done_at: datetime = Field(default_factory=datetime.utcnow, index=True)
    note: Optional[str] = None


# ── Modulo Gym (tipo Hevy) ─────────────────────────────────────────────────

class Exercise(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str
    muscle: str  # Pecho / Espalda / Hombros / Biceps / Triceps / Pierna / Core
    equipment: str = "barra"  # barra / mancuernas / maquina / polea / peso corporal
    custom: bool = Field(default=False)


class Routine(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str
    position: int = Field(default=0)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class RoutineExercise(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    routine_id: int = Field(foreign_key="routine.id", index=True)
    exercise_id: int = Field(foreign_key="exercise.id")
    position: int = Field(default=0)
    sets: int = Field(default=3)
    reps_min: int = Field(default=8)
    reps_max: int = Field(default=12)


class Workout(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    routine_id: Optional[int] = Field(default=None, foreign_key="routine.id")
    started_at: datetime = Field(default_factory=datetime.utcnow, index=True)
    finished_at: Optional[datetime] = None
    note: Optional[str] = None


class WorkoutSet(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    workout_id: int = Field(foreign_key="workout.id", index=True)
    exercise_id: int = Field(foreign_key="exercise.id", index=True)
    set_number: int = Field(default=1)
    weight: float = Field(default=0)  # kg
    reps: int = Field(default=0)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class BodyWeight(SQLModel, table=True):
    """Peso corporal (se puede subir tambien desde Atajos de iOS)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    at: datetime = Field(default_factory=datetime.utcnow, index=True)
    weight: float  # kg


class Profile(SQLModel, table=True):
    """Perfil del usuario de esta instancia (fila unica, id=1).

    Sustituye a los datos corporales que antes estaban hardcodeados: se
    rellena en el onboarding y se edita desde Ajustes.
    """
    id: Optional[int] = Field(default=1, primary_key=True)
    name: Optional[str] = None
    height_cm: float = Field(default=175)
    birth_date: Optional[datetime] = None
    sex: str = Field(default="m")  # m / f
    # Multiplicador sobre el BMR (1.2 sedentario ... 1.9 muy activo)
    activity_factor: float = Field(default=1.5)
    goal: str = Field(default="Mantener")  # Volumen / Definicion / Mantener
    goal_kcal_delta: float = Field(default=0)
    protein_per_kg: float = Field(default=2.0)
    body_fat_pct: Optional[float] = None
    fallback_weight: float = Field(default=70)
    # Material del gimnasio
    bar_weight: float = Field(default=20)
    plates: Any = Field(default=[20, 10, 5, 2.5, 1.25], sa_column=Column(JSON))
    # Ubicacion para el clima del briefing
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    city: Optional[str] = None
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class FoodLog(SQLModel, table=True):
    """Modulo Nutricion > Macros: una entrada por comida apuntada."""
    id: Optional[int] = Field(default=None, primary_key=True)
    at: datetime = Field(default_factory=datetime.utcnow, index=True)
    name: str
    kcal: int = Field(default=0)
    protein: float = Field(default=0)  # gramos


class BodyMeasure(SQLModel, table=True):
    """Medida corporal (perimetro en cm). site: brazo/pecho/cintura/pierna."""
    id: Optional[int] = Field(default=None, primary_key=True)
    at: datetime = Field(default_factory=datetime.utcnow, index=True)
    site: str = Field(index=True)
    value: float  # cm


class ProgressPhoto(SQLModel, table=True):
    """Foto de progreso (el archivo vive en backend/photos/)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    at: datetime = Field(default_factory=datetime.utcnow, index=True)
    filename: str
    note: Optional[str] = None


class Task(SQLModel, table=True):
    """Pendiente suelto (no recurrente) del modulo Tareas."""
    id: Optional[int] = Field(default=None, primary_key=True)
    text: str
    done: bool = Field(default=False)
    due: Optional[datetime] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    done_at: Optional[datetime] = None


class Note(SQLModel, table=True):
    """Nota rapida / diario."""
    id: Optional[int] = Field(default=None, primary_key=True)
    text: str
    created_at: datetime = Field(default_factory=datetime.utcnow, index=True)


class PushSubscription(SQLModel, table=True):
    """Suscripcion Web Push de un dispositivo (la PWA instalada en el iPhone)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    endpoint: str = Field(unique=True)
    p256dh: str
    auth: str
    created_at: datetime = Field(default_factory=datetime.utcnow)


class ShoppingItem(SQLModel, table=True):
    """Lista de la compra."""
    id: Optional[int] = Field(default=None, primary_key=True)
    text: str
    done: bool = Field(default=False)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class HealthDay(SQLModel, table=True):
    """Datos diarios de Apple Health (enviados por un Atajo de iOS). Una fila
    por dia (clave: day)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    day: str = Field(unique=True, index=True)  # YYYY-MM-DD
    steps: Optional[int] = None
    sleep_hours: Optional[float] = None
    resting_hr: Optional[int] = None
    active_kcal: Optional[int] = None
    updated_at: datetime = Field(default_factory=datetime.utcnow)
