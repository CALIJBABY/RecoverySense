from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd
from scipy.signal import butter, detrend, find_peaks, sosfiltfilt, welch

PPG_FEATURE_NAMES = [
    "ppg_available",
    "ppg_sample_count",
    "ppg_duration_seconds",
    "ppg_observed_sampling_rate_hz",
    "ppg_timestamp_gap_fraction",
    "ppg_green_valid_fraction",
    "ppg_infrared_valid_fraction",
    "ppg_red_valid_fraction",
    "ppg_all_channels_valid_fraction",
    "ppg_green_mean",
    "ppg_green_std",
    "ppg_infrared_mean",
    "ppg_infrared_std",
    "ppg_red_mean",
    "ppg_red_std",
    "ppg_green_perfusion_index_proxy",
    "ppg_infrared_perfusion_index_proxy",
    "ppg_red_perfusion_index_proxy",
    "ppg_green_red_correlation",
    "ppg_green_infrared_correlation",
    "ppg_selected_channel_code",
    "ppg_selected_valid_fraction",
    "ppg_selected_snr_proxy_db",
    "ppg_selected_clipping_fraction",
    "ppg_peak_count",
    "ppg_pulse_rate_bpm",
    "ppg_prv_mean_nn_ms",
    "ppg_prv_sdnn_ms",
    "ppg_prv_rmssd_ms",
    "ppg_prv_pnn50",
    "ppg_prv_valid_interval_count",
]


def empty_ppg_features() -> dict[str, float]:
    result = {name: np.nan for name in PPG_FEATURE_NAMES}
    result.update(
        {
            "ppg_available": 0.0,
            "ppg_sample_count": 0.0,
            "ppg_duration_seconds": 0.0,
            "ppg_timestamp_gap_fraction": 1.0,
            "ppg_green_valid_fraction": 0.0,
            "ppg_infrared_valid_fraction": 0.0,
            "ppg_red_valid_fraction": 0.0,
            "ppg_all_channels_valid_fraction": 0.0,
            "ppg_selected_valid_fraction": 0.0,
            "ppg_selected_clipping_fraction": 1.0,
            "ppg_peak_count": 0.0,
            "ppg_prv_valid_interval_count": 0.0,
        }
    )
    return result


def prepare_ppg_data(frame: pd.DataFrame | None) -> pd.DataFrame:
    """Normalize raw Samsung PPG samples without discarding original status codes."""
    if frame is None or frame.empty:
        return pd.DataFrame()
    result = frame.copy()
    aliases = {
        "green": "green_adc",
        "infrared": "infrared_adc",
        "ir": "infrared_adc",
        "red": "red_adc",
    }
    for source, target in aliases.items():
        if target not in result.columns and source in result.columns:
            result[target] = result[source]
    required = {"participant_id", "session_id", "timestamp", "green_adc"}
    missing = required.difference(result.columns)
    if missing:
        raise ValueError("Raw PPG data is missing columns: " + ", ".join(sorted(missing)))

    result["participant_id"] = result["participant_id"].astype(str)
    result["session_id"] = result["session_id"].astype(str)
    result["timestamp"] = pd.to_datetime(
        result["timestamp"], utc=True, errors="coerce", format="mixed"
    )
    for column in (
        "green_adc",
        "infrared_adc",
        "red_adc",
        "green_status",
        "infrared_status",
        "red_status",
        "sampling_rate_hz",
    ):
        if column not in result.columns:
            result[column] = np.nan
        result[column] = pd.to_numeric(result[column], errors="coerce")

    # Int.MIN_VALUE is the app-side sentinel for a missing SDK value.
    for column in ("green_adc", "infrared_adc", "red_adc"):
        result.loc[result[column] <= -2_147_483_648, column] = np.nan

    return (
        result.dropna(subset=["timestamp"])
        .sort_values(["participant_id", "session_id", "timestamp"])
        .drop_duplicates(["participant_id", "session_id", "timestamp"], keep="last")
        .reset_index(drop=True)
    )


def _safe_mean(values: np.ndarray) -> float:
    finite = values[np.isfinite(values)]
    return float(np.mean(finite)) if finite.size else np.nan


def _safe_std(values: np.ndarray) -> float:
    finite = values[np.isfinite(values)]
    return float(np.std(finite, ddof=1)) if finite.size > 1 else 0.0 if finite.size else np.nan


def _valid_fraction(values: np.ndarray) -> float:
    return float(np.mean(np.isfinite(values))) if values.size else 0.0


def _correlation(left: np.ndarray, right: np.ndarray) -> float:
    valid = np.isfinite(left) & np.isfinite(right)
    if valid.sum() < 4 or np.std(left[valid]) <= 1e-12 or np.std(right[valid]) <= 1e-12:
        return np.nan
    return float(np.corrcoef(left[valid], right[valid])[0, 1])


def _perfusion_index_proxy(values: np.ndarray) -> float:
    finite = values[np.isfinite(values)]
    if finite.size < 4:
        return np.nan
    dc = abs(float(np.mean(finite)))
    return float(100.0 * np.std(finite) / dc) if dc > 1e-9 else np.nan


def _interpolate(values: np.ndarray) -> np.ndarray:
    series = pd.Series(values, dtype=float)
    return series.interpolate(limit_direction="both", limit_area="inside").to_numpy(float)


def _filtered_signal(values: np.ndarray, sampling_rate_hz: float) -> np.ndarray | None:
    finite_fraction = _valid_fraction(values)
    if finite_fraction < 0.70 or values.size < max(25, int(sampling_rate_hz * 4)):
        return None
    filled = _interpolate(values)
    if not np.all(np.isfinite(filled)):
        return None
    centered = detrend(filled, type="linear")
    high = min(5.0, sampling_rate_hz * 0.45)
    if sampling_rate_hz <= 2.2 or high <= 0.55:
        return centered
    sos = butter(3, [0.5, high], btype="bandpass", fs=sampling_rate_hz, output="sos")
    try:
        return sosfiltfilt(sos, centered)
    except ValueError:
        return centered


def _snr_proxy_db(signal: np.ndarray, sampling_rate_hz: float) -> float:
    if signal.size < max(32, int(sampling_rate_hz * 4)):
        return np.nan
    frequencies, power = welch(signal, fs=sampling_rate_hz, nperseg=min(signal.size, 256))
    pulse_band = (frequencies >= 0.6) & (frequencies <= 3.5)
    noise_band = ((frequencies >= 0.1) & (frequencies < 0.5)) | (
        (frequencies > 5.0) & (frequencies <= sampling_rate_hz / 2)
    )
    signal_power = float(np.trapezoid(power[pulse_band], frequencies[pulse_band])) if pulse_band.any() else 0.0
    noise_power = float(np.trapezoid(power[noise_band], frequencies[noise_band])) if noise_band.any() else 0.0
    if signal_power <= 0 or noise_power <= 0:
        return np.nan
    return float(10.0 * np.log10(signal_power / noise_power))


def _clipping_fraction(values: np.ndarray) -> float:
    finite = values[np.isfinite(values)]
    if finite.size < 4:
        return 1.0
    low, high = np.percentile(finite, [0.5, 99.5])
    if high <= low:
        return 1.0
    tolerance = max((high - low) * 1e-4, 1.0)
    return float(np.mean((finite <= low + tolerance) | (finite >= high - tolerance)))


def _pulse_features(filtered: np.ndarray | None, sampling_rate_hz: float) -> dict[str, float]:
    result = {
        "ppg_peak_count": 0.0,
        "ppg_pulse_rate_bpm": np.nan,
        "ppg_prv_mean_nn_ms": np.nan,
        "ppg_prv_sdnn_ms": np.nan,
        "ppg_prv_rmssd_ms": np.nan,
        "ppg_prv_pnn50": np.nan,
        "ppg_prv_valid_interval_count": 0.0,
    }
    if filtered is None or filtered.size < sampling_rate_hz * 4:
        return result
    scale = float(np.std(filtered))
    if scale <= 1e-9:
        return result
    peaks, _ = find_peaks(
        filtered,
        distance=max(1, int(sampling_rate_hz * 0.30)),
        prominence=max(scale * 0.20, 1e-9),
    )
    result["ppg_peak_count"] = float(peaks.size)
    if peaks.size < 2:
        return result
    intervals_ms = np.diff(peaks) / sampling_rate_hz * 1000.0
    intervals_ms = intervals_ms[(intervals_ms >= 300.0) & (intervals_ms <= 2000.0)]
    result["ppg_prv_valid_interval_count"] = float(intervals_ms.size)
    if intervals_ms.size == 0:
        return result
    result["ppg_prv_mean_nn_ms"] = float(np.mean(intervals_ms))
    result["ppg_pulse_rate_bpm"] = float(60_000.0 / np.mean(intervals_ms))
    result["ppg_prv_sdnn_ms"] = float(np.std(intervals_ms, ddof=1)) if intervals_ms.size > 1 else 0.0
    successive = np.diff(intervals_ms)
    if successive.size:
        result["ppg_prv_rmssd_ms"] = float(np.sqrt(np.mean(successive**2)))
        result["ppg_prv_pnn50"] = float(np.mean(np.abs(successive) > 50.0))
    return result


def extract_ppg_window_features(
    window: pd.DataFrame | None,
    nominal_sampling_rate_hz: float = 25.0,
) -> dict[str, float]:
    """Extract research features from raw PPG for one aligned model window.

    Pulse-rate-variability (PRV) names are used deliberately. PPG pulse intervals
    are not claimed to be ECG-derived HRV, especially during motion.
    """
    result = empty_ppg_features()
    if window is None or window.empty:
        return result
    ordered = window.sort_values("timestamp")
    timestamps = pd.to_datetime(ordered["timestamp"], utc=True, errors="coerce")
    valid_time = timestamps.notna()
    ordered = ordered.loc[valid_time]
    timestamps = timestamps.loc[valid_time]
    if ordered.empty:
        return result

    green = pd.to_numeric(ordered.get("green_adc"), errors="coerce").to_numpy(float)
    infrared = pd.to_numeric(ordered.get("infrared_adc"), errors="coerce").to_numpy(float)
    red = pd.to_numeric(ordered.get("red_adc"), errors="coerce").to_numpy(float)
    green_status = pd.to_numeric(ordered.get("green_status"), errors="coerce").to_numpy(float)
    infrared_status = pd.to_numeric(ordered.get("infrared_status"), errors="coerce").to_numpy(float)
    red_status = pd.to_numeric(ordered.get("red_status"), errors="coerce").to_numpy(float)
    # Samsung defines status 0 as normal and -1 as interrupted/error for the
    # continuous PPG tracker. Keep the raw CSV untouched but exclude flagged
    # samples from signal processing.
    green = np.where(green_status == 0, green, np.nan)
    infrared = np.where(infrared_status == 0, infrared, np.nan)
    red = np.where(red_status == 0, red, np.nan)
    count = len(ordered)
    elapsed = timestamps.astype("int64").to_numpy() / 1e9
    deltas = np.diff(elapsed)
    observed_rate = 1.0 / np.median(deltas[deltas > 0]) if np.any(deltas > 0) else nominal_sampling_rate_hz
    rate = float(observed_rate if np.isfinite(observed_rate) and 5 <= observed_rate <= 250 else nominal_sampling_rate_hz)
    expected_delta = 1.0 / rate
    gap_fraction = float(np.mean(deltas > expected_delta * 1.8)) if deltas.size else 0.0

    result.update(
        {
            "ppg_available": 1.0,
            "ppg_sample_count": float(count),
            "ppg_duration_seconds": float(max(0.0, elapsed[-1] - elapsed[0])) if count > 1 else 0.0,
            "ppg_observed_sampling_rate_hz": rate,
            "ppg_timestamp_gap_fraction": gap_fraction,
            "ppg_green_valid_fraction": _valid_fraction(green),
            "ppg_infrared_valid_fraction": _valid_fraction(infrared),
            "ppg_red_valid_fraction": _valid_fraction(red),
            "ppg_all_channels_valid_fraction": float(
                np.mean(np.isfinite(green) & np.isfinite(infrared) & np.isfinite(red))
            ),
            "ppg_green_mean": _safe_mean(green),
            "ppg_green_std": _safe_std(green),
            "ppg_infrared_mean": _safe_mean(infrared),
            "ppg_infrared_std": _safe_std(infrared),
            "ppg_red_mean": _safe_mean(red),
            "ppg_red_std": _safe_std(red),
            "ppg_green_perfusion_index_proxy": _perfusion_index_proxy(green),
            "ppg_infrared_perfusion_index_proxy": _perfusion_index_proxy(infrared),
            "ppg_red_perfusion_index_proxy": _perfusion_index_proxy(red),
            "ppg_green_red_correlation": _correlation(green, red),
            "ppg_green_infrared_correlation": _correlation(green, infrared),
        }
    )

    channels = [(1.0, green), (2.0, infrared), (3.0, red)]
    code, selected = max(channels, key=lambda item: (_valid_fraction(item[1]), _safe_std(item[1]) or 0.0))
    filtered = _filtered_signal(selected, rate)
    result["ppg_selected_channel_code"] = code
    result["ppg_selected_valid_fraction"] = _valid_fraction(selected)
    result["ppg_selected_clipping_fraction"] = _clipping_fraction(selected)
    result["ppg_selected_snr_proxy_db"] = _snr_proxy_db(filtered, rate) if filtered is not None else np.nan
    result.update(_pulse_features(filtered, rate))
    return result


def ppg_features_for_interval(
    prepared_ppg: pd.DataFrame,
    participant_id: str,
    start: pd.Timestamp,
    end: pd.Timestamp,
    session_id: str | None = None,
    nominal_sampling_rate_hz: float = 25.0,
) -> dict[str, float]:
    if prepared_ppg.empty:
        return empty_ppg_features()
    mask = (
        (prepared_ppg["participant_id"].astype(str) == str(participant_id))
        & (prepared_ppg["timestamp"] >= start)
        & (prepared_ppg["timestamp"] <= end)
    )
    if session_id is not None:
        session_mask = prepared_ppg["session_id"].astype(str) == str(session_id)
        if (mask & session_mask).any():
            mask &= session_mask
    return extract_ppg_window_features(
        prepared_ppg.loc[mask], nominal_sampling_rate_hz=nominal_sampling_rate_hz
    )
