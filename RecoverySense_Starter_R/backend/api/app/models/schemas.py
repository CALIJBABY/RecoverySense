from datetime import datetime
from pydantic import BaseModel, Field


class SensorReadingIn(BaseModel):
    participant_id: str = Field(default="demo-participant")
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
