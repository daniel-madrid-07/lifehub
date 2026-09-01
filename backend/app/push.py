"""Notificaciones Web Push (PWA en el iPhone).

Requiere en el .env:
  VAPID_PUBLIC_KEY   — clave publica (applicationServerKey, la usa el frontend)
  VAPID_SUB          — "mailto:..." del responsable
y el archivo backend/vapid_private.pem con la clave privada.

El frontend pide permiso, se suscribe con la clave publica y manda la
suscripcion a /api/push/subscribe. send_push() envia a todas las
suscripciones guardadas (y borra las caducadas, error 404/410).
"""
import os

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from sqlmodel import Session, select

from . import config
from .db import engine
from .models import PushSubscription

router = APIRouter(prefix="/api/push")

PRIVATE_PEM = os.path.join(os.path.dirname(__file__), "..", "vapid_private.pem")


def _env():
    return config.load_env()


class SubIn(BaseModel):
    endpoint: str
    keys: dict  # {"p256dh": "...", "auth": "..."}


@router.get("/vapid")
def vapid_key():
    return {"key": _env().get("VAPID_PUBLIC_KEY", "")}


@router.post("/subscribe")
def subscribe(payload: SubIn):
    p256dh = payload.keys.get("p256dh")
    auth = payload.keys.get("auth")
    if not payload.endpoint or not p256dh or not auth:
        raise HTTPException(400, "Suscripcion incompleta")
    with Session(engine) as session:
        existing = session.exec(
            select(PushSubscription).where(PushSubscription.endpoint == payload.endpoint)
        ).first()
        if existing:
            existing.p256dh = p256dh
            existing.auth = auth
            session.add(existing)
        else:
            session.add(PushSubscription(endpoint=payload.endpoint, p256dh=p256dh, auth=auth))
        session.commit()
    return {"status": "ok"}


@router.post("/unsubscribe")
def unsubscribe(payload: dict):
    endpoint = payload.get("endpoint")
    with Session(engine) as session:
        sub = session.exec(
            select(PushSubscription).where(PushSubscription.endpoint == endpoint)
        ).first()
        if sub:
            session.delete(sub)
            session.commit()
    return {"status": "ok"}


@router.post("/test")
def test_push():
    n = send_push("Life Hub", "Funciona. Las notificaciones estan activas.", "/")
    return {"sent": n}


def send_push(title: str, body: str, url: str = "/") -> int:
    """Envia una notificacion a todas las suscripciones. Devuelve cuantas
    se entregaron. Silencioso si falta config."""
    from pywebpush import WebPushException, webpush

    env = _env()
    pub = env.get("VAPID_PUBLIC_KEY")
    sub = env.get("VAPID_SUB")
    if not pub or not sub or not os.path.exists(PRIVATE_PEM):
        return 0

    import json

    payload = json.dumps({"title": title, "body": body, "url": url})
    sent = 0
    with Session(engine) as session:
        subs = session.exec(select(PushSubscription)).all()
        for s in subs:
            info = {"endpoint": s.endpoint, "keys": {"p256dh": s.p256dh, "auth": s.auth}}
            try:
                webpush(
                    subscription_info=info,
                    data=payload,
                    vapid_private_key=PRIVATE_PEM,
                    vapid_claims={"sub": sub},
                    timeout=15,
                )
                sent += 1
            except WebPushException as e:
                status = getattr(e.response, "status_code", None)
                if status in (404, 410):  # suscripcion caducada: borrar
                    session.delete(s)
            except Exception:
                pass
        session.commit()
    return sent
