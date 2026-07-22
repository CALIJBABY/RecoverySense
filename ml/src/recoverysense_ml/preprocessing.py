from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd
from scipy.signal import butter, medfilt, sosfiltfilt

from .schema import validate_sensor_frame


def _odd_kernel(samples: int) -> int:
    samples = max(1, int(samples))
    return samples if samples % 2 == 1 else samples + 1


def _safe_lowpass(values: np.ndarray, sampling_rate_hz: float, cutoff_hz: float, order: int) -> np.ndarray:
    finite = np.isfinite(values)
    if finite.sum() < max(15, order * 3):
        return values

    nyquist = sampling_rate_hz / 2.0
    normalized = cutoff_hz / nyquist
    if not 0.0 < normalized < 1.0:
        return values

    filled = pd.Series(values).interpolate(limit_direction="both").to_numpy(float)
    sos = butter(order, normalized, btype="lowpass", output="sos")
    try:
        filtered = sosfiltfilt(sos, filled)
    except ValueError:
        return values
    filtered[~finite] = np.nan
    return filtered


def prepare_sensor_data(frame: pd.DataFrame, config: dict[str, Any]) -> pd.DataFrame:
    """Validate, clean, resample, interpolate short gaps, and filter sensor data.

    The returned frame is uniformly sampled within each participant/session. Long gaps
    create new derived segments so windows never bridge disconnected observations.
    """
    validate_sensor_frame(frame, config)
    schema = config["schema"]
    prep = config["preprocessing"]

    participant = schema["participant_column"]
    session = schema["session_column"]
    timestamp = schema["timestamp_column"]
    hr = schema["heart_rate_column"]
    accel = list(schema["accel_columns"])

    working = frame.copy()
    if session not in working.columns:
        working[session] = "session-0"

    working[timestamp] = pd.to_datetime(working[timestamp], utc=True, errors="coerce", format="mixed")
    for column in [hr, *accel]:
        working[column] = pd.to_numeric(working[column], errors="coerce")

    working = working.dropna(subset=[participant, session, timestamp])
    working = working.sort_values([participant, session, timestamp])
    working = working.drop_duplicates([participant, session, timestamp], keep="last")

    hr_low, hr_high = prep["heart_rate_valid_range"]
    working.loc[~working[hr].between(hr_low, hr_high), hr] = np.nan
    accel_low, accel_high = prep["acceleration_valid_range_g"]
    for column in accel:
        working.loc[~working[column].between(accel_low, accel_high), column] = np.nan

    rate = float(prep["sampling_rate_hz"])
    frequency = pd.to_timedelta(1.0 / rate, unit="s")
    gap_threshold = float(prep["session_break_gap_seconds"])
    interpolation_limit = max(
        1,
        int(round(float(prep["maximum_interpolation_gap_seconds"]) * rate)),
    )
    hr_kernel = _odd_kernel(round(float(prep["heart_rate_median_kernel_seconds"]) * rate))

    processed_groups: list[pd.DataFrame] = []
    for (participant_id, session_id), group in working.groupby([participant, session], sort=False):
        group = group.sort_values(timestamp).copy()
        gap_seconds = group[timestamp].diff().dt.total_seconds().fillna(0.0)
        group["_segment_number"] = (gap_seconds > gap_threshold).cumsum()

        for segment_number, segment in group.groupby("_segment_number", sort=False):
            segment = segment.set_index(timestamp)[[hr, *accel]]
            if len(segment) < 2:
                continue

            full_index = pd.date_range(segment.index.min(), segment.index.max(), freq=frequency)
            segment = segment.reindex(full_index)
            missing_before = segment[[hr, *accel]].isna().mean(axis=1)

            segment[hr] = segment[hr].interpolate(
                method="time", limit=interpolation_limit, limit_direction="both"
            )
            for column in accel:
                segment[column] = segment[column].interpolate(
                    method="time", limit=interpolation_limit, limit_direction="both"
                )

            if segment[hr].notna().sum() >= hr_kernel:
                filled_hr = segment[hr].interpolate(limit_direction="both").to_numpy(float)
                segment[hr] = medfilt(filled_hr, kernel_size=hr_kernel)

            for column in accel:
                segment[column] = _safe_lowpass(
                    segment[column].to_numpy(float),
                    sampling_rate_hz=rate,
                    cutoff_hz=float(prep["accelerometer_lowpass_hz"]),
                    order=int(prep["filter_order"]),
                )

            segment = segment.reset_index(names=timestamp)
            segment[participant] = participant_id
            segment[session] = f"{session_id}-segment-{int(segment_number)}"
            segment["row_missing_fraction_before_fill"] = missing_before.to_numpy(float)
            processed_groups.append(segment)

    if not processed_groups:
        raise ValueError("No usable sensor segments remained after preprocessing.")

    result = pd.concat(processed_groups, ignore_index=True)
    return result[[participant, session, timestamp, hr, *accel, "row_missing_fraction_before_fill"]]
