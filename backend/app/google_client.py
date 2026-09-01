import json
import os
import time
from datetime import datetime, timezone

import requests
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials

from . import config

CACHE_TTL = 300  # 5 min

TOKEN_PATH = os.path.join(os.path.dirname(__file__), "..", "token.json")

_cache: dict[str, dict] = {}
_cache_time: dict[str, float] = {}


def _credentials() -> Credentials | None:
    if not os.path.exists(TOKEN_PATH):
        return None

    env = config.load_env()
    with open(TOKEN_PATH, encoding="utf-8") as f:
        info = json.load(f)

    # client_id/secret pueden faltar en token.json; en google-auth modernos son
    # propiedades de solo lectura, asi que se inyectan en el dict ANTES
    if not info.get("client_id"):
        info["client_id"] = env.get("GOOGLE_CLIENT_ID")
    if not info.get("client_secret"):
        info["client_secret"] = env.get("GOOGLE_CLIENT_SECRET")

    creds = Credentials.from_authorized_user_info(info)
    if creds.expired and creds.refresh_token:
        creds.refresh(Request())
        with open(TOKEN_PATH, "w", encoding="utf-8") as f:
            f.write(creds.to_json())

    return creds


def _cached(key: str, fetch):
    now = time.time()
    if key in _cache and (now - _cache_time[key]) < CACHE_TTL:
        return _cache[key]

    result = fetch()
    if result.get("status") == "ok":
        _cache[key] = result
        _cache_time[key] = now
    return result


def get_mail_overview() -> dict:
    return _cached("mail", _fetch_mail)


def get_calendar_overview() -> dict:
    return _cached("calendar", _fetch_calendar)


def _auth_error(e: Exception) -> dict:
    return {"status": "error", "detail": f"No se pudo conectar con Google: {e}"}


def _fetch_mail() -> dict:
    creds = _credentials()
    if creds is None:
        return {"status": "error", "detail": "Falta token.json, hay que autorizar la cuenta de Google (google_auth.py)"}

    headers = {"Authorization": f"Bearer {creds.token}"}
    try:
        resp = requests.get(
            "https://gmail.googleapis.com/gmail/v1/users/me/messages",
            headers=headers,
            # NO nos fiamos de la etiqueta "importante" de Gmail (se deja correos
            # clave fuera): traemos TODO lo no leido de los ultimos 3 dias quitando
            # solo el ruido evidente (promociones/social) y luego filtra la IA.
            params={"q": "is:unread newer_than:3d -category:promotions -category:social", "maxResults": 30},
            timeout=20,
        )
        resp.raise_for_status()
        ids = [m["id"] for m in resp.json().get("messages", [])]

        messages = []
        for mid in ids:
            r = requests.get(
                f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{mid}",
                headers=headers,
                params={
                    "format": "metadata",
                    # las cabeceras de "lista de correo" delatan las suscripciones
                    "metadataHeaders": [
                        "Subject", "From", "List-Unsubscribe", "List-Id", "Precedence", "Auto-Submitted",
                    ],
                },
                timeout=20,
            )
            r.raise_for_status()
            data = r.json()
            hdrs = {h["name"].lower(): h["value"] for h in data.get("payload", {}).get("headers", [])}

            # Filtro automatico (sin IA): si el correo es de una lista/suscripcion
            # (tiene List-Unsubscribe / List-Id) o es automatico/masivo
            # (Precedence: bulk/list, Auto-Submitted), es ruido -> fuera. Lo que
            # te escribe una persona o un tramite real NO lleva estas cabeceras.
            if (
                "list-unsubscribe" in hdrs
                or "list-id" in hdrs
                or hdrs.get("precedence", "").lower() in ("bulk", "list", "junk")
                or hdrs.get("auto-submitted", "").lower() not in ("", "no")
            ):
                continue

            messages.append({
                "subject": hdrs.get("subject", "(sin asunto)"),
                "from": hdrs.get("from", ""),
                "snippet": data.get("snippet", ""),
                "date": data.get("internalDate"),
                "link": f"https://mail.google.com/mail/u/0/#inbox/{mid}",
            })

        return {"status": "ok", "messages": messages}
    except (requests.RequestException, ValueError) as e:
        return _auth_error(e)


def _fetch_calendar() -> dict:
    creds = _credentials()
    if creds is None:
        return {"status": "error", "detail": "Falta token.json, hay que autorizar la cuenta de Google (google_auth.py)"}

    headers = {"Authorization": f"Bearer {creds.token}"}
    time_min = datetime.now(timezone.utc).isoformat()
    try:
        resp = requests.get(
            "https://www.googleapis.com/calendar/v3/calendars/primary/events",
            headers=headers,
            params={
                "timeMin": time_min,
                "maxResults": 10,
                "singleEvents": "true",
                "orderBy": "startTime",
            },
            timeout=20,
        )
        resp.raise_for_status()
        events = []
        for ev in resp.json().get("items", []):
            start = ev.get("start", {})
            end = ev.get("end", {})
            events.append({
                "title": ev.get("summary", "(sin titulo)"),
                "start": start.get("dateTime") or start.get("date"),
                "end": end.get("dateTime") or end.get("date"),
                "location": ev.get("location"),
                "link": ev.get("htmlLink"),
            })

        return {"status": "ok", "events": events}
    except (requests.RequestException, ValueError) as e:
        return _auth_error(e)
