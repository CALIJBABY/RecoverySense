from __future__ import annotations

import numpy as np
import pandas as pd

from recoverysense_ml.config import load_config
from recoverysense_ml.features import extract_window_features
from recoverysense_ml.preprocessing import prepare_sensor_data


def _quality_frame() -> pd.DataFrame:
    rate = 10
    samples = 100
    start = pd.Timestamp("2026-08-11T12:00:00Z")
    timestamps = start + pd.to_timedelta(np.arange(samples) / rate, unit="s")
    frame = pd.DataFrame(
        {
            "participant_id": ["p1"] * samples,
            "session_id": ["s1"] * samples,
            "timestamp": timestamps,
            "heart_rate": np.full(samples, 72.0),
            "raw_heart_rate": np.full(samples, 72.0),
            "heart_rate_valid": np.ones(samples),
            "heart_rate_quality_code": np.zeros(samples),
            "heart_rate_outlier_flag": np.zeros(samples),
            "heart_rate_age_ms": np.full(samples, 500.0),
            "heart_rate_accuracy": np.full(samples, 3.0),
            "accel_x": np.zeros(samples),
            "accel_y": np.zeros(samples),
            "accel_z": np.ones(samples),
            "off_body": np.zeros(samples),
            "screen_interactive": np.ones(samples),
        }
    )
    return frame


def test_hard_invalid_hr_is_not_resurrected_by_interpolation() -> None:
    config = load_config("ml/config/default.yaml")
    frame = _quality_frame()
    # Two seconds explicitly rejected by the watch quality gate.
    frame.loc[30:49, "heart_rate_valid"] = 0
    frame.loc[30:49, "heart_rate_quality_code"] = 3
    frame.loc[30:49, "off_body"] = 1

    processed = prepare_sensor_data(frame, config)
    rejected = processed.iloc[30:50]
    assert rejected["heart_rate"].isna().all()
    assert rejected["raw_heart_rate"].notna().all()
    assert (rejected["heart_rate_valid"] < 0.5).all()


def test_stale_hr_is_excluded_defensively() -> None:
    config = load_config("ml/config/default.yaml")
    frame = _quality_frame()
    frame.loc[40:59, "heart_rate_age_ms"] = 120_000
    frame.loc[40:59, "heart_rate_valid"] = 0
    frame.loc[40:59, "heart_rate_quality_code"] = 2

    processed = prepare_sensor_data(frame, config)
    assert processed.iloc[40:60]["heart_rate"].isna().all()


def test_temporal_outlier_is_soft_flag_by_default() -> None:
    config = load_config("ml/config/default.yaml")
    frame = _quality_frame()
    frame.loc[50, "heart_rate"] = 160
    frame.loc[50, "raw_heart_rate"] = 160
    frame.loc[50, "heart_rate_outlier_flag"] = 1

    processed = prepare_sensor_data(frame, config)
    assert processed.iloc[50]["heart_rate_outlier_flag"] >= 0.5
    # Default policy preserves the flagged value for sensitivity analyses.
    assert np.isfinite(processed.iloc[50]["heart_rate"])

    config["preprocessing"]["exclude_temporal_outliers"] = True
    excluded = prepare_sensor_data(frame, config)
    assert np.isnan(excluded.iloc[50]["heart_rate"])


def test_quality_features_report_rejection_reasons() -> None:
    config = load_config("ml/config/default.yaml")
    frame = _quality_frame()
    frame.loc[20:29, "heart_rate_valid"] = 0
    frame.loc[20:29, "heart_rate_quality_code"] = 4  # no contact
    frame.loc[20:29, "heart_rate"] = np.nan
    frame.loc[60:69, "heart_rate_outlier_flag"] = 1

    processed = prepare_sensor_data(frame, config)
    features = extract_window_features(processed, config)
    assert features["raw_heart_rate_observed_fraction"] > 0.99
    assert features["heart_rate_no_contact_fraction"] > 0.05
    assert features["heart_rate_temporal_outlier_fraction"] > 0.05
    assert 0.0 < features["heart_rate_gate_valid_fraction"] < 1.0
