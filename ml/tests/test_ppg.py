from __future__ import annotations

import numpy as np
import pandas as pd

from recoverysense_ml.ppg import (
    extract_ppg_window_features,
    ppg_features_for_interval,
    prepare_ppg_data,
)


def _synthetic_ppg(seconds: int = 30, rate: int = 25, bpm: float = 72.0) -> pd.DataFrame:
    count = seconds * rate
    time = np.arange(count) / rate
    pulse_hz = bpm / 60.0
    rng = np.random.default_rng(4)
    waveform = np.sin(2 * np.pi * pulse_hz * time) + 0.25 * np.sin(
        4 * np.pi * pulse_hz * time
    )
    start = pd.Timestamp("2026-07-27T12:00:00Z")
    return pd.DataFrame(
        {
            "participant_id": "p1",
            "session_id": "s1",
            "timestamp": [start + pd.Timedelta(seconds=float(value)) for value in time],
            "sampling_rate_hz": rate,
            "green_adc": 100000 + waveform * 5000 + rng.normal(0, 120, count),
            "infrared_adc": 80000 + waveform * 3500 + rng.normal(0, 150, count),
            "red_adc": 70000 + waveform * 2500 + rng.normal(0, 180, count),
            "green_status": np.zeros(count, dtype=int),
            "infrared_status": np.zeros(count, dtype=int),
            "red_status": np.zeros(count, dtype=int),
        }
    )


def test_ppg_feature_pipeline_recovers_pulse_rate() -> None:
    frame = prepare_ppg_data(_synthetic_ppg())
    features = extract_ppg_window_features(frame, nominal_sampling_rate_hz=25)
    assert features["ppg_available"] == 1.0
    assert features["ppg_sample_count"] == 750.0
    assert 65.0 <= features["ppg_pulse_rate_bpm"] <= 80.0
    assert features["ppg_prv_valid_interval_count"] > 20
    assert features["ppg_green_valid_fraction"] == 1.0


def test_ppg_interval_alignment_is_participant_and_time_specific() -> None:
    frame = prepare_ppg_data(_synthetic_ppg())
    features = ppg_features_for_interval(
        frame,
        participant_id="p1",
        session_id="s1",
        start=pd.Timestamp("2026-07-27T12:00:05Z"),
        end=pd.Timestamp("2026-07-27T12:00:20Z"),
    )
    assert features["ppg_available"] == 1.0
    assert 300 <= features["ppg_sample_count"] <= 400

    missing = ppg_features_for_interval(
        frame,
        participant_id="other",
        session_id="s1",
        start=pd.Timestamp("2026-07-27T12:00:05Z"),
        end=pd.Timestamp("2026-07-27T12:00:20Z"),
    )
    assert missing["ppg_available"] == 0.0
