"""
event_detector.py — Detección automática de eventos en texto libre y correos.

Endpoints:
  POST /ai/detect-event   { text: str }  → DetectedEventsResponse
  GET  /ai/mail-events                   → DetectedEventsResponse
  POST /calendar/events   { title, start_iso, end_iso?, location? } → CreateEventResponse

Integración:
  from event_detector import router as events_router
  app.include_router(events_router)

Requisitos extra en requirements.txt:
  anthropic   (cliente Claude — ya lo tienes)
  google-auth
  google-auth-oauthlib
  google-api-python-client
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, date, timedelta
from typing import Optional

# ─── PROMPT DE EXTRACCIÓN ─────────────────────────────────────────────────────

_SYSTEM_DETECT = """Eres un asistente que extrae eventos de calendario a partir de texto informal en español.

Dado un texto (fragmento de WhatsApp, email, nota), devuelve un JSON con esta estructura exacta:
{
  "events": [
    {
      "id": "<uuid>",
      "title": "Nombre corto del evento (≤6 palabras)",
      "start_iso": "2026-07-15T19:00:00",  // fecha+hora ISO 8601 local; null si desconocida
      "end_iso": "2026-07-15T21:00:00",     // opcional, null si no se menciona
      "location": "Lugar o null",
      "confidence": 0.85,   // 0-1, cuán seguro estás de que es un evento real
      "source_snippet": "fragmento clave del texto"
    }
  ]
}

Reglas:
- Interpreta expresiones relativas respecto a hoy: %(today)s
- Si el texto habla de "mañana", "esta tarde", "el viernes"… convierte a fecha absoluta.
- Si la hora no se menciona, pon start_iso con solo la fecha y hora 00:00 y confidence ≤ 0.60.
- Si el texto NO contiene ningún evento (es una conversación sin plan concreto), devuelve events: [].
- Un evento debe tener al minimum algo temporal ("mañana", un día de la semana, una fecha).
- Solo devuelve el JSON, sin texto adicional.
"""

_SYSTEM_MAIL = """Eres un asistente que detecta eventos de calendario en asuntos y fragmentos de email.

Recibirás una lista de emails en formato JSON. Para cada email que contenga un evento concreto (reunión, cita, entrega, cena, evento social...), extrae el evento.

Devuelve solo el JSON:
{
  "events": [
    {
      "id": "<uuid>",
      "title": "Nombre del evento (≤6 palabras)",
      "start_iso": "2026-07-15T10:00:00",
      "end_iso": null,
      "location": null,
      "confidence": 0.90,
      "source_snippet": "asunto o fragmento del email"
    }
  ]
}

Reglas:
- Hoy es %(today)s.
- Ignora emails puramente promocionales, newsletters, facturas sin fecha de evento.
- Incluye: reuniones, cenas, citas, eventos con fecha, deadlines concretos.
- Solo devuelve el JSON.
"""

# ─── HELPERS ──────────────────────────────────────────────────────────────────

def _parse_detected(raw: str) -> list[dict]:
    try:
        data = json.loads(raw)
        events = data.get("events", [])
        for e in events:
            if "id" not in e or not e["id"]:
                e["id"] = str(uuid.uuid4())
        return [e for e in events if e.get("confidence", 0) >= 0.40]
    except Exception:
        return []

async def _ask_claude(system: str, user_msg: str, client) -> str:
    msg = await client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=1024,
        system=system,
        messages=[{"role": "user", "content": user_msg}],
    )
    return msg.content[0].text

# ─── GOOGLE CALENDAR ──────────────────────────────────────────────────────────

def _build_gcal_service(credentials_json: dict):
    from google.oauth2.credentials import Credentials
    from googleapiclient.discovery import build
    creds = Credentials(
        token=credentials_json.get("access_token"),
        refresh_token=credentials_json.get("refresh_token"),
        token_uri="https://oauth2.googleapis.com/token",
        client_id=credentials_json.get("client_id"),
        client_secret=credentials_json.get("client_secret"),
    )
    return build("calendar", "v3", credentials=creds, cache_discovery=False)

def _create_gcal_event(service, title: str, start_iso: str,
                        end_iso: Optional[str], location: Optional[str]) -> str:
    has_time = "T" in start_iso
    if has_time:
        start_body = {"dateTime": start_iso, "timeZone": "Europe/Madrid"}
        # Default duration: 1 hour if no end provided
        if end_iso:
            end_body = {"dateTime": end_iso, "timeZone": "Europe/Madrid"}
        else:
            from dateutil.parser import parse as dtparse
            dt_end = dtparse(start_iso) + timedelta(hours=1)
            end_body = {"dateTime": dt_end.isoformat(), "timeZone": "Europe/Madrid"}
    else:
        # All-day event
        d = start_iso[:10]
        start_body = {"date": d}
        end_body = {"date": d}

    body: dict = {"summary": title, "start": start_body, "end": end_body}
    if location: body["location"] = location

    result = service.events().insert(calendarId="primary", body=body).execute()
    return result.get("htmlLink", "")

# ─── FASTAPI ROUTER ───────────────────────────────────────────────────────────

try:
    from fastapi import APIRouter, Depends
    import anthropic

    router = APIRouter(tags=["events"])

    # Replace these with your actual dependency getters
    async def _get_anthropic(): ...   # type: ignore  → return anthropic.AsyncAnthropic(api_key=...)
    async def _get_gcal_creds(): ...  # type: ignore  → return your stored OAuth credentials dict
    async def _get_mail_client(): ... # type: ignore  → return your gmail client or cached messages
    async def _get_user_id() -> int: return 1

    @router.post("/ai/detect-event")
    async def detect_event_endpoint(
        body: dict,
        claude=Depends(_get_anthropic),
        uid: int = Depends(_get_user_id),
    ):
        text = body.get("text", "").strip()
        if not text:
            return {"events": []}
        system = _SYSTEM_DETECT % {"today": date.today().isoformat()}
        raw = await _ask_claude(system, text, claude)
        events = _parse_detected(raw)
        return {"events": events}

    @router.get("/ai/mail-events")
    async def mail_events_endpoint(
        claude=Depends(_get_anthropic),
        mail=Depends(_get_mail_client),
        uid: int = Depends(_get_user_id),
    ):
        # Fetch recent emails — adapt to your mail client
        # Expected format: list of {subject, snippet, date}
        messages = await mail.recent_messages(limit=20)  # type: ignore
        if not messages:
            return {"events": []}
        mail_json = json.dumps([
            {"subject": m.get("subject",""), "snippet": m.get("snippet",""), "date": m.get("date","")}
            for m in messages
        ], ensure_ascii=False)
        system = _SYSTEM_MAIL % {"today": date.today().isoformat()}
        raw = await _ask_claude(system, mail_json, claude)
        events = _parse_detected(raw)
        # Only show events in the future (or today)
        today_str = date.today().isoformat()
        future = [e for e in events if not e.get("start_iso") or e["start_iso"][:10] >= today_str]
        return {"events": future[:10]}  # cap at 10

    @router.post("/calendar/events")
    async def create_calendar_event(
        body: dict,
        gcal_creds=Depends(_get_gcal_creds),
        uid: int = Depends(_get_user_id),
    ):
        title    = body.get("title", "Evento")
        start    = body.get("start_iso")
        end      = body.get("end_iso")
        location = body.get("location")
        if not start:
            from fastapi import HTTPException
            raise HTTPException(400, "start_iso requerido")
        try:
            service = _build_gcal_service(gcal_creds)
            link = _create_gcal_event(service, title, start, end, location)
            return {"status": "ok", "link": link}
        except Exception as e:
            return {"status": "error", "link": None, "detail": str(e)}

except ImportError:
    router = None  # type: ignore
