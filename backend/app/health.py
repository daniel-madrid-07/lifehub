"""Datos de Apple Health, enviados por un Atajo de iOS.

El Atajo (automatización diaria) hace POST a /api/health con los datos del
dia desde la app Salud. Se guarda una fila por dia (idempotente por 'day')."""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from . import config
from .db import engine
from .models import HealthDay

router = APIRouter(prefix="/api/health")


class HealthIn(BaseModel):
    day: Optional[str] = None  # YYYY-MM-DD; si falta, hoy
    steps: Optional[int] = Field(default=None, ge=0, le=200000)
    sleep_hours: Optional[float] = Field(default=None, ge=0, le=24)
    resting_hr: Optional[int] = Field(default=None, ge=20, le=220)
    active_kcal: Optional[int] = Field(default=None, ge=0, le=20000)


def _out(h: HealthDay) -> dict:
    return {
        "day": h.day,
        "steps": h.steps,
        "sleep_hours": h.sleep_hours,
        "resting_hr": h.resting_hr,
        "active_kcal": h.active_kcal,
    }


@router.get("")
def list_health(days: int = 30):
    with Session(engine) as session:
        rows = session.exec(
            select(HealthDay).order_by(HealthDay.day.desc()).limit(days)
        ).all()
        return [_out(h) for h in reversed(rows)]


@router.post("")
def upsert_health(payload: HealthIn):
    day = payload.day or config.now_local().date().isoformat()
    with Session(engine) as session:
        row = session.exec(select(HealthDay).where(HealthDay.day == day)).first()
        if not row:
            row = HealthDay(day=day)
        for key, value in payload.model_dump(exclude_unset=True).items():
            if key != "day" and value is not None:
                setattr(row, key, value)
        row.updated_at = datetime.utcnow()
        session.add(row)
        session.commit()
        session.refresh(row)
        return _out(row)
