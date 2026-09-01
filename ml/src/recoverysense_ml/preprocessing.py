from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd
from scipy.signal import butter, sosfiltfilt

from .schema import validate_sensor_frame


def _odd_kernel(samples: int) -> int:
    samples = max(1, int(samples))
    return samples if samples % 2 == 1 else samples + 1


def _safe_lowpass(
    values: np.ndarray,
    sampling_rate_hz: float,
    cutoff_hz: float,
    order: int,
) -> np.ndarray:
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


def _optional_column(schema: dict[str, Any], key: str, fallback: str) -> str:
    return str(schema.get(key, fallback))


def prepare_sensor_data(frame: pd.DataFrame, config: dict[str, Any]) -> pd.DataFrame:
    """Clean, uniformly resample, gap-limit, and filter sensor measurements.

    Firestore/CSV values remain raw. This function creates an analysis copy,
    applies a median smoother to heart rate, and applies zero-phase Butterworth
    low-pass filtering to accelerometer and gyroscope axes.
    """
    validate_sensor_frame(frame, config)
    schema = config["schema"]
    prep = config["preprocessing"]

    participant = schema["participant_column"]
    session = schema["session_column"]
    timestamp = schema["timestamp_column"]
    hr = schema["heart_rate_column"]
    accel = list(schema["accel_columns"])
    gyro = list(schema.get("gyro_columns", ["gyro_x", "gyro_y", "gyro_z"]))
    step_count = _optional_column(schema, "step_count_column", "step_count")
    step_detected = _optional_column(schema, "step_detected_column", "step_detected")
    hr_accuracy = _optional_column(
        schema, "heart_rate_accuracy_column", "heart_rate_accuracy"
    )
    accel_accuracy = _optional_column(
        schema, "accelerometer_accuracy_column", "accelerometer_accuracy"
    )
    gyro_accuracy = _optional_column(
        schema, "gyroscope_accuracy_column", "gyroscope_accuracy"
    )
    off_body = _optional_column(schema, "off_body_column", "off_body")

    optional_numeric = [
        *gyro,
        step_count,
        step_detected,
        hr_accuracy,
        accel_accuracy,
        gyro_accuracy,
        off_body,
    ]

    working = frame.copy()
    if session not in working.columns:
        working[session] = "session-0"
    for column in optional_numeric:
        if column not in working.columns:
            working[column] = np.nan

    working[timestamp] = pd.to_datetime(
        working[timestamp], utc=True, errors="coerce", format="mixed"
    )
    for column in [hr, *accel, *optional_numeric]:
        working[column] = pd.to_numeric(working[column], errors="coerce")

    working = working.dropna(subset=[participant, session, timestamp])
    working = working.sort_values([participant, session, timestamp])
    working = working.drop_duplicates([participant, session, timestamp], keep="last")

    hr_low, hr_high = prep["heart_rate_valid_range"]
    working.loc[~working[hr].between(hr_low, hr_high), hr] = np.nan

    accel_low, accel_high = prep["acceleration_valid_range_g"]
    for column in accel:
        working.loc[~working[column].between(accel_low, accel_high), column] = np.nan

    gyro_low, gyro_high = prep.get("gyroscope_valid_range_rad_s", [-50.0, 50.0])
    for column in gyro:
        working.loc[~working[column].between(gyro_low, gyro_high), column] = np.nan

    rate = float(prep["sampling_rate_hz"])
    frequency = pd.to_timedelta(1.0 / rate, unit="s")
    gap_threshold = float(prep["session_break_gap_seconds"])
    interpolation_limit = max(
        1,
        int(round(float(prep["maximum_interpolation_gap_seconds"]) * rate)),
    )
    hr_kernel = _odd_kernel(
        round(float(prep["heart_rate_median_kernel_seconds"]) * rate)
    )
    baseline_samples = max(
        1,
        int(round(float(prep.get("baseline_window_seconds", 300.0)) * rate)),
    )
    baseline_minimum = max(
        1,
        int(round(float(prep.get("baseline_minimum_seconds", 60.0)) * rate)),
    )

    core_columns = [hr, *accel]
    continuous_columns = [hr, *accel, *gyro]
    quality_columns = [hr_accuracy, accel_accuracy, gyro_accuracy, off_body]

    processed_groups: list[pd.DataFrame] = []
    for (participant_id, session_id), group in working.groupby(
        [participant, session], sort=False
    ):
        group = group.sort_values(timestamp).copy()
        gap_seconds = group[timestamp].diff().dt.total_seconds().fillna(0.0)
        group["_segment_number"] = (gap_seconds > gap_threshold).cumsum()

        for segment_number, raw_segment in group.groupby("_segment_number", sort=False):
            if len(raw_segment) < 2:
                continue

            raw_segment = raw_segment.set_index(timestamp)
            aggregations: dict[str, str] = {
                **{column: "mean" for column in continuous_columns},
                step_count: "last",
                step_detected: "sum",
                hr_accuracy: "mean",
                accel_accuracy: "mean",
                gyro_accuracy: "mean",
                off_body: "last",
            }
            segment = raw_segment.resample(frequency, origin="start").agg(aggregations)
            if len(segment) < 2:
                continue

            missing_before = segment[core_columns].isna().mean(axis=1)

            segment[hr] = segment[hr].interpolate(
                method="time",
                limit=interpolation_limit,
                limit_direction="both",
            )
            for column in [*accel, *gyro]:
                segment[column] = segment[column].interpolate(
                    method="time",
                    limit=interpolation_limit,
                    limit_direction="both",
                )

            segment[step_count] = segment[step_count].ffill(limit=interpolation_limit)
            segment[step_detected] = segment[step_detected].fillna(0.0)
            for column in quality_columns:
                segment[column] = segment[column].ffill(limit=interpolation_limit)

            if segment[hr].notna().sum() >= hr_kernel:
                segment[hr] = segment[hr].rolling(
                    window=hr_kernel,
                    center=True,
                    min_periods=1,
                ).median()

            for column in accel:
                segment[column] = _safe_lowpass(
                    segment[column].to_numpy(float),
                    sampling_rate_hz=rate,
                    cutoff_hz=float(prep["accelerometer_lowpass_hz"]),
                    order=int(prep["filter_order"]),
                )
            for column in gyro:
                segment[column] = _safe_lowpass(
                    segment[column].to_numpy(float),
                    sampling_rate_hz=rate,
                    cutoff_hz=float(prep.get("gyroscope_lowpass_hz", 4.0)),
                    order=int(prep["filter_order"]),
                )

            segment["hr_baseline_bpm"] = (
                segment[hr]
                .shift(1)
                .rolling(
                    window=baseline_samples,
                    min_periods=min(baseline_minimum, baseline_samples),
                )
                .median()
            )

            segment = segment.reset_index(names=timestamp)
            segment[participant] = participant_id
            segment[session] = f"{session_id}-segment-{int(segment_number)}"
            segment["row_missing_fraction_before_fill"] = missing_before.to_numpy(float)
            processed_groups.append(segment)

    if not processed_groups:
        raise ValueError("No usable sensor segments remained after preprocessing.")

    result = pd.concat(processed_groups, ignore_index=True)
    columns = [
        participant,
        session,
        timestamp,
        hr,
        *accel,
        *gyro,
        step_count,
        step_detected,
        hr_accuracy,
        accel_accuracy,
        gyro_accuracy,
        off_body,
        "hr_baseline_bpm",
        "row_missing_fraction_before_fill",
    ]
    return result[columns]
