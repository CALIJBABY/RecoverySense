from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class SensorReadingIn(BaseModel):
    """One timestamped watch sample plus optional prior-night context.

    Extra fields are rejected so a client/schema mismatch is visible rather
    than silently discarded before model inference.
    """

    model_config = ConfigDict(extra="forbid")

    participant_id: str = Field(min_length=1, max_length=128)
    session_id: str = Field(min_length=1, max_length=128)
    timestamp: datetime
    heart_rate: float = Field(ge=0, le=260)
    accel_x: float = Field(ge=-200, le=200)
    accel_y: float = Field(ge=-200, le=200)
    accel_z: float = Field(ge=-200, le=200)

    gyro_x: float | None = Field(default=None, ge=-100, le=100)
    gyro_y: float | None = Field(default=None, ge=-100, le=100)
    gyro_z: float | None = Field(default=None, ge=-100, le=100)
    step_count: float | None = Field(default=None, ge=0)
    step_detected: float | None = Field(default=None, ge=0)
    heart_rate_accuracy: float | None = None
    accelerometer_accuracy: float | None = None
    gyroscope_accuracy: float | None = None
    heart_rate_age_ms: float | None = Field(default=None, ge=0)
    off_body: float | None = Field(default=None, ge=0, le=1)
    screen_interactive: float | None = Field(default=None, ge=0, le=1)
    timezone_offset_minutes: int | None = Field(default=None, ge=-840, le=840)

    sleep_log_available: float | None = Field(default=None, ge=0, le=1)
    sleep_log_stale: float | None = Field(default=None, ge=0, le=1)
    sleep_log_age_hours: float | None = Field(default=None, ge=0)
    prior_sleep_duration_minutes: float | None = Field(default=None, ge=0)
    prior_sleep_efficiency: float | None = Field(default=None, ge=0, le=1)
    prior_sleep_awakenings: float | None = Field(default=None, ge=0)
    prior_sleep_waso_minutes: float | None = Field(default=None, ge=0)
    prior_sleep_overnight_mean_hr: float | None = Field(default=None, ge=0, le=260)
    prior_sleep_overnight_movement_std_g: float | None = Field(default=None, ge=0)
    prior_sleep_estimate_confidence: float | None = Field(default=None, ge=0, le=1)
    prior_sleep_quality: float | None = Field(default=None, ge=1, le=5)
    prior_rested_score: float | None = Field(default=None, ge=1, le=5)
    prior_sleep_watch_removed: float | None = Field(default=None, ge=0, le=1)


class EmaAnswerIn(BaseModel):
    """The required repeated EMA label used by the craving model."""

    model_config = ConfigDict(extra="forbid")

    participant_id: str = Field(min_length=1, max_length=128)
    session_id: str | None = Field(default=None, max_length=128)
    timestamp: datetime
    craving_score: int = Field(ge=0, le=10)
    source: str = Field(default="manual", min_length=1, max_length=64)
    response_device: Literal["watch", "phone", "unknown"] = "unknown"
    response_delay_ms: int | None = Field(default=None, ge=0)


class ModelContributor(BaseModel):
    feature: str
    display_name: str
    contribution: float
    value: float | None = None
    direction: Literal["increasing", "decreasing"] = "increasing"


class TriggerDecision(BaseModel):
    should_trigger_ema: bool
    reason: str
    probability: float | None = Field(default=None, ge=0, le=1)
    threshold: float = Field(default=0.70, ge=0, le=1)
    model_ready: bool = False
    window_ready: bool = False
    buffered_samples: int | None = Field(default=None, ge=0)
    required_samples: int | None = Field(default=None, ge=0)
    cooldown_active: bool = False
    model_name: str | None = None
    model_version: str | None = None
    interpretability_model: str | None = None
    interpretability_method: str | None = None
    interpretability_probability: float | None = Field(default=None, ge=0, le=1)
    top_contributors: list[ModelContributor] = Field(default_factory=list)


class ModelStatus(BaseModel):
    model_ready: bool
    model_path: str
    threshold: float = Field(ge=0, le=1)
    detail: str
