"""Canal unico de avisos. Por defecto van por Web Push (la app en el iPhone);
configurable con NOTIFY_CHANNEL = push | telegram | both.

Asi el usuario recibe todo SOLO en la app. Telegram queda como fallback de un
flag por si el push fallara."""
import re

from . import config, push, telegram


def _strip_html(s: str) -> str:
    return re.sub(r"<[^>]+>", "", s or "")


def notify(html_text: str, url: str = "/") -> None:
    """Recibe el texto en formato Telegram (con <b>..); manda push (texto
    plano, titulo = 1a linea) y/o Telegram segun NOTIFY_CHANNEL."""
    env = config.load_env()
    channel = (env.get("NOTIFY_CHANNEL") or "push").strip().lower()

    if channel in ("push", "both"):
        plain = _strip_html(html_text)
        lines = [ln for ln in plain.split("\n") if ln.strip()]
        title = lines[0] if lines else "Life Hub"
        body = "\n".join(lines[1:]) if len(lines) > 1 else ""
        try:
            push.send_push(title, body, url)
        except Exception:
            pass

    if channel in ("telegram", "both"):
        try:
            telegram.send_message(env, html_text)
        except Exception:
            pass
