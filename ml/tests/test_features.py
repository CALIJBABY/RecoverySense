from __future__ import annotations

import numpy as np
import pandas as pd

from recoverysense_ml.config import load_config
from recoverysense_ml.features import extract_window_features


def test_feature_extraction_returns_finite_values() -> None:
    config = load_config("ml/config/default.yaml")
    rate = config["preprocessing"]["sampling_rate_hz"]
    samples = int(rate * config["windowing"]["window_seconds"])
    time = np.arange(samples) / rate
    frame = pd.DataFrame(
        {
            "heart_rate": 70 + np.sin(time),
            "accel_x": 0.1 * np.sin(2 * np.pi * time),
            "accel_y": 0.1 * np.cos(2 * np.pi * time),
            "accel_z": np.ones(samples),
        }
    )
    features = extract_window_features(frame, config)
    assert len(features) > 40
    assert all(np.isfinite(value) for value in features.values())
