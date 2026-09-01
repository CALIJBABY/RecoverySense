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
    sleep_rows: list[dict[str, Any]] = []
    for participant_number in range(participants):
        participant_id = f"participant-{participant_number + 1:02d}"
        session_id = "demo-session"
        prior_wake = base_time + pd.Timedelta(days=participant_number, hours=-5)
        sleep_rows.append(
            {
                "participant_id": participant_id,
                "sleep_session_id": f"demo-sleep-{participant_number + 1:02d}",
                "status": "confirmed",
                "recording_start": prior_wake - pd.Timedelta(hours=8),
                "recording_end": prior_wake,
                "reported_sleep_onset": prior_wake - pd.Timedelta(hours=7.5),
                "reported_wake": prior_wake,
                "predicted_sleep_onset": prior_wake - pd.Timedelta(hours=7.4),
                "predicted_wake": prior_wake,
                "estimated_total_sleep_minutes": 420 + int(rng.integers(-30, 31)),
                "estimated_sleep_efficiency": float(rng.uniform(0.78, 0.96)),
                "estimated_awakenings": int(rng.integers(0, 4)),
                "estimated_waso_minutes": float(rng.integers(5, 45)),
                "overnight_mean_hr": float(rng.uniform(52, 68)),
                "overnight_movement_std_g": float(rng.uniform(0.01, 0.08)),
                "sleep_estimate_confidence": float(rng.uniform(0.65, 0.95)),
                "sleep_quality": int(rng.integers(2, 6)),
                "rested_score": int(rng.integers(2, 6)),
                "reported_awakenings": int(rng.integers(0, 4)),
                "watch_removed": False,
            }
        )
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
                "timezone_offset_minutes": -300,
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
                "timezone_offset_minutes": -300,
            }
        )

    sensors = pd.concat(sensor_rows, ignore_index=True)
    ema = pd.DataFrame(ema_rows)
    sleep = pd.DataFrame(sleep_rows)

    sensor_path = Path(config["paths"]["raw_sensor_csv"])
    ema_path = Path(config["paths"]["ema_csv"])
    sleep_path = Path(config["paths"].get("sleep_sessions_csv", "ml/data/raw/sleep_sessions.csv"))
    sensor_path.parent.mkdir(parents=True, exist_ok=True)
    ema_path.parent.mkdir(parents=True, exist_ok=True)
    sleep_path.parent.mkdir(parents=True, exist_ok=True)
    sensors.to_csv(sensor_path, index=False)
    ema.to_csv(ema_path, index=False)
    sleep.to_csv(sleep_path, index=False)
    return sensors, ema


def generate_sleep_demo_data(
    config: dict[str, Any],
    participants: int = 6,
    minutes_per_night: int = 20,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Generate small non-clinical overnight data for sleep-pipeline tests."""
    rng = np.random.default_rng(int(config["project"]["random_seed"]) + 17)
    rate = float(config["preprocessing"]["sampling_rate_hz"])
    samples = int(minutes_per_night * 60 * rate)
    base = pd.Timestamp("2026-02-01T22:00:00Z")
    sensor_frames: list[pd.DataFrame] = []
    session_rows: list[dict[str, Any]] = []

    for index in range(participants):
        participant_id = f"sleep-participant-{index + 1:02d}"
        sleep_session_id = f"sleep-night-{index + 1:02d}"
        start = base + pd.Timedelta(days=index)
        times = np.arange(samples) / rate
        timestamps = start + pd.to_timedelta(times, unit="s")
        onset_seconds = 3 * 60
        wake_seconds = (minutes_per_night - 3) * 60
        sleeping = (times >= onset_seconds) & (times < wake_seconds)

        movement_scale = np.where(sleeping, 0.012, 0.12)
        heart_rate = np.where(sleeping, 58.0, 76.0) + rng.normal(0, 1.8, samples)
        accel_x = rng.normal(0, movement_scale)
        accel_y = rng.normal(0, movement_scale)
        accel_z = 1.0 + rng.normal(0, movement_scale)
        gyro_x = rng.normal(0, movement_scale * 1.5)
        gyro_y = rng.normal(0, movement_scale * 1.5)
        gyro_z = rng.normal(0, movement_scale * 1.5)
        step_detected = (~sleeping & (rng.random(samples) < 0.004)).astype(float)
        step_count = np.cumsum(step_detected)

        sensor_frames.append(
            pd.DataFrame(
                {
                    "participant_id": participant_id,
                    "session_id": f"watch-session-{index + 1:02d}",
                    "recording_mode": "sleep",
                    "sleep_session_id": sleep_session_id,
                    "timestamp": timestamps,
                    "heart_rate": heart_rate,
                    "heart_rate_accuracy": 3,
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
        session_rows.append(
            {
                "participant_id": participant_id,
                "sleep_session_id": sleep_session_id,
                "status": "confirmed",
                "recording_start": start,
                "recording_end": start + pd.Timedelta(minutes=minutes_per_night),
                "reported_sleep_onset": start + pd.Timedelta(seconds=onset_seconds),
                "reported_wake": start + pd.Timedelta(seconds=wake_seconds),
                "sleep_quality": 4,
                "rested_score": 4,
                "watch_removed": False,
            }
        )

    return pd.concat(sensor_frames, ignore_index=True), pd.DataFrame(session_rows)



def generate_complete_demo_data(
    config: dict[str, Any],
    participants: int = 12,
    minutes: int = 12,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Generate one combined non-clinical demo for both ML pipelines.

    Daytime participants provide craving/EMA examples and prior-night summary
    context. Separate synthetic overnight participants provide raw sleep-mode
    sensor rows and confirmed onset/wake labels. Keeping the participant groups
    separate prevents the demo from implying that the generated nights are real
    longitudinal observations.
    """
    daytime_sensors, ema = generate_demo_data(config, participants, minutes)
    sleep_path = Path(
        config["paths"].get("sleep_sessions_csv", "ml/data/raw/sleep_sessions.csv")
    )
    prior_sleep = pd.read_csv(sleep_path)

    overnight_participants = max(6, min(participants, 10))
    overnight_minutes = max(10, min(30, minutes + 8))
    overnight_sensors, overnight_sessions = generate_sleep_demo_data(
        config,
        participants=overnight_participants,
        minutes_per_night=overnight_minutes,
    )

    sensors = pd.concat(
        [daytime_sensors, overnight_sensors],
        ignore_index=True,
        sort=False,
    )
    sleep = pd.concat(
        [prior_sleep, overnight_sessions],
        ignore_index=True,
        sort=False,
    )

    sensor_path = Path(config["paths"]["raw_sensor_csv"])
    ema_path = Path(config["paths"]["ema_csv"])
    sensor_path.parent.mkdir(parents=True, exist_ok=True)
    ema_path.parent.mkdir(parents=True, exist_ok=True)
    sleep_path.parent.mkdir(parents=True, exist_ok=True)
    sensors.to_csv(sensor_path, index=False)
    ema.to_csv(ema_path, index=False)
    sleep.to_csv(sleep_path, index=False)
    return sensors, ema, sleep
