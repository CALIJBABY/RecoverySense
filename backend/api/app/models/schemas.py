from datetime import datetime

from pydantic import BaseModel, Field


class SensorReadingIn(BaseModel):
    participant_id: str = Field(default="demo-participant")
    session_id: str = Field(default="session-0")
    timestamp: datetime
    heart_rate: float
    accel_x: float
    accel_y: float
    accel_z: float


class EmaAnswerIn(BaseModel):
    participant_id: str = Field(default="demo-participant")
    timestamp: datetime
    question: str
    answer: str
    craving_score: int = Field(ge=0, le=10)


class TriggerDecision(BaseModel):
    should_trigger_ema: bool
    reason: str
    probability: float | None = None
    threshold: float = 0.70
    model_ready: bool = False
    window_ready: bool = False
    buffered_samples: int | None = None
    required_samples: int | None = None
    cooldown_active: bool = False


class ModelStatus(BaseModel):
    model_ready: bool
    model_path: str
    threshold: float
    detail: str
