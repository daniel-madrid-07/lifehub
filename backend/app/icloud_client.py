"""Calendario del iPhone (iCloud) via CalDAV + cumpleanos via CardDAV.

Necesita en backend/.env:
  ICLOUD_USERNAME      — el Apple ID (email)
  ICLOUD_APP_PASSWORD  — contrasena de app creada en https://account.apple.com
                         (Inicio de sesion y seguridad > Contrasenas de apps)

iCloud NO expone el calendario "Cumpleanos" por CalDAV (lo genera de los
contactos), asi que los cumpleanos se leen de los propios contactos por
CardDAV (contacts.icloud.com) y se sintetizan como eventos de dia entero.

Mismo contrato que el resto de modulos: {"status": "ok", "events": [...]} o
{"status": "error", "detail": "..."}. Cache en memoria de 5 minutos.
"""
import re
import time
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta, timezone
from urllib.parse import urljoin

import requests

from . import config

CACHE_TTL = 300  # 5 min
DAYS_AHEAD = 30
MAX_EVENTS = 20

_cache: dict | None = None
_cache_time = 0.0


def get_calendar_overview() -> dict:
    global _cache, _cache_time
    if _cache is not None and (time.time() - _cache_time) < CACHE_TTL:
        return _cache

    result = _fetch()
    if result.get("status") == "ok":
        _cache = result
        _cache_time = time.time()
    elif _cache is not None:
        # iCloud falla a ratos: mejor datos de hace un rato que un error
        return _cache
    return result


def _fetch() -> dict:
    env = config.load_env()
    user = env.get("ICLOUD_USERNAME")
    password = env.get("ICLOUD_APP_PASSWORD")
    if not user or not password:
        return {
            "status": "error",
            "detail": "Faltan ICLOUD_USERNAME / ICLOUD_APP_PASSWORD en .env "
                      "(crear contrasena de app en account.apple.com)",
        }

    import caldav  # import perezoso: tarda y solo hace falta aqui

    try:
        # timeout: sin el, una respuesta colgada de iCloud bloquea la
        # peticion (y el frontend se queda en el skeleton para siempre)
        client = caldav.DAVClient(
            url="https://caldav.icloud.com/", username=user, password=password, timeout=15
        )
        principal = client.principal()
        calendars = principal.calendars()
    except Exception as e:
        return {"status": "error", "detail": f"No se pudo conectar con iCloud: {e}"}

    start = datetime.now(timezone.utc)
    end = start + timedelta(days=DAYS_AHEAD)
    events = []
    for cal in calendars:
        try:
            found = cal.search(start=start, end=end, event=True, expand=True)
        except Exception:
            continue  # calendarios raros (cumpleanos, suscritos) pueden fallar
        for item in found:
            try:
                comp = item.icalendar_component
            except Exception:
                continue
            if comp is None or comp.get("summary") is None:
                continue
            events.append({
                "title": str(comp.get("summary")),
                "start": _iso(comp.get("dtstart")),
                "end": _iso(comp.get("dtend")),
                "location": str(comp.get("location")) if comp.get("location") else None,
                "link": None,
            })

    try:
        events.extend(_fetch_birthdays(user, password))
    except Exception:
        pass  # sin cumpleanos antes que sin agenda

    events = [e for e in events if e["start"]]
    events.sort(key=lambda e: _sort_key(e["start"]))
    return {"status": "ok", "events": events[:MAX_EVENTS]}


# ── Cumpleanos (CardDAV) ───────────────────────────────────────────────────

_DAV = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:carddav"}


def _dav(method: str, url: str, auth, body: str, depth: str) -> ET.Element:
    resp = requests.request(
        method,
        url,
        auth=auth,
        data=body.encode(),
        headers={"Depth": depth, "Content-Type": "text/xml; charset=utf-8"},
        timeout=15,
    )
    resp.raise_for_status()
    return ET.fromstring(resp.content)


def _fetch_birthdays(user: str, password: str) -> list[dict]:
    auth = (user, password)
    base = "https://contacts.icloud.com/"

    root = _dav("PROPFIND", base, auth,
                '<?xml version="1.0"?><d:propfind xmlns:d="DAV:">'
                '<d:prop><d:current-user-principal/></d:prop></d:propfind>', "0")
    principal = root.find(".//d:current-user-principal/d:href", _DAV)
    if principal is None or not principal.text:
        return []

    root = _dav("PROPFIND", urljoin(base, principal.text), auth,
                '<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:carddav">'
                '<d:prop><c:addressbook-home-set/></d:prop></d:propfind>', "0")
    home = root.find(".//c:addressbook-home-set/d:href", _DAV)
    if home is None or not home.text:
        return []

    root = _dav("REPORT", urljoin(base, home.text) + "card/", auth,
                '<?xml version="1.0"?><c:addressbook-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:carddav">'
                '<d:prop><c:address-data/></d:prop></c:addressbook-query>', "1")

    today = config.now_local().date()
    horizon = today + timedelta(days=DAYS_AHEAD)
    events = []
    for node in root.findall(".//c:address-data", _DAV):
        vcard = node.text or ""
        # des-plegar lineas (continuacion = empieza por espacio/tab)
        vcard = re.sub(r"\r?\n[ \t]", "", vcard)
        name = None
        bday = None
        phone = None
        for line in vcard.splitlines():
            up = line.upper()
            if up.startswith("FN"):
                name = line.split(":", 1)[-1].strip()
            elif up.startswith("BDAY"):
                bday = line.split(":", 1)[-1].strip()
            elif up.startswith("TEL") and phone is None:
                phone = re.sub(r"[^\d+]", "", line.split(":", 1)[-1])
        if not name or not bday:
            continue
        # Formatos: 1999-04-12 / 19990412 / --0412 / 1604-04-12 (ano omitido)
        m = re.match(r"^(?:(\d{4})|--)?-?(\d{2})-?(\d{2})$", bday)
        if not m:
            continue
        month, day = int(m.group(2)), int(m.group(3))
        try:
            next_bday = date(today.year, month, day)
        except ValueError:
            continue  # 29 de febrero en ano no bisiesto
        if next_bday < today:
            try:
                next_bday = date(today.year + 1, month, day)
            except ValueError:
                continue
        if today <= next_bday <= horizon:
            # si hay telefono, el evento abre WhatsApp para felicitar
            wa = None
            if phone:
                num = phone.lstrip("+")
                wa = f"https://wa.me/{num}?text=%C2%A1Feliz%20cumplea%C3%B1os%21"
            events.append({
                "title": f"Cumpleaños de {name}",
                "start": next_bday.isoformat(),
                "end": None,
                "location": "Felicitar por WhatsApp" if wa else None,
                "link": wa,
            })
    return events


def _iso(prop) -> str | None:
    """DTSTART/DTEND de icalendar -> ISO. Fecha sin hora = evento de dia entero
    (el frontend detecta 'sin T' como dia completo)."""
    if prop is None:
        return None
    dt = prop.dt
    if isinstance(dt, datetime):
        return config.to_local(dt).isoformat()
    if isinstance(dt, date):
        return dt.isoformat()
    return None


def _sort_key(iso: str) -> str:
    # "YYYY-MM-DD" (dia entero) debe ordenar antes que horas del mismo dia
    return iso if "T" in iso else iso + "T00:00:00"


# ── Crear evento ───────────────────────────────────────────────────────────────

def _build_ical(uid: str, title: str, start_iso: str,
                end_iso: str | None, location: str | None) -> str:
    from datetime import datetime, date as date_type
    now_stamp = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    has_time = "T" in start_iso
    if has_time:
        dt_s = datetime.fromisoformat(start_iso)
        if end_iso and "T" in end_iso:
            dt_e = datetime.fromisoformat(end_iso)
        else:
            dt_e = dt_s + timedelta(hours=1)
        dtstart = f"DTSTART;TZID=Europe/Madrid:{dt_s.strftime('%Y%m%dT%H%M%S')}"
        dtend   = f"DTEND;TZID=Europe/Madrid:{dt_e.strftime('%Y%m%dT%H%M%S')}"
    else:
        d = start_iso[:10].replace("-", "")
        next_d = (date_type.fromisoformat(start_iso[:10]) + timedelta(days=1)).strftime("%Y%m%d")
        dtstart = f"DTSTART;VALUE=DATE:{d}"
        dtend   = f"DTEND;VALUE=DATE:{next_d}"

    lines = [
        "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Life Hub//EN",
        "BEGIN:VEVENT",
        f"UID:{uid}@lifehub",
        f"DTSTAMP:{now_stamp}",
        dtstart, dtend,
        f"SUMMARY:{title}",
    ]
    if location:
        lines.append(f"LOCATION:{location}")
    lines += ["END:VEVENT", "END:VCALENDAR"]
    return "\r\n".join(lines) + "\r\n"


def create_event(title: str, start_iso: str,
                 end_iso: str | None, location: str | None) -> str:
    import uuid, caldav
    env = config.load_env()
    user     = env.get("ICLOUD_USERNAME")
    password = env.get("ICLOUD_APP_PASSWORD")
    if not user or not password:
        raise ValueError("Faltan ICLOUD_USERNAME / ICLOUD_APP_PASSWORD en .env")

    client = caldav.DAVClient(
        url="https://caldav.icloud.com/", username=user, password=password, timeout=20
    )
    principal = client.principal()
    calendars = principal.calendars()

    # Primer calendario que no sea cumpleaños ni festivos (son de solo lectura)
    skip = {"birthday", "cumpleaños", "holidays", "festivos", "siri"}
    target = next(
        (c for c in calendars if not any(s in (c.name or "").lower() for s in skip)),
        calendars[0] if calendars else None,
    )
    if target is None:
        raise ValueError("No hay calendarios disponibles en iCloud")

    uid  = str(uuid.uuid4())
    ical = _build_ical(uid, title, start_iso, end_iso, location)
    target.add_event(ical)

    # Invalida la cache para que el siguiente GET /api/calendar vea el nuevo evento
    global _cache, _cache_time
    _cache = None
    _cache_time = 0.0

    return uid
