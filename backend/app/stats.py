from collections import defaultdict
from datetime import datetime, timedelta

from sqlmodel import Session, select

from . import config
from .models import Habit, HabitLog
from .schemas import HabitOut

CATEGORY_LABELS = {
    "water": "Agua",
    "medicine": "Medicina",
    "exercise": "Ejercicio",
    "sleep": "Sueño",
    "chore": "Tarea doméstica",
    "custom": "Rutina",
    "diet": "Comida",
}


def get_logs(session: Session, habit_id: int, days: int = 120):
    since = datetime.utcnow() - timedelta(days=days)
    return session.exec(
        select(HabitLog)
        .where(HabitLog.habit_id == habit_id, HabitLog.done_at >= since)
        .order_by(HabitLog.done_at.desc())
    ).all()


def habit_to_out(session: Session, habit: Habit) -> HabitOut:
    logs = get_logs(session, habit.id)
    today = config.now_local().date()
    last_done = logs[0].done_at if logs else None

    if habit.schedule_type == "daily_times":
        times = sorted(habit.schedule or [])
        times_total = len(times) or 1
        counts = defaultdict(int)
        for log in logs:
            counts[config.to_local(log.done_at).date()] += 1
        done_today = counts[today] >= times_total
        due_today = not done_today
        next_time = None
        if times and not done_today:
            next_time = times[min(counts[today], len(times) - 1)]
        streak = 0
        day = today if done_today else today - timedelta(days=1)
        while counts[day] >= times_total:
            streak += 1
            day -= timedelta(days=1)
        progress_label = f"{counts[today]}/{times_total} hoy"
    elif habit.schedule_type == "week_days":
        # schedule = {"days": [0-6, lunes=0], "times": ["HH:MM", ...]}
        sched = habit.schedule if isinstance(habit.schedule, dict) else {}
        days = set(sched.get("days") or [])
        times = sorted(sched.get("times") or [])
        times_total = len(times) or 1
        counts = defaultdict(int)
        for log in logs:
            counts[config.to_local(log.done_at).date()] += 1
        scheduled_today = today.weekday() in days
        done_today = scheduled_today and counts[today] >= times_total
        due_today = scheduled_today and not done_today
        next_time = None
        if due_today and times:
            next_time = times[min(counts[today], len(times) - 1)]
        # racha: dias programados consecutivos cumplidos (los de descanso no cortan)
        streak = 0
        if days:
            day = today - timedelta(days=1) if due_today else today
            for _ in range(365):
                if day.weekday() in days:
                    if counts[day] >= times_total:
                        streak += 1
                    else:
                        break
                day -= timedelta(days=1)
        if scheduled_today:
            progress_label = f"{counts[today]}/{times_total} hoy"
        else:
            progress_label = "Descanso hoy"
    else:
        interval = int(habit.schedule or 1)
        dates = sorted({config.to_local(log.done_at).date() for log in logs}, reverse=True)
        done_today = bool(dates and dates[0] == today)
        due_today = not done_today and (not dates or (today - dates[0]).days >= interval)
        next_time = None
        streak = 0
        if dates and (today - dates[0]).days <= interval:
            streak = 1
            for i in range(len(dates) - 1):
                gap = (dates[i] - dates[i + 1]).days
                if gap <= interval:
                    streak += 1
                else:
                    break
        if not dates:
            progress_label = "Nunca hecho"
        else:
            days_since = (today - dates[0]).days
            if days_since >= interval:
                progress_label = f"Toca ya (hace {days_since}d)"
            else:
                progress_label = f"Proximo en {interval - days_since}d"

    return HabitOut(
        id=habit.id,
        name=habit.name,
        category=habit.category,
        schedule_type=habit.schedule_type,
        schedule=habit.schedule,
        active=habit.active,
        created_at=habit.created_at,
        streak=streak,
        done_today=done_today,
        due_today=due_today,
        next_time=next_time,
        progress_label=progress_label,
        last_done=last_done,
    )
