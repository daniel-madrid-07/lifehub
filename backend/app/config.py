import os
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

TZ = ZoneInfo(os.environ.get("TIMEZONE", "Europe/Madrid"))


def load_env(path=".env"):
    env = dict(os.environ)
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
    return env


def now_local() -> datetime:
    return datetime.now(TZ)


def to_local(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(TZ)
