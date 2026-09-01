"""Modulo Finanzas: lee las carteras de Alpaca (paper, USD) y Bitvavo (real, EUR).

Las claves son las mismas que usa MarketPulse. Se leen de backend/.env o,
si esta definido MARKETPULSE_ENV_FILE (ruta al .env del bot, p.ej.
/opt/marketpulse/.env en el servidor), de ahi — asi no hay que duplicarlas.
"""
import hashlib
import hmac
import json
import os
import socket
import sqlite3
import time
from datetime import datetime, timezone

import requests

from . import config

# La whitelist de IP de la clave de Bitvavo solo cubre la IPv4 del servidor;
# por IPv6 responde 403 (errorCode 307). Mismo motivo por el que el bot usa
# https.Agent({family: 4}). El hook de urllib3 (allowed_gai_family) ya no
# surte efecto en urllib3 2.x, asi que se filtra la resolucion DNS solo
# para el host de Bitvavo.
_orig_getaddrinfo = socket.getaddrinfo


def _v4_first_getaddrinfo(host, *args, **kwargs):
    results = _orig_getaddrinfo(host, *args, **kwargs)
    if host == "api.bitvavo.com":
        v4 = [r for r in results if r[0] == socket.AF_INET]
        return v4 or results
    return results


socket.getaddrinfo = _v4_first_getaddrinfo

CACHE_TTL = 120  # 2 min — datos de mercado, queremos frescura sin spamear

_cache: dict[str, dict] = {}
_cache_time: dict[str, float] = {}

BITVAVO_URL = "https://api.bitvavo.com/v2"


def _env() -> dict:
    env = config.load_env()
    extra = env.get("MARKETPULSE_ENV_FILE")
    if extra and os.path.exists(extra):
        for line in open(extra, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env.setdefault(k.strip(), v.strip())
    return env


def _cached(key: str, fetch):
    now = time.time()
    if key in _cache and (now - _cache_time[key]) < CACHE_TTL:
        return _cache[key]
    result = fetch()
    if result.get("status") == "ok":
        _cache[key] = result
        _cache_time[key] = now
    return result


def get_alpaca_overview() -> dict:
    return _cached("alpaca", _fetch_alpaca)


def get_bitvavo_overview() -> dict:
    return _cached("bitvavo", _fetch_bitvavo)


# ── Resumen combinado + historico ──────────────────────────────────────────

FX_TTL = 12 * 3600  # el cambio USD/EUR no necesita mas frescura
_fx_rate: float | None = None
_fx_time = 0.0


def _usd_to_eur() -> float | None:
    """Cambio USD->EUR (BCE via frankfurter.app, gratis y sin clave)."""
    global _fx_rate, _fx_time
    if _fx_rate is not None and (time.time() - _fx_time) < FX_TTL:
        return _fx_rate
    try:
        resp = requests.get(
            "https://api.frankfurter.app/latest",
            params={"from": "USD", "to": "EUR"},
            timeout=15,
        )
        resp.raise_for_status()
        _fx_rate = float(resp.json()["rates"]["EUR"])
        _fx_time = time.time()
    except (requests.RequestException, ValueError, KeyError):
        pass  # si falla, devolvemos el rate viejo (o None la primera vez)
    return _fx_rate


def _equity_history(rate: float | None) -> list[dict]:
    """Snapshots diarios de equity que MarketPulse guarda en su SQLite
    (eventos EQUITY_SNAPSHOT). Solo lectura; en local el archivo no existe
    y se devuelve lista vacia."""
    db = _env().get("MARKETPULSE_DB", "/opt/marketpulse/data/marketpulse.sqlite")
    if not os.path.exists(db):
        return []
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        rows = con.execute(
            "select payload, created_at from events where type='EQUITY_SNAPSHOT' order by created_at"
        ).fetchall()
        con.close()
    except sqlite3.Error:
        return []

    by_day: dict[str, dict] = {}
    for payload, created_at in rows:
        try:
            data = json.loads(payload)
            day = datetime.fromtimestamp(created_at / 1000, tz=timezone.utc).date().isoformat()
        except (ValueError, OSError):
            continue
        alpaca = float(data.get("alpacaEquity") or 0)
        bitvavo = float(data.get("bitvavoEur") or 0)
        by_day[day] = {
            "date": day,
            "alpaca_usd": round(alpaca, 2),
            "bitvavo_eur": round(bitvavo, 2),
            "total_eur": round(alpaca * rate + bitvavo, 2) if rate else None,
        }
    return list(by_day.values())


def get_summary() -> dict:
    """Patrimonio total combinado (EUR) + curva historica para la grafica."""
    alpaca = get_alpaca_overview()
    bitvavo = get_bitvavo_overview()
    rate = _usd_to_eur()

    alpaca_eur = None
    if alpaca.get("status") == "ok" and rate:
        alpaca_eur = round(alpaca["equity"] * rate, 2)
    bitvavo_eur = bitvavo.get("equity") if bitvavo.get("status") == "ok" else None

    total = None
    if alpaca_eur is not None and bitvavo_eur is not None:
        total = round(alpaca_eur + bitvavo_eur, 2)

    return {
        "status": "ok",
        "rate": rate,
        "alpaca_usd": alpaca.get("equity") if alpaca.get("status") == "ok" else None,
        "alpaca_eur": alpaca_eur,
        "bitvavo_eur": bitvavo_eur,
        "total_eur": total,
        "day_change_pct": alpaca.get("day_change_pct") if alpaca.get("status") == "ok" else None,
        "history": _equity_history(rate),
    }


# ── Alpaca (paper trading, USD) ────────────────────────────────────────────

def _fetch_alpaca() -> dict:
    env = _env()
    key, secret = env.get("ALPACA_KEY"), env.get("ALPACA_SECRET")
    if not key or not secret:
        return {"status": "error", "detail": "Faltan ALPACA_KEY / ALPACA_SECRET en .env"}
    base = env.get("ALPACA_BASE_URL", "https://paper-api.alpaca.markets")
    headers = {"APCA-API-KEY-ID": key, "APCA-API-SECRET-KEY": secret}

    try:
        acct = requests.get(f"{base}/v2/account", headers=headers, timeout=15)
        acct.raise_for_status()
        a = acct.json()
        pos = requests.get(f"{base}/v2/positions", headers=headers, timeout=15)
        pos.raise_for_status()
    except (requests.RequestException, ValueError) as e:
        return {"status": "error", "detail": f"No se pudo conectar con Alpaca: {e}"}

    equity = float(a.get("equity") or 0)
    last_equity = float(a.get("last_equity") or 0) or equity

    positions = []
    for p in pos.json():
        market_value = float(p.get("market_value") or 0)
        positions.append({
            "symbol": p.get("symbol"),
            "qty": float(p.get("qty") or 0),
            "price": float(p.get("current_price") or 0),
            "value": market_value,
            "pnl": float(p.get("unrealized_pl") or 0),
            "pnl_pct": float(p.get("unrealized_plpc") or 0) * 100,
            "day_pct": float(p.get("change_today") or 0) * 100,
        })
    positions.sort(key=lambda x: -x["value"])

    return {
        "status": "ok",
        "currency": "USD",
        "equity": equity,
        "cash": float(a.get("cash") or 0),
        "day_change": equity - last_equity,
        "day_change_pct": (equity / last_equity - 1) * 100 if last_equity else 0,
        "positions": positions,
    }


# ── Bitvavo (dinero real, EUR) ─────────────────────────────────────────────

def _bitvavo_get(env: dict, path: str) -> requests.Response:
    """GET firmado, mismo esquema HMAC que data-sources/bitvavo.ts del bot."""
    ts = str(int(time.time() * 1000))
    msg = f"{ts}GET/v2{path}"
    sig = hmac.new(env["BITVAVO_API_SECRET"].encode(), msg.encode(), hashlib.sha256).hexdigest()
    headers = {
        "Bitvavo-Access-Key": env["BITVAVO_API_KEY"],
        "Bitvavo-Access-Signature": sig,
        "Bitvavo-Access-Timestamp": ts,
        "Bitvavo-Access-Window": "10000",
    }
    return requests.get(BITVAVO_URL + path, headers=headers, timeout=15)


def _fetch_bitvavo() -> dict:
    env = _env()
    if not env.get("BITVAVO_API_KEY") or not env.get("BITVAVO_API_SECRET"):
        return {"status": "error", "detail": "Faltan BITVAVO_API_KEY / BITVAVO_API_SECRET en .env"}

    try:
        resp = _bitvavo_get(env, "/balance")
        resp.raise_for_status()
        balances = resp.json()
    except (requests.RequestException, ValueError) as e:
        return {"status": "error", "detail": f"No se pudo conectar con Bitvavo: {e}"}
    if isinstance(balances, dict):  # error de la API: {"errorCode": ..., "error": ...}
        return {"status": "error", "detail": f"Bitvavo: {balances.get('error', balances)}"}

    cash = 0.0
    positions = []
    day_change = 0.0
    for b in balances:
        qty = float(b.get("available") or 0) + float(b.get("inOrder") or 0)
        if qty <= 0:
            continue
        symbol = b.get("symbol")
        if symbol == "EUR":
            cash = qty
            continue
        # precio y variacion diaria via ticker publico
        price = 0.0
        open24h = None
        try:
            t = requests.get(f"{BITVAVO_URL}/ticker/24h", params={"market": f"{symbol}-EUR"}, timeout=15)
            if t.ok:
                data = t.json()
                price = float(data.get("last") or 0)
                open24h = float(data["open"]) if data.get("open") else None
        except (requests.RequestException, ValueError):
            pass
        value = qty * price
        pos_day = qty * (price - open24h) if open24h else 0.0
        day_change += pos_day
        positions.append({
            "symbol": symbol,
            "qty": qty,
            "price": price,
            "value": value,
            "pnl": None,  # Bitvavo no da coste medio por la API
            "pnl_pct": None,
            "day_pct": (price / open24h - 1) * 100 if open24h else 0,
        })
    positions.sort(key=lambda x: -x["value"])

    equity = cash + sum(p["value"] for p in positions)
    prev = equity - day_change
    return {
        "status": "ok",
        "currency": "EUR",
        "equity": equity,
        "cash": cash,
        "day_change": day_change,
        "day_change_pct": (equity / prev - 1) * 100 if prev else 0,
        "positions": positions,
    }
