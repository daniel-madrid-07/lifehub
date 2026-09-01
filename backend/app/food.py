"""Modulo Nutricion > Macros: registro rapido de comidas (kcal + proteina).

Los objetivos diarios viven en el frontend (localStorage): aqui solo datos.
"""
from datetime import datetime, time as dtime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from . import config
from .db import engine
from .models import FoodLog, ShoppingItem

router = APIRouter(prefix="/api/food")


class FoodIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    kcal: int = Field(ge=0, le=10000)
    protein: float = Field(default=0, ge=0, le=1000)


def _day_bounds_utc(day: Optional[str]):
    """Limites UTC del dia LOCAL pedido (los logs se guardan en UTC)."""
    local_day = (
        datetime.strptime(day, "%Y-%m-%d").date() if day else config.now_local().date()
    )
    start_local = datetime.combine(local_day, dtime.min, tzinfo=config.TZ)
    end_local = start_local + timedelta(days=1)
    return (
        start_local.astimezone(timezone.utc).replace(tzinfo=None),
        end_local.astimezone(timezone.utc).replace(tzinfo=None),
    )


@router.get("")
def list_food(day: Optional[str] = None):
    start, end = _day_bounds_utc(day)
    with Session(engine) as session:
        rows = session.exec(
            select(FoodLog).where(FoodLog.at >= start, FoodLog.at < end).order_by(FoodLog.at)
        ).all()
        return {
            "items": [
                {"id": r.id, "at": r.at, "name": r.name, "kcal": r.kcal, "protein": r.protein}
                for r in rows
            ],
            "total_kcal": sum(r.kcal for r in rows),
            "total_protein": round(sum(r.protein for r in rows), 1),
        }


@router.post("")
def add_food(payload: FoodIn):
    with Session(engine) as session:
        row = FoodLog(**payload.model_dump())
        session.add(row)
        session.commit()
        session.refresh(row)
        return {"id": row.id, "at": row.at, "name": row.name, "kcal": row.kcal, "protein": row.protein}


@router.delete("/{entry_id}")
def delete_food(entry_id: int):
    with Session(engine) as session:
        row = session.get(FoodLog, entry_id)
        if not row:
            raise HTTPException(404, "No encontrado")
        session.delete(row)
        session.commit()
        return {"status": "deleted"}


# ── Lista de la compra ──────────────────────────────────────────────────────

class ShopIn(BaseModel):
    text: str = Field(min_length=1, max_length=120)


def _shop_out(s: ShoppingItem) -> dict:
    return {"id": s.id, "text": s.text, "done": s.done}


@router.get("/shopping")
def list_shopping():
    with Session(engine) as session:
        rows = session.exec(select(ShoppingItem)).all()
        rows.sort(key=lambda s: (s.done, s.created_at))
        return [_shop_out(s) for s in rows]


@router.post("/shopping")
def add_shopping(payload: ShopIn):
    with Session(engine) as session:
        row = ShoppingItem(text=payload.text.strip())
        session.add(row)
        session.commit()
        session.refresh(row)
        return _shop_out(row)


@router.patch("/shopping/{item_id}")
def toggle_shopping(item_id: int):
    with Session(engine) as session:
        row = session.get(ShoppingItem, item_id)
        if not row:
            raise HTTPException(404, "No encontrado")
        row.done = not row.done
        session.add(row)
        session.commit()
        return _shop_out(row)


@router.delete("/shopping/{item_id}")
def delete_shopping(item_id: int):
    with Session(engine) as session:
        row = session.get(ShoppingItem, item_id)
        if not row:
            raise HTTPException(404, "No encontrado")
        session.delete(row)
        session.commit()
        return {"status": "deleted"}


@router.delete("/shopping")
def clear_done_shopping():
    """Borra todos los items ya comprados (marcados)."""
    with Session(engine) as session:
        for row in session.exec(select(ShoppingItem).where(ShoppingItem.done == True)).all():  # noqa: E712
            session.delete(row)
        session.commit()
        return {"status": "ok"}
