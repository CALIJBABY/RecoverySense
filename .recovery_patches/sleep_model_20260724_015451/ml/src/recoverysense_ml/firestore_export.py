from __future__ import annotations

import argparse
import os
from pathlib import Path
from typing import Any

import pandas as pd

STANDARD_GRAVITY = 9.80665
SENSOR_COLUMNS = [
    "participant_id",
    "session_id",
    "timestamp",
    "heart_rate",
    "heart_rate_timestamp",
    "heart_rate_accuracy",
    "accel_x",
    "accel_y",
    "accel_z",
    "acceleration_g",
    "accelerometer_accuracy",
    "gyro_x",
    "gyro_y",
    "gyro_z",
    "gyro_magnitude",
    "gyro_timestamp",
    "gyroscope_accuracy",
    "step_count",
    "step_detected",
    "off_body",
]
EMA_COLUMNS = [
    "participant_id",
    "session_id",
    "timestamp",
    "prompted_at",
    "opened_at",
    "craving_score",
    "stress_score",
    "mood_score",
    "anxiety_score",
    "boredom_score",
    "current_activity",
    "social_context",
    "trigger_situation",
    "craving_started_recently",
    "onset_minutes_ago",
    "acted_on_craving",
    "coping_strategy_used",
    "coping_strategy",
    "source",
    "trigger_reason",
    "note",
    "trigger_probability",
    "model_version",
    "model_threshold",
    "window_start",
    "window_end",
    "response_delay_ms",
]


def initialize_firebase(credentials_path: str | None = None):
    """Initialize Firebase Admin using a service-account file or ADC."""
    try:
        import firebase_admin
        from firebase_admin import credentials, firestore
    except ImportError as exc:
        raise RuntimeError(
            "firebase-admin is required only for Firestore export. "
            "Install it with: pip install firebase-admin"
        ) from exc

    if not firebase_admin._apps:
        path = credentials_path or os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
        if path:
            firebase_admin.initialize_app(credentials.Certificate(path))
        else:
            firebase_admin.initialize_app()
    return firestore.client()


def _iso_timestamp(timestamp_ms: Any) -> str | None:
    if timestamp_ms is None:
        return None
    value = pd.to_numeric(timestamp_ms, errors="coerce")
    if pd.isna(value):
        return None
    return pd.to_datetime(int(value), unit="ms", utc=True).isoformat()


def _numeric(value: Any) -> float | None:
    result = pd.to_numeric(value, errors="coerce")
    if pd.isna(result):
        return None
    return float(result)


def _to_g(value: Any) -> float | None:
    numeric = _numeric(value)
    return None if numeric is None else numeric / STANDARD_GRAVITY


def export_firestore_to_csv(
    output_dir: str | Path = "ml/data/raw",
    credentials_path: str | None = None,
) -> tuple[Path, Path]:
    """Export Firestore sensor batches and EMA events to ML-ready CSV files.

    Raw accelerometer axes are stored in Android m/s^2 and converted to g only
    in the exported analysis copy. Gyroscope values remain in rad/s. Firestore
    retains the original raw measurements.
    """
    db = initialize_firebase(credentials_path)
    sensor_rows: list[dict[str, Any]] = []
    ema_rows: list[dict[str, Any]] = []

    for participant_doc in db.collection("participants").stream():
        participant_id = participant_doc.id
        participant_ref = participant_doc.reference

        for session_doc in participant_ref.collection("sessions").stream():
            session_id = session_doc.id
            for batch_doc in session_doc.reference.collection("sensor_batches").stream():
                batch = batch_doc.to_dict() or {}
                for sample in batch.get("samples", []):
                    if not isinstance(sample, dict):
                        continue
                    sensor_rows.append(
                        {
                            "participant_id": participant_id,
                            "session_id": session_id,
                            "timestamp": _iso_timestamp(sample.get("timestamp_ms")),
                            "heart_rate": sample.get("heart_rate"),
                            "heart_rate_timestamp": _iso_timestamp(
                                sample.get("heart_rate_timestamp_ms")
                            ),
                            "heart_rate_accuracy": sample.get("heart_rate_accuracy"),
                            "accel_x": _to_g(sample.get("accel_x_ms2")),
                            "accel_y": _to_g(sample.get("accel_y_ms2")),
                            "accel_z": _to_g(sample.get("accel_z_ms2")),
                            "acceleration_g": _numeric(sample.get("acceleration_g")),
                            "accelerometer_accuracy": sample.get("accelerometer_accuracy"),
                            "gyro_x": _numeric(sample.get("gyro_x_rad_s")),
                            "gyro_y": _numeric(sample.get("gyro_y_rad_s")),
                            "gyro_z": _numeric(sample.get("gyro_z_rad_s")),
                            "gyro_magnitude": _numeric(sample.get("gyro_magnitude_rad_s")),
                            "gyro_timestamp": _iso_timestamp(sample.get("gyro_timestamp_ms")),
                            "gyroscope_accuracy": sample.get("gyroscope_accuracy"),
                            "step_count": _numeric(sample.get("step_count")),
                            "step_detected": sample.get("step_detected"),
                            "off_body": sample.get("off_body"),
                        }
                    )

        for ema_doc in participant_ref.collection("ema_events").stream():
            event = ema_doc.to_dict() or {}
            ema_rows.append(
                {
                    "participant_id": participant_id,
                    "session_id": event.get("session_id"),
                    "timestamp": _iso_timestamp(event.get("timestamp_ms")),
                    "prompted_at": _iso_timestamp(event.get("prompted_at_ms")),
                    "opened_at": _iso_timestamp(event.get("opened_at_ms")),
                    "craving_score": event.get("craving_score"),
                    "stress_score": event.get("stress_score"),
                    "mood_score": event.get("mood_score"),
                    "anxiety_score": event.get("anxiety_score"),
                    "boredom_score": event.get("boredom_score"),
                    "current_activity": event.get("current_activity"),
                    "social_context": event.get("social_context"),
                    "trigger_situation": event.get("trigger_situation"),
                    "craving_started_recently": event.get("craving_started_recently"),
                    "onset_minutes_ago": event.get("onset_minutes_ago"),
                    "acted_on_craving": event.get("acted_on_craving"),
                    "coping_strategy_used": event.get("coping_strategy_used"),
                    "coping_strategy": event.get("coping_strategy"),
                    "source": event.get("source", "manual"),
                    "trigger_reason": event.get("trigger_reason"),
                    "note": event.get("note"),
                    "trigger_probability": event.get("trigger_probability"),
                    "model_version": event.get("model_version"),
                    "model_threshold": event.get("model_threshold"),
                    "window_start": _iso_timestamp(event.get("window_start_ms")),
                    "window_end": _iso_timestamp(event.get("window_end_ms")),
                    "response_delay_ms": event.get("response_delay_ms"),
                }
            )

    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    sensor_path = output / "sensor_readings.csv"
    ema_path = output / "ema_events.csv"

    sensor_frame = pd.DataFrame(sensor_rows, columns=SENSOR_COLUMNS)
    ema_frame = pd.DataFrame(ema_rows, columns=EMA_COLUMNS)

    if not sensor_frame.empty:
        sensor_frame = sensor_frame.dropna(subset=["participant_id", "timestamp"])
        sensor_frame = sensor_frame.sort_values(
            ["participant_id", "session_id", "timestamp"],
            na_position="last",
        )
    if not ema_frame.empty:
        ema_frame = ema_frame.dropna(
            subset=["participant_id", "timestamp", "craving_score"]
        )
        ema_frame = ema_frame.sort_values(["participant_id", "timestamp"])

    sensor_frame.to_csv(sensor_path, index=False)
    ema_frame.to_csv(ema_path, index=False)
    return sensor_path, ema_path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export RecoverySense Firestore data to ML-ready CSV files."
    )
    parser.add_argument("--output-dir", default="ml/data/raw")
    parser.add_argument(
        "--credentials",
        help=(
            "Path to a Firebase service-account JSON file. If omitted, "
            "GOOGLE_APPLICATION_CREDENTIALS or Application Default Credentials is used."
        ),
    )
    args = parser.parse_args()

    sensor_path, ema_path = export_firestore_to_csv(
        output_dir=args.output_dir,
        credentials_path=args.credentials,
    )
    print(f"Wrote sensor data to {sensor_path}")
    print(f"Wrote EMA data to {ema_path}")


if __name__ == "__main__":
    main()
