import html

from sqlmodel import Session, select

from . import config, notify
from .db import engine
from .models import Habit, HabitLog
from .stats import CATEGORY_LABELS


def _count_today(session: Session, habit_id: int, today) -> int:
    logs = session.exec(select(HabitLog).where(HabitLog.habit_id == habit_id)).all()
    return sum(1 for log in logs if config.to_local(log.done_at).date() == today)


def check_reminders():
    now = config.now_local()
    hhmm = now.strftime("%H:%M")
    today = now.date()
    with Session(engine) as session:
        habits = session.exec(select(Habit).where(Habit.active == True)).all()
        for habit in habits:
            if habit.category == "diet":
                continue
            if habit.schedule_type == "daily_times":
                times = habit.schedule or []
                if hhmm not in times:
                    continue
                if _count_today(session, habit.id, today) >= sum(1 for t in times if t <= hhmm):
                    continue
            elif habit.schedule_type == "week_days":
                sched = habit.schedule if isinstance(habit.schedule, dict) else {}
                days = sched.get("days") or []
                times = sched.get("times") or []
                if now.weekday() not in days or hhmm not in times:
                    continue
                if _count_today(session, habit.id, today) >= sum(1 for t in times if t <= hhmm):
                    continue
            else:
                if hhmm != "09:00":
                    continue
                interval = int(habit.schedule or 1)
                last_log = session.exec(
                    select(HabitLog)
                    .where(HabitLog.habit_id == habit.id)
                    .order_by(HabitLog.done_at.desc())
                ).first()
                days_since = (today - config.to_local(last_log.done_at).date()).days if last_log else interval
                if days_since < interval:
                    continue
            send_reminder(habit)


def send_reminder(habit: Habit):
    label = CATEGORY_LABELS.get(habit.category, habit.category)
    text = f"<b>{html.escape(habit.name)}</b>\nToca: {html.escape(label)}"
    notify.notify(text)
