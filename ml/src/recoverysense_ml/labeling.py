from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd

from .schema import validate_ema_frame


AMBIGUOUS_LABEL = -1


def prepare_ema_data(frame: pd.DataFrame, config: dict[str, Any]) -> pd.DataFrame:
    validate_ema_frame(frame, config)
    schema = config["schema"]
    participant = schema["participant_column"]
    timestamp = schema["timestamp_column"]
    result = frame.copy()
    result[timestamp] = pd.to_datetime(result[timestamp], utc=True, errors="coerce", format="mixed")
    result["craving_score"] = pd.to_numeric(result["craving_score"], errors="coerce")
    result = result.dropna(subset=[participant, timestamp, "craving_score"])
    return result.sort_values([participant, timestamp]).reset_index(drop=True)


def label_window(
    participant_id: str,
    window_end: pd.Timestamp,
    ema_frame: pd.DataFrame,
    config: dict[str, Any],
) -> tuple[int, float | None, pd.Timestamp | None]:
    """Label a sensor window from the nearest subsequent EMA.

    Positive: a high-score EMA occurs within the configured lookback horizon after
    the window end. Negative: no high-score EMA occurs within the larger exclusion
    horizon. Everything between those definitions is ambiguous and can be dropped.
    """
    schema = config["schema"]
    label_cfg = config["labeling"]
    participant = schema["participant_column"]
    timestamp = schema["timestamp_column"]

    subset = ema_frame[ema_frame[participant] == participant_id]
    if subset.empty:
        return AMBIGUOUS_LABEL, None, None

    future = subset[subset[timestamp] >= window_end].copy()
    if future.empty:
        return AMBIGUOUS_LABEL, None, None

    future["seconds_after_window"] = (future[timestamp] - window_end).dt.total_seconds()
    nearest = future.sort_values("seconds_after_window").iloc[0]
    score = float(nearest["craving_score"])
    seconds = float(nearest["seconds_after_window"])
    event_time = nearest[timestamp]

    positive_score = score >= float(label_cfg["positive_score_threshold"])
    if positive_score and seconds <= float(label_cfg["positive_lookback_seconds"]):
        return 1, score, event_time

    high_events = future[
        (future["craving_score"] >= float(label_cfg["positive_score_threshold"]))
        & (future["seconds_after_window"] <= float(label_cfg["negative_exclusion_seconds"]))
    ]
    if high_events.empty:
        return 0, score, event_time

    return AMBIGUOUS_LABEL, score, event_time
