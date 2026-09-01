"""Estado y renovacion del token de Google (Gmail/Calendar) + estado de Epitech.

En modo Testing el refresh_token de Google caduca a los 7 dias. Aqui se lleva un
contador (dias restantes desde la ultima autorizacion) y se ofrece renovar con
un flujo OAuth web de un toque: el boton abre el consentimiento de Google y el
callback guarda el token nuevo y reinicia el contador.

Para que el callback funcione, el cliente OAuth de Google debe tener registrado
el redirect URI <APP_URL>/api/auth/google/callback (cliente tipo Web), donde
APP_URL es la URL publica de tu instancia (variable del .env).
"""
import json
import os
from datetime import datetime, timezone

import requests
from google_auth_oauthlib.flow import Flow

from . import config
from .google_client import TOKEN_PATH, _credentials

META_PATH = os.path.join(os.path.dirname(__file__), "..", "token_meta.json")
WINDOW_DAYS = 7
SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/calendar.readonly",
]
def _redirect_uri() -> str:
    """Callback de Google: se deriva de APP_URL para que cada instancia use la
    suya sin tocar el codigo."""
    base = config.load_env().get("APP_URL", "http://localhost:8000").rstrip("/")
    return f"{base}/api/auth/google/callback"


def _authorized_at() -> datetime | None:
    if os.path.exists(META_PATH):
        try:
            ts = json.load(open(META_PATH, encoding="utf-8")).get("authorized_at")
            return datetime.fromisoformat(ts)
        except Exception:
            pass
    if os.path.exists(TOKEN_PATH):  # fallback: fecha del archivo
        return datetime.fromtimestamp(os.path.getmtime(TOKEN_PATH), tz=timezone.utc)
    return None


def set_authorized_now():
    with open(META_PATH, "w", encoding="utf-8") as f:
        json.dump({"authorized_at": datetime.now(timezone.utc).isoformat()}, f)


def _google_status() -> dict:
    env = config.load_env()
    # En modo Produccion el refresh_token NO caduca: sin cuenta atras.
    prod = env.get("GOOGLE_PROD", "").lower() in ("1", "true", "yes", "on")
    at = _authorized_at()
    days_left = None
    if at and not prod:
        days_left = WINDOW_DAYS - (datetime.now(timezone.utc) - at).days
    try:
        connected = _credentials() is not None
    except Exception:
        connected = False
    return {
        "authorized_at": at.isoformat() if at else None,
        "days_left": days_left,
        "production": prod,
        "connected": connected,
    }


def _epitech_status() -> dict:
    """Estado de la sesion del intra. Rapido y fiable: se basa en la caducidad
    de la cookie persistente (no en una llamada lenta que podria dar falsos
    negativos por timeout). La cookie marca la vida maxima de la sesion."""
    env = config.load_env()
    path = env.get("INTRA_SESSION_PATH", "/opt/intra-bot/session.json")
    days_left = None
    expires_at = None
    connected = False
    try:
        cookies = json.load(open(path, encoding="utf-8")).get("cookies", [])
        exps = [
            c["expires"] for c in cookies
            if c.get("name") in ("ESTSAUTHPERSISTENT", "ESTSAUTH") and c.get("expires", -1) > 0
        ]
        if exps:
            dt = datetime.fromtimestamp(min(exps), tz=timezone.utc)
            expires_at = dt.isoformat()
            days_left = (dt - datetime.now(timezone.utc)).days
            connected = days_left > 0
        elif os.path.exists(path):
            connected = True  # hay sesion pero sin cookie de caducidad legible
    except Exception:
        pass
    return {"connected": connected, "days_left": days_left, "expires_at": expires_at}


def status() -> dict:
    return {"google": _google_status(), "epitech": _epitech_status()}


def _flow() -> Flow:
    env = config.load_env()
    cfg = {
        "web": {
            "client_id": env["GOOGLE_CLIENT_ID"],
            "client_secret": env["GOOGLE_CLIENT_SECRET"],
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": [_redirect_uri()],
        }
    }
    flow = Flow.from_client_config(cfg, scopes=SCOPES)
    flow.redirect_uri = _redirect_uri()
    return flow


def consent_url() -> str:
    url, _ = _flow().authorization_url(
        access_type="offline", prompt="consent", include_granted_scopes="true"
    )
    return url


def handle_callback(code: str) -> bool:
    try:
        flow = _flow()
        flow.fetch_token(code=code)
        with open(TOKEN_PATH, "w", encoding="utf-8") as f:
            f.write(flow.credentials.to_json())
        set_authorized_now()
        return True
    except Exception:
        return False
