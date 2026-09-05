"""Modulo Estudios: proxy al intra-api (que lanza Chromium headless, tarda
varios segundos).

Para no hacer esperar nunca al usuario, el resultado se persiste en disco
(studies_cache.json) y se considera valido TODO el dia: la pestana abre al
instante con los datos de hoy. Se refresca:
- solo (job de APScheduler a las 08:30),
- al entrar si aun no hay datos de hoy,
- o a mano con el boton de refrescar (GET /api/studies?refresh=1).
"""
import json
import os
import time

import requests

from . import config

CACHE_FILE = os.path.join(os.path.dirname(__file__), "..", "studies_cache.json")


def _load_disk() -> dict | None:
    try:
        with open(CACHE_FILE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _save_disk(payload: dict) -> None:
    try:
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False)
    except OSError:
        pass


def get_overview(force: bool = False) -> dict:
    cached = _load_disk()
    today = config.now_local().date().isoformat()
    if not force and cached and cached.get("day") == today:
        return cached["data"]

    result = _fetch()
    if result.get("status") == "ok":
        result["fetched_at"] = config.now_local().isoformat()
        _save_disk({"day": today, "data": result})
        return result
    # El intra fallo: mejor los datos de ayer que un error
    if cached:
        return cached["data"]
    return result


def prefetch() -> None:
    """Job diario (08:30): deja los datos de hoy listos antes de que mire."""
    try:
        get_overview(force=True)
    except Exception:
        pass


def _fetch() -> dict:
    env = config.load_env()
    base_url = env.get("INTRA_API_URL", "http://127.0.0.1:8000")
    api_key = env.get("INTRA_API_KEY")
    headers = {"X-API-Key": api_key} if api_key else {}

    try:
        resp = requests.get(f"{base_url}/study", headers=headers, timeout=60)
    except requests.RequestException as e:
        return {"status": "error", "detail": f"No se pudo conectar con el intra-bot: {e}"}

    if resp.status_code == 401:
        return {"status": "error", "detail": "Sesion del intra caducada, hace falta volver a iniciar sesion en el servidor"}
    if resp.status_code == 503:
        return {"status": "error", "detail": "El intra-bot no tiene sesion guardada todavia"}
    if not resp.ok:
        return {"status": "error", "detail": f"Error del intra-bot ({resp.status_code})"}

    return {"status": "ok", **resp.json()}
