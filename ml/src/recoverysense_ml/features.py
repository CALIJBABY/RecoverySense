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
    if values.size == 0:
        return {f"{prefix}_{name}": 0.0 for name in ("mean", "std", "min", "max", "range", "median", "iqr", "rms")}
    q25, q75 = np.percentile(values, [25, 75])
    return {
        f"{prefix}_mean": _safe_float(np.mean(values)),
        f"{prefix}_std": _safe_float(np.std(values, ddof=1) if values.size > 1 else 0.0),
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


def _frequency_features(prefix: str, values: np.ndarray, sampling_rate_hz: float) -> dict[str, float]:
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


def extract_window_features(window: pd.DataFrame, config: dict[str, Any]) -> dict[str, float]:
    """Extract deterministic heart-rate and motion features from one window."""
    schema = config["schema"]
    rate = float(config["preprocessing"]["sampling_rate_hz"])
    hr_col = schema["heart_rate_column"]
    ax_col, ay_col, az_col = schema["accel_columns"]

    hr = window[hr_col].to_numpy(float)
    ax = window[ax_col].to_numpy(float)
    ay = window[ay_col].to_numpy(float)
    az = window[az_col].to_numpy(float)
    magnitude = np.sqrt(ax**2 + ay**2 + az**2)
    dynamic_magnitude = magnitude - np.nanmedian(magnitude)
    jerk = np.diff(magnitude, prepend=magnitude[0]) * rate

    features: dict[str, float] = {}
    features.update(_summary("hr", hr))
    features["hr_slope_bpm_per_second"] = _linear_slope(hr, rate)
    hr_diff = np.diff(hr[np.isfinite(hr)])
    features["hr_mean_abs_change"] = _safe_float(np.mean(np.abs(hr_diff))) if hr_diff.size else 0.0
    features["hr_rmssd_bpm"] = _safe_float(np.sqrt(np.mean(hr_diff**2))) if hr_diff.size else 0.0

    for prefix, values in (("accel_x", ax), ("accel_y", ay), ("accel_z", az), ("accel_mag", magnitude), ("dynamic_accel_mag", dynamic_magnitude), ("jerk", jerk)):
        features.update(_summary(prefix, values))

    features.update(_frequency_features("accel_mag", dynamic_magnitude, rate))
    features.update(_frequency_features("jerk", jerk, rate))
    features["signal_magnitude_area"] = _safe_float(np.nanmean(np.abs(ax) + np.abs(ay) + np.abs(az)))
    features["stillness_fraction"] = _safe_float(np.nanmean(np.abs(dynamic_magnitude) < 0.05))
    features["high_motion_fraction"] = _safe_float(np.nanmean(np.abs(dynamic_magnitude) > 0.50))

    for left_name, left, right_name, right in (
        ("x", ax, "y", ay),
        ("x", ax, "z", az),
        ("y", ay, "z", az),
    ):
        valid = np.isfinite(left) & np.isfinite(right)
        if valid.sum() > 2 and np.std(left[valid]) > 1e-12 and np.std(right[valid]) > 1e-12:
            correlation = np.corrcoef(left[valid], right[valid])[0, 1]
        else:
            correlation = 0.0
        features[f"accel_corr_{left_name}{right_name}"] = _safe_float(correlation)

    features["window_missing_fraction"] = _safe_float(
        window[[hr_col, ax_col, ay_col, az_col]].isna().mean().mean()
    )
    if "row_missing_fraction_before_fill" in window:
        features["pre_fill_missing_fraction"] = _safe_float(
            window["row_missing_fraction_before_fill"].mean()
        )
    else:
        features["pre_fill_missing_fraction"] = 0.0
    return features
