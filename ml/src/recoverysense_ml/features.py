from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd
from scipy.stats import entropy


def _safe_float(value: float | np.floating) -> float:
    value = float(value)
    return value if np.isfinite(value) else 0.0


def _summary(prefix: str, values: np.ndarray) -> dict[str, float]:
    values = values[np.isfinite(values)]
    names = ("mean", "std", "min", "max", "range", "median", "iqr", "rms")
    if values.size == 0:
        return {f"{prefix}_{name}": 0.0 for name in names}
    q25, q75 = np.percentile(values, [25, 75])
    return {
        f"{prefix}_mean": _safe_float(np.mean(values)),
        f"{prefix}_std": _safe_float(
            np.std(values, ddof=1) if values.size > 1 else 0.0
        ),
        f"{prefix}_min": _safe_float(np.min(values)),
        f"{prefix}_max": _safe_float(np.max(values)),
        f"{prefix}_range": _safe_float(np.ptp(values)),
        f"{prefix}_median": _safe_float(np.median(values)),
        f"{prefix}_iqr": _safe_float(q75 - q25),
        f"{prefix}_rms": _safe_float(np.sqrt(np.mean(np.square(values)))),
    }


def _linear_slope(values: np.ndarray, sampling_rate_hz: float) -> float:
    finite = np.isfinite(values)
    if finite.sum() < 2:
        return 0.0
    x = np.arange(values.size, dtype=float)[finite] / sampling_rate_hz
    y = values[finite]
    return _safe_float(np.polyfit(x, y, deg=1)[0])


def _frequency_features(
    prefix: str,
    values: np.ndarray,
    sampling_rate_hz: float,
) -> dict[str, float]:
    values = values[np.isfinite(values)]
    if values.size < 8:
        return {
            f"{prefix}_spectral_energy": 0.0,
            f"{prefix}_dominant_frequency_hz": 0.0,
            f"{prefix}_spectral_entropy": 0.0,
        }

    centered = values - np.mean(values)
    spectrum = np.abs(np.fft.rfft(centered)) ** 2
    frequencies = np.fft.rfftfreq(values.size, d=1.0 / sampling_rate_hz)
    if spectrum.size <= 1 or np.sum(spectrum) <= 0:
        return {
            f"{prefix}_spectral_energy": 0.0,
            f"{prefix}_dominant_frequency_hz": 0.0,
            f"{prefix}_spectral_entropy": 0.0,
        }

    spectrum[0] = 0.0
    total = np.sum(spectrum)
    probabilities = spectrum / total if total > 0 else np.zeros_like(spectrum)
    dominant = frequencies[int(np.argmax(spectrum))]
    normalized_entropy = entropy(probabilities + 1e-12) / np.log(probabilities.size)
    return {
        f"{prefix}_spectral_energy": _safe_float(total / values.size),
        f"{prefix}_dominant_frequency_hz": _safe_float(dominant),
        f"{prefix}_spectral_entropy": _safe_float(normalized_entropy),
    }


def _correlation(left: np.ndarray, right: np.ndarray) -> float:
    valid = np.isfinite(left) & np.isfinite(right)
    if (
        valid.sum() > 2
        and np.std(left[valid]) > 1e-12
        and np.std(right[valid]) > 1e-12
    ):
        return _safe_float(np.corrcoef(left[valid], right[valid])[0, 1])
    return 0.0


def _column_values(window: pd.DataFrame, column: str) -> np.ndarray:
    if column not in window:
        return np.full(len(window), np.nan, dtype=float)
    return pd.to_numeric(window[column], errors="coerce").to_numpy(float)


def extract_window_features(window: pd.DataFrame, config: dict[str, Any]) -> dict[str, float]:
    """Extract heart-rate, motion, interaction, context, and quality features."""
    schema = config["schema"]
    rate = float(config["preprocessing"]["sampling_rate_hz"])
    hr_col = schema["heart_rate_column"]
    ax_col, ay_col, az_col = schema["accel_columns"]
    gx_col, gy_col, gz_col = schema.get(
        "gyro_columns", ["gyro_x", "gyro_y", "gyro_z"]
    )
    step_count_col = schema.get("step_count_column", "step_count")
    step_detected_col = schema.get("step_detected_column", "step_detected")
    hr_accuracy_col = schema.get("heart_rate_accuracy_column", "heart_rate_accuracy")
    accel_accuracy_col = schema.get(
        "accelerometer_accuracy_column", "accelerometer_accuracy"
    )
    gyro_accuracy_col = schema.get("gyroscope_accuracy_column", "gyroscope_accuracy")
    off_body_col = schema.get("off_body_column", "off_body")
    heart_rate_age_col = schema.get("heart_rate_age_column", "heart_rate_age_ms")
    screen_interactive_col = schema.get("screen_interactive_column", "screen_interactive")

    hr = _column_values(window, hr_col)
    ax = _column_values(window, ax_col)
    ay = _column_values(window, ay_col)
    az = _column_values(window, az_col)
    gx = _column_values(window, gx_col)
    gy = _column_values(window, gy_col)
    gz = _column_values(window, gz_col)

    magnitude = np.sqrt(ax**2 + ay**2 + az**2)
    dynamic_magnitude = magnitude - np.nanmedian(magnitude)
    jerk = np.diff(magnitude, prepend=magnitude[0]) * rate
    gyro_magnitude = np.sqrt(gx**2 + gy**2 + gz**2)
    rotational_jerk = np.diff(gyro_magnitude, prepend=gyro_magnitude[0]) * rate

    features: dict[str, float] = {}
    features.update(_summary("hr", hr))
    features["hr_slope_bpm_per_second"] = _linear_slope(hr, rate)
    hr_diff = np.diff(hr[np.isfinite(hr)])
    features["hr_mean_abs_change"] = (
        _safe_float(np.mean(np.abs(hr_diff))) if hr_diff.size else 0.0
    )
    features["hr_rmssd_bpm"] = (
        _safe_float(np.sqrt(np.mean(hr_diff**2))) if hr_diff.size else 0.0
    )

    for prefix, values in (
        ("accel_x", ax),
        ("accel_y", ay),
        ("accel_z", az),
        ("accel_mag", magnitude),
        ("dynamic_accel_mag", dynamic_magnitude),
        ("jerk", jerk),
        ("gyro_x", gx),
        ("gyro_y", gy),
        ("gyro_z", gz),
        ("gyro_mag", gyro_magnitude),
        ("rotational_jerk", rotational_jerk),
    ):
        features.update(_summary(prefix, values))

    features.update(_frequency_features("accel_mag", dynamic_magnitude, rate))
    features.update(_frequency_features("jerk", jerk, rate))
    features.update(_frequency_features("gyro_mag", gyro_magnitude, rate))
    features["signal_magnitude_area"] = _safe_float(
        np.nanmean(np.abs(ax) + np.abs(ay) + np.abs(az))
    )
    features["stillness_fraction"] = _safe_float(
        np.nanmean(np.abs(dynamic_magnitude) < 0.05)
    )
    features["high_motion_fraction"] = _safe_float(
        np.nanmean(np.abs(dynamic_magnitude) > 0.50)
    )
    features["still_wrist_fraction"] = _safe_float(
        np.nanmean(np.abs(gyro_magnitude) < 0.10)
    )

    features["accel_corr_xy"] = _correlation(ax, ay)
    features["accel_corr_xz"] = _correlation(ax, az)
    features["accel_corr_yz"] = _correlation(ay, az)
    features["gyro_corr_xy"] = _correlation(gx, gy)
    features["gyro_corr_xz"] = _correlation(gx, gz)
    features["gyro_corr_yz"] = _correlation(gy, gz)
    features["accel_gyro_magnitude_correlation"] = _correlation(
        dynamic_magnitude, gyro_magnitude
    )
    features["hr_accel_magnitude_correlation"] = _correlation(hr, dynamic_magnitude)

    baseline = _column_values(window, "hr_baseline_bpm")
    valid_baseline = baseline[np.isfinite(baseline)]
    baseline_bpm = float(np.median(valid_baseline)) if valid_baseline.size else np.nan
    hr_mean = features["hr_mean"]
    baseline_delta = hr_mean - baseline_bpm if np.isfinite(baseline_bpm) else 0.0
    features["hr_baseline_bpm"] = _safe_float(baseline_bpm)
    features["hr_baseline_delta_bpm"] = _safe_float(baseline_delta)
    features["hr_baseline_ratio"] = (
        _safe_float(hr_mean / baseline_bpm) if baseline_bpm > 0 else 0.0
    )
    positive_activation = max(0.0, baseline_delta)
    features["hr_activation_while_still"] = _safe_float(
        positive_activation * features["stillness_fraction"]
    )
    features["hr_activation_to_motion_ratio"] = _safe_float(
        positive_activation / (features["dynamic_accel_mag_rms"] + 1e-6)
    )

    step_count = _column_values(window, step_count_col)
    valid_steps = step_count[np.isfinite(step_count)]
    step_delta = max(0.0, float(valid_steps[-1] - valid_steps[0])) if valid_steps.size > 1 else 0.0
    step_events = _column_values(window, step_detected_col)
    step_event_count = float(np.nansum(np.clip(step_events, 0, None)))
    duration_minutes = max(len(window) / rate / 60.0, 1e-6)
    features["step_count_delta"] = _safe_float(step_delta)
    features["step_event_count"] = _safe_float(step_event_count)
    features["step_cadence_per_minute"] = _safe_float(
        max(step_delta, step_event_count) / duration_minutes
    )

    core = window[[hr_col, ax_col, ay_col, az_col]]
    features["window_missing_fraction"] = _safe_float(core.isna().mean().mean())
    features["heart_rate_valid_fraction"] = _safe_float(np.mean(np.isfinite(hr)))
    features["accelerometer_valid_fraction"] = _safe_float(
        np.mean(np.isfinite(ax) & np.isfinite(ay) & np.isfinite(az))
    )
    features["gyroscope_valid_fraction"] = _safe_float(
        np.mean(np.isfinite(gx) & np.isfinite(gy) & np.isfinite(gz))
    )

    for feature_name, column in (
        ("heart_rate_accuracy_mean", hr_accuracy_col),
        ("accelerometer_accuracy_mean", accel_accuracy_col),
        ("gyroscope_accuracy_mean", gyro_accuracy_col),
    ):
        accuracy_values = _column_values(window, column)
        finite_accuracy = accuracy_values[np.isfinite(accuracy_values)]
        features[feature_name] = (
            _safe_float(np.mean(finite_accuracy)) if finite_accuracy.size else 0.0
        )

    heart_rate_age = _column_values(window, heart_rate_age_col)
    valid_hr_age = heart_rate_age[np.isfinite(heart_rate_age) & (heart_rate_age >= 0)]
    features["heart_rate_age_ms_mean"] = (
        _safe_float(np.mean(valid_hr_age)) if valid_hr_age.size else 0.0
    )
    features["heart_rate_stale_fraction"] = (
        _safe_float(np.mean(valid_hr_age > 90_000.0)) if valid_hr_age.size else 0.0
    )

    screen_interactive = _column_values(window, screen_interactive_col)
    known_screen = screen_interactive[np.isfinite(screen_interactive)]
    features["screen_off_fraction"] = (
        _safe_float(np.mean(known_screen < 0.5)) if known_screen.size else 0.0
    )

    off_body = _column_values(window, off_body_col)
    known_off_body = off_body[np.isfinite(off_body)]
    features["off_body_fraction"] = (
        _safe_float(np.mean(known_off_body > 0.5)) if known_off_body.size else 0.0
    )

    if "row_missing_fraction_before_fill" in window:
        features["pre_fill_missing_fraction"] = _safe_float(
            window["row_missing_fraction_before_fill"].mean()
        )
    else:
        features["pre_fill_missing_fraction"] = 0.0
    return features
