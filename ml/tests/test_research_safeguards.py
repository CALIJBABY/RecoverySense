from __future__ import annotations

import numpy as np
import pandas as pd

from recoverysense_ml.config import load_config
from recoverysense_ml.dataset import _time_features
from recoverysense_ml.labeling import AMBIGUOUS_LABEL, label_window, prepare_ema_data
from recoverysense_ml.preprocessing import prepare_sensor_data
from recoverysense_ml.sleep_model import _add_sequence_features
from recoverysense_ml.training import _split_indices


def _sensor_frame(future_heart_rate: float, future_accel_x: float) -> pd.DataFrame:
    rate = 10
    samples = 200
    start = pd.Timestamp("2026-03-01T12:00:00Z")
    timestamps = start + pd.to_timedelta(np.arange(samples) / rate, unit="s")
    heart_rate = np.full(samples, 60.0)
    accel_x = np.zeros(samples)
    heart_rate[100:] = future_heart_rate
    accel_x[100:] = future_accel_x
    return pd.DataFrame(
        {
            "participant_id": "p1",
            "session_id": "s1",
            "timestamp": timestamps,
            "heart_rate": heart_rate,
            "accel_x": accel_x,
            "accel_y": np.zeros(samples),
            "accel_z": np.ones(samples),
            "heart_rate_age_ms": np.arange(samples, dtype=float) * 100.0,
            "screen_interactive": np.where(np.arange(samples) < 100, 1.0, 0.0),
        }
    )


def test_preprocessing_does_not_use_future_samples() -> None:
    config = load_config("ml/config/default.yaml")
    first = prepare_sensor_data(_sensor_frame(60.0, 0.0), config)
    changed_future = prepare_sensor_data(_sensor_frame(180.0, 5.0), config)

    cutoff = pd.Timestamp("2026-03-01T12:00:09Z")
    first_prefix = first[first["timestamp"] <= cutoff].reset_index(drop=True)
    changed_prefix = changed_future[
        changed_future["timestamp"] <= cutoff
    ].reset_index(drop=True)

    assert len(first_prefix) == len(changed_prefix)
    for column in (
        "heart_rate",
        "accel_x",
        "accel_y",
        "accel_z",
        "heart_rate_age_ms",
        "screen_interactive",
    ):
        np.testing.assert_allclose(
            first_prefix[column].to_numpy(float),
            changed_prefix[column].to_numpy(float),
            equal_nan=True,
            atol=1e-10,
        )


def test_quality_diagnostic_columns_survive_preprocessing() -> None:
    config = load_config("ml/config/default.yaml")
    processed = prepare_sensor_data(_sensor_frame(60.0, 0.0), config)
    assert "heart_rate_age_ms" in processed.columns
    assert "screen_interactive" in processed.columns
    assert processed["heart_rate_age_ms"].notna().any()
    assert processed["screen_interactive"].notna().any()


def test_sleep_sequence_features_are_causal() -> None:
    start = pd.Timestamp("2026-03-01T22:00:00Z")
    base = pd.DataFrame(
        {
            "participant_id": ["p1"] * 6,
            "sleep_session_id": ["night1"] * 6,
            "epoch_start": [start + pd.Timedelta(seconds=30 * i) for i in range(6)],
            "dynamic_accel_mag_std": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
            "stillness_fraction": [0.1, 0.2, 0.95, 0.96, 0.97, 0.98],
            "gyro_mag_mean": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
            "hr_mean": [70.0, 69.0, 68.0, 67.0, 66.0, 65.0],
        }
    )
    changed_future = base.copy()
    changed_future.loc[5, "dynamic_accel_mag_std"] = 6000.0
    changed_future.loc[5, "hr_mean"] = 200.0

    original_features = _add_sequence_features(base)
    future_changed_features = _add_sequence_features(changed_future)

    assert not any(column.startswith("next_") for column in original_features.columns)
    causal_columns = [
        column
        for column in original_features.columns
        if column.startswith("previous_") or column.startswith("rolling_5_")
    ]
    pd.testing.assert_frame_equal(
        original_features.loc[:4, causal_columns],
        future_changed_features.loc[:4, causal_columns],
        check_dtype=False,
    )


def test_negative_labels_require_a_nearby_low_craving_ema() -> None:
    config = load_config("ml/config/default.yaml")
    window_end = pd.Timestamp("2026-03-01T12:00:00Z")

    distant_low = prepare_ema_data(
        pd.DataFrame(
            [
                {
                    "participant_id": "p1",
                    "timestamp": window_end + pd.Timedelta(minutes=10),
                    "craving_score": 1,
                }
            ]
        ),
        config,
    )
    label, _, _ = label_window("p1", window_end, distant_low, config)
    assert label == AMBIGUOUS_LABEL

    nearby_low = prepare_ema_data(
        pd.DataFrame(
            [
                {
                    "participant_id": "p1",
                    "timestamp": window_end + pd.Timedelta(seconds=60),
                    "craving_score": 1,
                }
            ]
        ),
        config,
    )
    label, _, _ = label_window("p1", window_end, nearby_low, config)
    assert label == 0

    nearby_high = prepare_ema_data(
        pd.DataFrame(
            [
                {
                    "participant_id": "p1",
                    "timestamp": window_end + pd.Timedelta(seconds=60),
                    "craving_score": 9,
                }
            ]
        ),
        config,
    )
    label, _, _ = label_window("p1", window_end, nearby_high, config)
    assert label == 1


def test_single_participant_split_is_purged_and_temporal() -> None:
    config = load_config("ml/config/default.yaml")
    start = pd.Timestamp("2026-03-01T12:00:00Z")
    dataset = pd.DataFrame(
        {
            "participant_id": ["p1"] * 30,
            "session_id": ["s1"] * 30,
            "window_start": [start + pd.Timedelta(minutes=i) for i in range(30)],
            "window_end": [
                start + pd.Timedelta(minutes=i, seconds=29) for i in range(30)
            ],
            "label": [i % 2 for i in range(30)],
        }
    )

    train_idx, test_idx, method = _split_indices(dataset, config)
    assert method == "purged-temporal-holdout-fallback"
    train_end = pd.to_datetime(dataset.iloc[train_idx]["window_end"], utc=True).max()
    test_start = pd.to_datetime(dataset.iloc[test_idx]["window_start"], utc=True).min()
    assert train_end < test_start - pd.Timedelta(
        seconds=float(config["windowing"]["window_seconds"])
    )


def test_time_features_use_participant_local_offset() -> None:
    utc_time = pd.Timestamp("2026-03-02T01:00:00Z")
    utc_features = _time_features(utc_time, 0)
    eastern_features = _time_features(utc_time, -300)

    assert utc_features["local_time_context_available"] == 1.0
    assert eastern_features["local_time_context_available"] == 1.0
    # 01:00 UTC and 20:00 local on the previous day must not encode as the
    # same time/day pattern.
    assert not np.isclose(
        utc_features["time_of_day_sin"], eastern_features["time_of_day_sin"]
    )
    assert not np.isclose(
        utc_features["day_of_week_sin"], eastern_features["day_of_week_sin"]
    )


def test_time_features_fail_missing_when_local_offset_is_unavailable() -> None:
    features = _time_features(pd.Timestamp("2026-03-02T01:00:00Z"), None)
    assert features["local_time_context_available"] == 0.0
    assert np.isnan(features["time_of_day_sin"])
    assert np.isnan(features["day_of_week_cos"])
