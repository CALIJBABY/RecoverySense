from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from .features import extract_window_features
from .labeling import AMBIGUOUS_LABEL, label_window, prepare_ema_data
from .preprocessing import prepare_sensor_data
from .ppg import ppg_features_for_interval, prepare_ppg_data


METADATA_COLUMNS = [
    "participant_id",
    "session_id",
    "window_start",
    "window_end",
    "ema_score",
    "ema_timestamp",
    "label",
]

SLEEP_CONTEXT_FEATURES = [
    "sleep_log_available",
    "sleep_log_stale",
    "sleep_log_age_hours",
    "prior_sleep_duration_minutes",
    "prior_sleep_efficiency",
    "prior_sleep_awakenings",
    "prior_sleep_waso_minutes",
    "prior_sleep_overnight_mean_hr",
    "prior_sleep_overnight_movement_std_g",
    "prior_sleep_estimate_confidence",
    "prior_sleep_quality",
    "prior_rested_score",
    "prior_sleep_watch_removed",
]


def _time_features(
    window_start: pd.Timestamp,
    timezone_offset_minutes: float | int | None,
) -> dict[str, float]:
    """Encode participant-local clock time without treating UTC as local time.

    The offset is metadata available at prediction time, not an outcome. When
    older records do not contain a trustworthy offset, cyclic clock features
    remain missing so the model cannot silently learn a UTC clock as if it were
    the participant's routine.
    """
    offset = pd.to_numeric(timezone_offset_minutes, errors="coerce")
    if pd.isna(offset) or float(offset) < -14 * 60 or float(offset) > 14 * 60:
        return {
            "local_time_context_available": 0.0,
            "time_of_day_sin": np.nan,
            "time_of_day_cos": np.nan,
            "day_of_week_sin": np.nan,
            "day_of_week_cos": np.nan,
        }

    local_start = window_start + pd.Timedelta(minutes=float(offset))
    seconds = (
        local_start.hour * 3600
        + local_start.minute * 60
        + local_start.second
        + local_start.microsecond / 1_000_000
    )
    day_fraction = seconds / 86_400.0
    weekday_fraction = local_start.dayofweek / 7.0
    return {
        "local_time_context_available": 1.0,
        "time_of_day_sin": float(np.sin(2 * np.pi * day_fraction)),
        "time_of_day_cos": float(np.cos(2 * np.pi * day_fraction)),
        "day_of_week_sin": float(np.sin(2 * np.pi * weekday_fraction)),
        "day_of_week_cos": float(np.cos(2 * np.pi * weekday_fraction)),
    }


def _ema_timezone_offset_minutes(
    participant_id: str,
    ema_timestamp: pd.Timestamp | None,
    ema: pd.DataFrame,
    config: dict[str, Any],
) -> float | None:
    if ema_timestamp is None or "timezone_offset_minutes" not in ema.columns:
        return None
    participant_col = config["schema"]["participant_column"]
    timestamp_col = config["schema"]["timestamp_column"]
    matches = ema[
        (ema[participant_col].astype(str) == str(participant_id))
        & (ema[timestamp_col] == ema_timestamp)
    ]
    if matches.empty:
        return None
    value = pd.to_numeric(matches.iloc[0]["timezone_offset_minutes"], errors="coerce")
    return None if pd.isna(value) else float(value)


def _prior_ema_features(
    participant_id: str,
    window_start: pd.Timestamp,
    ema: pd.DataFrame,
    config: dict[str, Any],
) -> dict[str, float]:
    schema = config["schema"]
    participant_col = schema["participant_column"]
    timestamp_col = schema["timestamp_column"]
    prior = ema[
        (ema[participant_col].astype(str) == str(participant_id))
        & (ema[timestamp_col] < window_start)
    ].sort_values(timestamp_col)

    result = {
        "time_since_previous_ema_seconds": np.nan,
        "previous_ema_score": np.nan,
        "previous_stress_score": np.nan,
        "previous_mood_score": np.nan,
        "previous_anxiety_score": np.nan,
        "previous_boredom_score": np.nan,
        "ema_count_previous_24h": 0.0,
        "ema_mean_previous_24h": np.nan,
        "ema_max_previous_24h": np.nan,
    }
    if prior.empty:
        return result

    last = prior.iloc[-1]
    result["time_since_previous_ema_seconds"] = float(
        (window_start - last[timestamp_col]).total_seconds()
    )
    result["previous_ema_score"] = float(last["craving_score"])
    for source_column, feature_name in (
        ("stress_score", "previous_stress_score"),
        ("mood_score", "previous_mood_score"),
        ("anxiety_score", "previous_anxiety_score"),
        ("boredom_score", "previous_boredom_score"),
    ):
        if source_column in prior.columns:
            numeric = pd.to_numeric(last[source_column], errors="coerce")
            if pd.notna(numeric):
                result[feature_name] = float(numeric)

    recent = prior[prior[timestamp_col] >= window_start - pd.Timedelta(hours=24)]
    recent_scores = pd.to_numeric(recent["craving_score"], errors="coerce").dropna()
    result["ema_count_previous_24h"] = float(len(recent_scores))
    if not recent_scores.empty:
        result["ema_mean_previous_24h"] = float(recent_scores.mean())
        result["ema_max_previous_24h"] = float(recent_scores.max())
    return result


def prepare_sleep_context(frame: pd.DataFrame | None) -> pd.DataFrame:
    """Normalize confirmed nightly sleep records used by the craving model.

    Sleep is treated as context from the latest completed night only. The model
    never receives a sleep record whose wake time is after the sensor window.
    """
    if frame is None or frame.empty:
        return pd.DataFrame()
    result = frame.copy()
    if "participant_id" not in result.columns:
        return pd.DataFrame()

    for column in (
        "reported_wake",
        "predicted_wake",
        "recording_end",
        "reported_sleep_onset",
        "predicted_sleep_onset",
        "recording_start",
    ):
        if column in result.columns:
            result[column] = pd.to_datetime(
                result[column], utc=True, errors="coerce", format="mixed"
            )

    wake_candidates = [
        column
        for column in ("reported_wake", "predicted_wake", "recording_end")
        if column in result.columns
    ]
    if not wake_candidates:
        return pd.DataFrame()
    result["_effective_wake"] = result[wake_candidates].bfill(axis=1).iloc[:, 0]

    if "status" in result.columns:
        status = result["status"].fillna("").astype(str).str.lower()
        result = result[status.isin({"confirmed", "complete", "completed"})]

    result = result.dropna(subset=["participant_id", "_effective_wake"])
    return result.sort_values(["participant_id", "_effective_wake"]).reset_index(
        drop=True
    )


def _empty_sleep_features() -> dict[str, float]:
    return {
        "sleep_log_available": 0.0,
        "sleep_log_stale": 0.0,
        "sleep_log_age_hours": np.nan,
        "prior_sleep_duration_minutes": np.nan,
        "prior_sleep_efficiency": np.nan,
        "prior_sleep_awakenings": np.nan,
        "prior_sleep_waso_minutes": np.nan,
        "prior_sleep_overnight_mean_hr": np.nan,
        "prior_sleep_overnight_movement_std_g": np.nan,
        "prior_sleep_estimate_confidence": np.nan,
        "prior_sleep_quality": np.nan,
        "prior_rested_score": np.nan,
        "prior_sleep_watch_removed": np.nan,
    }


def _first_numeric(row: pd.Series, names: tuple[str, ...]) -> float:
    for name in names:
        if name not in row.index:
            continue
        value = pd.to_numeric(row[name], errors="coerce")
        if pd.notna(value):
            return float(value)
    return np.nan


def _prior_sleep_features(
    participant_id: str,
    window_start: pd.Timestamp,
    sleep: pd.DataFrame,
    config: dict[str, Any],
) -> dict[str, float]:
    """Return only the latest eligible completed sleep record.

    Rules established for RecoverySense:
    - the wake time must be before the current sensor window;
    - <=36 hours is preferred/current;
    - 36-48 hours is retained but flagged stale;
    - >48 hours is excluded;
    - missing sleep is represented with availability flags and NaN, never zero.
    """
    result = _empty_sleep_features()
    if sleep.empty:
        return result

    prior = sleep[
        (sleep["participant_id"].astype(str) == str(participant_id))
        & (sleep["_effective_wake"] <= window_start)
    ]
    if prior.empty:
        return result

    latest = prior.sort_values("_effective_wake").iloc[-1]
    age_hours = float(
        (window_start - latest["_effective_wake"]).total_seconds() / 3600.0
    )
    sleep_cfg = config.get("sleep_context", {})
    preferred = float(sleep_cfg.get("preferred_max_age_hours", 36.0))
    maximum = float(sleep_cfg.get("stale_max_age_hours", 48.0))
    if age_hours < 0 or age_hours > maximum:
        return result

    result.update(
        {
            "sleep_log_available": 1.0,
            "sleep_log_stale": float(age_hours > preferred),
            "sleep_log_age_hours": age_hours,
            "prior_sleep_duration_minutes": _first_numeric(
                latest,
                ("estimated_total_sleep_minutes", "reported_sleep_duration_minutes"),
            ),
            "prior_sleep_efficiency": _first_numeric(
                latest, ("estimated_sleep_efficiency", "sleep_efficiency")
            ),
            "prior_sleep_awakenings": _first_numeric(
                latest, ("reported_awakenings", "estimated_awakenings")
            ),
            "prior_sleep_waso_minutes": _first_numeric(
                latest, ("estimated_waso_minutes", "waso_minutes")
            ),
            "prior_sleep_overnight_mean_hr": _first_numeric(
                latest, ("overnight_mean_hr",)
            ),
            "prior_sleep_overnight_movement_std_g": _first_numeric(
                latest, ("overnight_movement_std_g", "overnight_movement")
            ),
            "prior_sleep_estimate_confidence": _first_numeric(
                latest, ("sleep_estimate_confidence", "confidence")
            ),
            "prior_sleep_quality": _first_numeric(latest, ("sleep_quality",)),
            "prior_rested_score": _first_numeric(latest, ("rested_score",)),
            "prior_sleep_watch_removed": _first_numeric(latest, ("watch_removed",)),
        }
    )
    return result


def build_window_dataset(
    sensor_frame: pd.DataFrame,
    ema_frame: pd.DataFrame,
    config: dict[str, Any],
    sleep_frame: pd.DataFrame | None = None,
    ppg_frame: pd.DataFrame | None = None,
) -> pd.DataFrame:
    processed = prepare_sensor_data(sensor_frame, config)
    ema = prepare_ema_data(ema_frame, config)
    sleep = prepare_sleep_context(sleep_frame)
    ppg = prepare_ppg_data(ppg_frame)

    schema = config["schema"]
    window_cfg = config["windowing"]
    participant_col = schema["participant_column"]
    session_col = schema["session_column"]
    timestamp_col = schema["timestamp_column"]

    rate = float(config["preprocessing"]["sampling_rate_hz"])
    window_samples = int(round(float(window_cfg["window_seconds"]) * rate))
    stride_samples = int(round(float(window_cfg["stride_seconds"]) * rate))
    minimum_samples = int(
        round(window_samples * float(window_cfg["minimum_window_coverage"]))
    )
    maximum_missing = float(window_cfg["maximum_missing_fraction"])

    rows: list[dict[str, Any]] = []
    for (participant_id, session_id), group in processed.groupby(
        [participant_col, session_col], sort=False
    ):
        group = group.sort_values(timestamp_col).reset_index(drop=True)
        if len(group) < minimum_samples:
            continue
        session_start = group[timestamp_col].iloc[0]

        for start in range(0, max(1, len(group) - minimum_samples + 1), stride_samples):
            end = start + window_samples
            window = group.iloc[start:end]
            if len(window) < minimum_samples:
                continue

            observed_missing = float(window["row_missing_fraction_before_fill"].mean())
            if observed_missing > maximum_missing:
                continue

            window_start = window[timestamp_col].iloc[0]
            window_end = window[timestamp_col].iloc[-1]
            label, ema_score, ema_timestamp = label_window(
                str(participant_id), window_end, ema, config
            )
            if label == AMBIGUOUS_LABEL and config["labeling"]["drop_ambiguous_windows"]:
                continue

            features = extract_window_features(window, config)
            features.update(
                _time_features(
                    window_start,
                    _ema_timezone_offset_minutes(
                        str(participant_id), ema_timestamp, ema, config
                    ),
                )
            )
            features.update(
                _prior_ema_features(str(participant_id), window_start, ema, config)
            )
            features.update(
                _prior_sleep_features(str(participant_id), window_start, sleep, config)
            )
            features.update(
                ppg_features_for_interval(
                    ppg,
                    str(participant_id),
                    window_start,
                    window_end,
                    session_id=str(session_id),
                    nominal_sampling_rate_hz=float(
                        config.get("ppg", {}).get("sampling_rate_hz", 25.0)
                    ),
                )
            )
            features["window_coverage"] = float(len(window) / window_samples)
            features["session_elapsed_minutes"] = float(
                (window_start - session_start).total_seconds() / 60.0
            )

            rows.append(
                {
                    participant_col: participant_id,
                    session_col: session_id,
                    "window_start": window_start,
                    "window_end": window_end,
                    "ema_score": np.nan if ema_score is None else ema_score,
                    "ema_timestamp": ema_timestamp,
                    "label": label,
                    **features,
                }
            )

    if not rows:
        raise ValueError(
            "No labeled windows were produced. Check timestamps, EMA events, and labeling horizons."
        )

    result = pd.DataFrame(rows)
    if result["label"].nunique() < 2:
        raise ValueError("The window dataset must contain both positive and negative labels.")
    return result


def build_dataset_from_config(config: dict[str, Any]) -> pd.DataFrame:
    sensor_path = Path(config["paths"]["raw_sensor_csv"])
    ema_path = Path(config["paths"]["ema_csv"])
    sleep_path = Path(
        config["paths"].get("sleep_sessions_csv", "ml/data/raw/sleep_sessions.csv")
    )
    if not sensor_path.exists():
        raise FileNotFoundError(f"Missing sensor data: {sensor_path}")
    if not ema_path.exists():
        raise FileNotFoundError(f"Missing EMA data: {ema_path}")

    sleep_frame = pd.read_csv(sleep_path) if sleep_path.exists() else None
    ppg_path = Path(config["paths"].get("raw_ppg_csv", "ml/data/raw/raw_ppg.csv"))
    ppg_frame = pd.read_csv(ppg_path, low_memory=False) if ppg_path.exists() else None
    dataset = build_window_dataset(
        pd.read_csv(sensor_path, low_memory=False),
        pd.read_csv(ema_path),
        config,
        sleep_frame=sleep_frame,
        ppg_frame=ppg_frame,
    )
    output_path = Path(config["paths"]["processed_windows_csv"])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    dataset.to_csv(output_path, index=False)
    return dataset
