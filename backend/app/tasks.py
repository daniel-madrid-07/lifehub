"""Modulo Tareas + Notas: pendientes sueltos (no recurrentes, a diferencia
de los habitos) y notas rapidas / diario."""
import re
from datetime import datetime, time, timedelta
from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from . import config
from .db import engine
from .models import Note, Task

router = APIRouter(prefix="/api")


# ── Lenguaje natural: "examen viernes" -> texto "examen" + fecha viernes ──────

_WEEKDAYS = {
    "lunes": 0, "martes": 1, "miercoles": 2, "miércoles": 2, "jueves": 3,
    "viernes": 4, "sabado": 5, "sábado": 5, "domingo": 6,
}
_MONTHS = {
    "enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6,
    "julio": 7, "agosto": 8, "septiembre": 9, "setiembre": 9, "octubre": 10,
    "noviembre": 11, "diciembre": 12,
}


def parse_due(text: str) -> tuple[str, Optional[datetime]]:
    """Detecta una fecha en lenguaje natural (es) y la quita del texto.
    Devuelve (texto_limpio, due o None). Hora por defecto 09:00 local."""
    now = config.now_local()
    today = now.date()
    low = " " + text.lower() + " "
    due_date = None
    span = None  # (substring a quitar)

    def at9(d):
        return datetime.combine(d, time(9, 0))

    # patrones absolutos primero
    m = re.search(r"\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b", low)
    if m:
        d, mo = int(m.group(1)), int(m.group(2))
        y = int(m.group(3)) + (2000 if m.group(3) and len(m.group(3)) == 2 else 0) if m.group(3) else today.year
        try:
            due_date = datetime(y, mo, d).date()
            span = m.group(0)
        except ValueError:
            pass

    if not due_date:
        m = re.search(r"\b(\d{1,2})\s+de\s+(" + "|".join(_MONTHS) + r")\b", low)
        if m:
            d, mo = int(m.group(1)), _MONTHS[m.group(2)]
            y = today.year + (1 if mo < today.month else 0)
            try:
                due_date = datetime(y, mo, d).date()
                span = m.group(0)
            except ValueError:
                pass

    if not due_date:
        m = re.search(r"\ben\s+(\d{1,2})\s+(d[ií]as?|semanas?)\b", low)
        if m:
            n = int(m.group(1)) * (7 if m.group(2).startswith("sem") else 1)
            due_date = today + timedelta(days=n)
            span = m.group(0)

    if not due_date:
        if re.search(r"\bpasado\s+ma[nñ]ana\b", low):
            due_date, span = today + timedelta(days=2), "pasado mañana"
        elif re.search(r"\bma[nñ]ana\b", low):
            due_date, span = today + timedelta(days=1), "mañana"
        elif re.search(r"\bhoy\b", low):
            due_date, span = today, "hoy"

    if not due_date:
        for name, wd in _WEEKDAYS.items():
            if re.search(r"\b" + name + r"\b", low):
                ahead = (wd - today.weekday()) % 7
                ahead = ahead or 7  # "viernes" = el proximo viernes
                due_date, span = today + timedelta(days=ahead), name
                break

    if not due_date:
        return text.strip(), None

    # limpia el texto: quita la expresion de fecha y conectores sueltos
    clean = text
    if span:
        clean = re.sub(re.escape(span), "", clean, flags=re.IGNORECASE)
    clean = re.sub(r"\b(el|para|este|esta|próximo|proximo|próxima|proxima)\b", " ", clean, flags=re.IGNORECASE)
    clean = re.sub(r"\s+", " ", clean).strip(" ,.-")
    return (clean or text.strip()), at9(due_date)


# ── Tareas ─────────────────────────────────────────────────────────────────

class TaskIn(BaseModel):
    text: str = Field(min_length=1, max_length=300)
    due: Optional[datetime] = None


class TaskUpdate(BaseModel):
    text: Optional[str] = Field(default=None, min_length=1, max_length=300)
    done: Optional[bool] = None
    due: Optional[datetime] = None


def _task_out(t: Task) -> dict:
    return {
        "id": t.id,
        "text": t.text,
        "done": t.done,
        "due": t.due,
        "created_at": t.created_at,
        "done_at": t.done_at,
    }


@router.get("/tasks")
def list_tasks():
    with Session(engine) as session:
        rows = session.exec(select(Task)).all()
        # pendientes primero (por fecha limite, luego creacion); hechas al final
        rows.sort(key=lambda t: (t.done, t.due or datetime.max, t.created_at))
        return [_task_out(t) for t in rows]


@router.post("/tasks")
def create_task(payload: TaskIn):
    text = payload.text.strip()
    due = payload.due
    if due is None:  # sin fecha explicita: intenta deducirla del texto
        text, due = parse_due(text)
    with Session(engine) as session:
        task = Task(text=text, due=due)
        session.add(task)
        session.commit()
        session.refresh(task)
        return _task_out(task)


@router.patch("/tasks/{task_id}")
def update_task(task_id: int, payload: TaskUpdate):
    with Session(engine) as session:
        task = session.get(Task, task_id)
        if not task:
            raise HTTPException(404, "Tarea no encontrada")
        data = payload.model_dump(exclude_unset=True)
        if "done" in data:
            task.done = data["done"]
            task.done_at = datetime.utcnow() if data["done"] else None
        if "text" in data and data["text"]:
            task.text = data["text"].strip()
        if "due" in data:
            task.due = data["due"]
        session.add(task)
        session.commit()
        session.refresh(task)
        return _task_out(task)


@router.delete("/tasks/{task_id}")
def delete_task(task_id: int):
    with Session(engine) as session:
        task = session.get(Task, task_id)
        if not task:
            raise HTTPException(404, "Tarea no encontrada")
        session.delete(task)
        session.commit()
        return {"status": "deleted"}


# ── Notas ──────────────────────────────────────────────────────────────────

class NoteIn(BaseModel):
    text: str = Field(min_length=1, max_length=2000)


@router.get("/notes")
def list_notes():
    with Session(engine) as session:
        rows = session.exec(select(Note).order_by(Note.created_at.desc())).all()
        return [{"id": n.id, "text": n.text, "created_at": n.created_at} for n in rows]


@router.post("/notes")
def create_note(payload: NoteIn):
    with Session(engine) as session:
        note = Note(text=payload.text.strip())
        session.add(note)
        session.commit()
        session.refresh(note)
        return {"id": note.id, "text": note.text, "created_at": note.created_at}


@router.delete("/notes/{note_id}")
def delete_note(note_id: int):
    with Session(engine) as session:
        note = session.get(Note, note_id)
        if not note:
            raise HTTPException(404, "Nota no encontrada")
        session.delete(note)
        session.commit()
        return {"status": "deleted"}


def pending_task_lines() -> list[str]:
    """Para el briefing de Telegram: tareas pendientes (max 5)."""
    import html
    with Session(engine) as session:
        rows = session.exec(select(Task).where(Task.done == False)).all()  # noqa: E712
    rows.sort(key=lambda t: (t.due or datetime.max, t.created_at))
    return [f"• {html.escape(t.text)}" for t in rows[:5]]
