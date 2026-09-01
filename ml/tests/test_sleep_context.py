from __future__ import annotations

import numpy as np
import pandas as pd

from recoverysense_ml.config import load_config
from recoverysense_ml.dataset import _prior_sleep_features, prepare_sleep_context


def test_prior_sleep_uses_only_completed_past_night_and_flags_stale() -> None:
    config = load_config("ml/config/default.yaml")
    frame = pd.DataFrame(
        [
            {
                "participant_id": "p1",
                "sleep_session_id": "old",
                "status": "confirmed",
                "reported_wake": "2026-01-01T06:00:00Z",
                "estimated_total_sleep_minutes": 390,
            },
            {
                "participant_id": "p1",
                "sleep_session_id": "future",
                "status": "confirmed",
                "reported_wake": "2026-01-03T06:00:00Z",
                "estimated_total_sleep_minutes": 500,
            },
        ]
    )
    sleep = prepare_sleep_context(frame)
    current = _prior_sleep_features(
        "p1", pd.Timestamp("2026-01-02T12:00:00Z"), sleep, config
    )
    assert current["sleep_log_available"] == 1.0
    assert current["sleep_log_stale"] == 0.0
    assert current["prior_sleep_duration_minutes"] == 390.0

    stale = _prior_sleep_features(
        "p1", pd.Timestamp("2026-01-02T20:00:00Z"), sleep, config
    )
    assert stale["sleep_log_available"] == 1.0
    assert stale["sleep_log_stale"] == 1.0

    expired = _prior_sleep_features(
        "p1", pd.Timestamp("2026-01-03T07:00:01Z"), prepare_sleep_context(frame.iloc[:1]), config
    )
    assert expired["sleep_log_available"] == 0.0
    assert np.isnan(expired["prior_sleep_duration_minutes"])
