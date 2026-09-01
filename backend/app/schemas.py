from datetime import datetime
from typing import Any, Literal, Optional

from pydantic import BaseModel, Field

ScheduleType = Literal["daily_times", "week_days", "interval_days"]


class HabitCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    category: str = Field(max_length=50)
    schedule_type: ScheduleType
    schedule: Any
    active: bool = True


class HabitUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=200)
    category: Optional[str] = Field(default=None, max_length=50)
    schedule_type: Optional[ScheduleType] = None
    schedule: Optional[Any] = None
    active: Optional[bool] = None


class HabitOut(BaseModel):
    id: int
    name: str
    category: str
    schedule_type: str
    schedule: Any
    active: bool
    created_at: datetime
    streak: int
    done_today: bool
    due_today: bool
    next_time: Optional[str] = None
    progress_label: str
    last_done: Optional[datetime] = None


class HabitLogOut(BaseModel):
    id: int
    habit_id: int
    done_at: datetime
    note: Optional[str] = None


# (el perfil corporal no es configurable: los datos de Daniel viven
#  hardcodeados en frontend/src/me.ts — la app es de un solo usuario)
