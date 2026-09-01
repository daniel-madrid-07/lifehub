"""Perfil del usuario: datos corporales, objetivo y material del gimnasio.

Antes esto estaba hardcodeado por duplicado en el frontend (me.ts) y en la app
iOS (Me.swift). Ahora vive en la base de datos y las fórmulas se calculan aquí,
en un solo sitio, para que los tres clientes coincidan siempre.
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from .db import engine
from .models import BodyWeight, Profile

router = APIRouter(prefix="/api/profile")


# ── Schemas ────────────────────────────────────────────────────────────────

class ProfileIn(BaseModel):
    name: Optional[str] = None
    height_cm: Optional[float] = Field(default=None, gt=50, lt=260)
    birth_date: Optional[datetime] = None
    sex: Optional[str] = Field(default=None, pattern="^[mf]$")
    activity_factor: Optional[float] = Field(default=None, ge=1.0, le=2.5)
    goal: Optional[str] = None
    goal_kcal_delta: Optional[float] = Field(default=None, ge=-1500, le=1500)
    protein_per_kg: Optional[float] = Field(default=None, ge=0.5, le=4)
    body_fat_pct: Optional[float] = Field(default=None, ge=1, le=70)
    fallback_weight: Optional[float] = Field(default=None, gt=20, lt=400)
    bar_weight: Optional[float] = Field(default=None, ge=0, le=50)
    plates: Optional[list[float]] = None
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    city: Optional[str] = None


# Presets de objetivo: delta de kcal sobre el TDEE y proteína por kg.
GOAL_PRESETS = {
    "Volumen": (300, 2.0),
    "Definicion": (-400, 2.2),
    "Mantener": (0, 1.8),
}


# ── Acceso ─────────────────────────────────────────────────────────────────

def get_profile(session: Session) -> Profile:
    """Perfil de la instancia; lo crea con valores por defecto si no existe."""
    profile = session.get(Profile, 1)
    if profile is None:
        profile = Profile(id=1)
        session.add(profile)
        session.commit()
        session.refresh(profile)
    return profile


def _latest_weight(session: Session, profile: Profile) -> float:
    """Último peso de la báscula, o el de respaldo del perfil."""
    row = session.exec(select(BodyWeight).order_by(BodyWeight.at.desc())).first()
    return row.weight if row else profile.fallback_weight


# ── Fórmulas ───────────────────────────────────────────────────────────────

def age_of(profile: Profile) -> Optional[int]:
    if not profile.birth_date:
        return None
    today = datetime.utcnow()
    years = today.year - profile.birth_date.year
    before = (today.month, today.day) < (profile.birth_date.month, profile.birth_date.day)
    return years - 1 if before else years


def bmr(profile: Profile, weight: float) -> float:
    """Mifflin-St Jeor. El término final depende del sexo: +5 hombre, -161 mujer."""
    years = age_of(profile) or 25
    base = 10 * weight + 6.25 * profile.height_cm - 5 * years
    return base + (5 if profile.sex == "m" else -161)


def tdee(profile: Profile, weight: float) -> float:
    return bmr(profile, weight) * profile.activity_factor


def kcal_target(profile: Profile, weight: float) -> int:
    return round(tdee(profile, weight) + profile.goal_kcal_delta)


def protein_target(profile: Profile, weight: float) -> float:
    return round(weight * profile.protein_per_kg)


def plates_per_side(profile: Profile, total: float) -> dict:
    """Qué discos poner por lado para un peso total, con la barra del usuario."""
    per_side = (total - profile.bar_weight) / 2
    if per_side <= 0:
        return {"plates": [], "leftover": 0}
    out: list[float] = []
    for plate in sorted(profile.plates or [], reverse=True):
        while per_side >= plate - 1e-9:
            out.append(plate)
            per_side -= plate
    return {"plates": out, "leftover": round(per_side, 2)}


# ── Endpoints ──────────────────────────────────────────────────────────────

def _serialize(profile: Profile, session: Session) -> dict:
    weight = _latest_weight(session, profile)
    return {
        "name": profile.name,
        "height_cm": profile.height_cm,
        "birth_date": profile.birth_date.isoformat() if profile.birth_date else None,
        "age": age_of(profile),
        "sex": profile.sex,
        "activity_factor": profile.activity_factor,
        "goal": profile.goal,
        "goal_kcal_delta": profile.goal_kcal_delta,
        "protein_per_kg": profile.protein_per_kg,
        "body_fat_pct": profile.body_fat_pct,
        "fallback_weight": profile.fallback_weight,
        "bar_weight": profile.bar_weight,
        "plates": profile.plates,
        "latitude": profile.latitude,
        "longitude": profile.longitude,
        "city": profile.city,
        # Derivados, para que los clientes no repitan las fórmulas
        "weight": weight,
        "bmr": round(bmr(profile, weight)),
        "tdee": round(tdee(profile, weight)),
        "kcal_target": kcal_target(profile, weight),
        "protein_target": protein_target(profile, weight),
        "configured": profile.birth_date is not None,
    }


@router.get("")
def read_profile() -> dict:
    with Session(engine) as session:
        return _serialize(get_profile(session), session)


@router.patch("")
def update_profile(data: ProfileIn) -> dict:
    with Session(engine) as session:
        profile = get_profile(session)
        fields = data.model_dump(exclude_unset=True)

        # Elegir un objetivo aplica su preset salvo que se pasen valores propios.
        goal = fields.get("goal")
        if goal in GOAL_PRESETS:
            delta, protein = GOAL_PRESETS[goal]
            fields.setdefault("goal_kcal_delta", delta)
            fields.setdefault("protein_per_kg", protein)

        for key, value in fields.items():
            if value is not None:
                setattr(profile, key, value)
        profile.updated_at = datetime.utcnow()
        session.add(profile)
        session.commit()
        session.refresh(profile)
        return _serialize(profile, session)


@router.get("/plates")
def compute_plates(total: float) -> dict:
    with Session(engine) as session:
        return plates_per_side(get_profile(session), total)
