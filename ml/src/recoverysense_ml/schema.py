from __future__ import annotations

from typing import Any

import pandas as pd


class DataValidationError(ValueError):
    """Raised when an input dataset does not match the RecoverySense schema."""


def validate_sensor_frame(frame: pd.DataFrame, config: dict[str, Any]) -> None:
    schema = config["schema"]
    required = {
        schema["participant_column"],
        schema["timestamp_column"],
        schema["heart_rate_column"],
        *schema["accel_columns"],
    }
    missing = sorted(required.difference(frame.columns))
    if missing:
        raise DataValidationError(
            "Sensor CSV is missing required columns: " + ", ".join(missing)
        )
    if frame.empty:
        raise DataValidationError("Sensor CSV contains no rows.")


def validate_ema_frame(frame: pd.DataFrame, config: dict[str, Any]) -> None:
    schema = config["schema"]
    required = {
        schema["participant_column"],
        schema["timestamp_column"],
        "craving_score",
    }
    missing = sorted(required.difference(frame.columns))
    if missing:
        raise DataValidationError(
            "EMA CSV is missing required columns: " + ", ".join(missing)
        )
