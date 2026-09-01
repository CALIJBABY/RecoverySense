from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd


def generate_demo_data(
    config: dict[str, Any],
    participants: int = 12,
    minutes: int = 12,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Generate deterministic, non-clinical data for pipeline testing only."""
    rng = np.random.default_rng(int(config["project"]["random_seed"]))
    rate = float(config["preprocessing"]["sampling_rate_hz"])
    samples = int(minutes * 60 * rate)
    base_time = pd.Timestamp("2026-01-01T12:00:00Z")

    sensor_rows: list[pd.DataFrame] = []
    ema_rows: list[dict[str, Any]] = []
    for participant_number in range(participants):
        participant_id = f"participant-{participant_number + 1:02d}"
        session_id = "demo-session"
        time_seconds = np.arange(samples) / rate
        timestamps = base_time + pd.to_timedelta(
            time_seconds + participant_number * 86400,
            unit="s",
        )

        event_center = rng.integers(int(samples * 0.35), int(samples * 0.80))
        event_duration = int(rate * 90)
        event_start = max(0, event_center - event_duration)
        event_mask = np.zeros(samples, dtype=bool)
        event_mask[event_start:event_center] = True
        has_positive_event = participant_number % 2 == 0

        heart_rate = (
            70
            + rng.normal(0, 2.5, samples)
            + 3 * np.sin(2 * np.pi * time_seconds / 60)
        )
        activity_scale = 0.025 + 0.015 * np.sin(
            2 * np.pi * time_seconds / 30
        ) ** 2
        if has_positive_event:
            heart_rate[event_mask] += np.linspace(2, 24, event_mask.sum())
            activity_scale[event_mask] += 0.20

        accel_x = rng.normal(0.0, activity_scale)
        accel_y = rng.normal(0.0, activity_scale)
        accel_z = 1.0 + rng.normal(0.0, activity_scale)
        gyro_x = rng.normal(0.0, activity_scale * 1.5)
        gyro_y = rng.normal(0.0, activity_scale * 1.5)
        gyro_z = rng.normal(0.0, activity_scale * 1.5)
        if has_positive_event:
            pulse = np.sin(2 * np.pi * 1.4 * time_seconds[event_mask])
            accel_x[event_mask] += 0.22 * pulse
            accel_y[event_mask] += 0.16 * np.cos(
                2 * np.pi * 1.4 * time_seconds[event_mask]
            )
            gyro_x[event_mask] += 0.40 * pulse
            gyro_y[event_mask] += 0.30 * np.cos(
                2 * np.pi * 1.4 * time_seconds[event_mask]
            )

        step_detected = np.zeros(samples)
        walking_samples = rng.random(samples) < (0.003 + activity_scale * 0.02)
        step_detected[walking_samples] = 1.0
        step_count = np.cumsum(step_detected)

        missing = rng.random(samples) < 0.005
        heart_rate[missing] = np.nan

        sensor_rows.append(
            pd.DataFrame(
                {
                    "participant_id": participant_id,
                    "session_id": session_id,
                    "timestamp": timestamps,
                    "heart_rate": heart_rate,
                    "heart_rate_accuracy": np.where(missing, 0, 3),
                    "accel_x": accel_x,
                    "accel_y": accel_y,
                    "accel_z": accel_z,
                    "accelerometer_accuracy": 3,
                    "gyro_x": gyro_x,
                    "gyro_y": gyro_y,
                    "gyro_z": gyro_z,
                    "gyroscope_accuracy": 3,
                    "step_count": step_count,
                    "step_detected": step_detected,
                    "off_body": 0,
                }
            )
        )
        score = int(
            rng.integers(8, 11) if has_positive_event else rng.integers(0, 5)
        )
        ema_rows.append(
            {
                "participant_id": participant_id,
                "session_id": session_id,
                "timestamp": timestamps[event_center],
                "craving_score": score,
                "stress_score": min(10, max(0, score + int(rng.integers(-2, 2)))),
                "mood_score": max(0, 10 - score),
                "anxiety_score": min(10, max(0, score + int(rng.integers(-2, 2)))),
                "boredom_score": int(rng.integers(0, 11)),
                "source": "synthetic-demo",
            }
        )
        ema_rows.append(
            {
                "participant_id": participant_id,
                "session_id": session_id,
                "timestamp": timestamps[-1],
                "craving_score": int(rng.integers(0, 4)),
                "stress_score": int(rng.integers(0, 5)),
                "mood_score": int(rng.integers(5, 10)),
                "anxiety_score": int(rng.integers(0, 5)),
                "boredom_score": int(rng.integers(0, 8)),
                "source": "synthetic-demo",
            }
        )

    sensors = pd.concat(sensor_rows, ignore_index=True)
    ema = pd.DataFrame(ema_rows)

    sensor_path = Path(config["paths"]["raw_sensor_csv"])
    ema_path = Path(config["paths"]["ema_csv"])
    sensor_path.parent.mkdir(parents=True, exist_ok=True)
    ema_path.parent.mkdir(parents=True, exist_ok=True)
    sensors.to_csv(sensor_path, index=False)
    ema.to_csv(ema_path, index=False)
    return sensors, ema
