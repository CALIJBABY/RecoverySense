"""
Export one RecoverySense participant from Firestore using paged reads.

The participant identifier is supplied at runtime rather than stored in source
control. Exported participant data are local research artifacts and should not
be committed to Git.
"""
from pathlib import Path
import argparse
import csv

from recoverysense_ml.firestore_export import (
    initialize_firebase,
    _iso_timestamp,
    _numeric,
    _to_g,
    SENSOR_COLUMNS,
    EMA_COLUMNS,
    SLEEP_COLUMNS,
)

parser = argparse.ArgumentParser(
    description="Export one RecoverySense participant from Firestore."
)
parser.add_argument(
    "--participant-id",
    required=True,
    help="Firebase participant UID supplied locally at runtime.",
)
args = parser.parse_args()

PARTICIPANT_ID = args.participant_id
PAGE_SIZE = 20


def paged_docs(collection, page_size=PAGE_SIZE):
    last = None

    while True:
        query = collection.order_by("__name__").limit(page_size)

        if last is not None:
            query = query.start_after(last)

        docs = list(query.stream())

        if not docs:
            break

        for doc in docs:
            yield doc

        last = docs[-1]


db = initialize_firebase()

participant_ref = db.collection("participants").document(PARTICIPANT_ID)

if not participant_ref.get().exists:
    raise RuntimeError(f"Participant not found: {PARTICIPANT_ID}")

output = Path("ml/data/raw/primary_participant")
output.mkdir(parents=True, exist_ok=True)

sensor_path = output / "sensor_readings.csv"
ema_path = output / "ema_events.csv"
sleep_path = output / "sleep_sessions.csv"

sessions = list(paged_docs(participant_ref.collection("sessions"), 25))

sensor_rows = 0

with sensor_path.open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=SENSOR_COLUMNS)
    writer.writeheader()

    for session_number, session_doc in enumerate(sessions, 1):
        session_id = session_doc.id
        session_data = session_doc.to_dict() or {}

        for batch_doc in paged_docs(
            session_doc.reference.collection("sensor_batches")
        ):
            batch = batch_doc.to_dict() or {}

            recording_mode = batch.get(
                "recording_mode",
                session_data.get("recording_mode", "continuous"),
            )

            sleep_session_id = batch.get(
                "sleep_session_id",
                session_data.get("sleep_session_id"),
            )

            for sample in batch.get("samples", []):
                if not isinstance(sample, dict):
                    continue

                writer.writerow({
                    "participant_id": PARTICIPANT_ID,
                    "session_id": session_id,
                    "recording_mode": recording_mode,
                    "sleep_session_id": sleep_session_id,
                    "batch_id": batch.get("batch_id", batch_doc.id),
                    "timestamp": _iso_timestamp(sample.get("timestamp_ms")),
                    "heart_rate": sample.get("heart_rate"),
                    "heart_rate_timestamp": _iso_timestamp(
                        sample.get("heart_rate_timestamp_ms")
                    ),
                    "heart_rate_age_ms": sample.get("heart_rate_age_ms"),
                    "heart_rate_accuracy": sample.get("heart_rate_accuracy"),
                    "accel_x": _to_g(sample.get("accel_x_ms2")),
                    "accel_y": _to_g(sample.get("accel_y_ms2")),
                    "accel_z": _to_g(sample.get("accel_z_ms2")),
                    "acceleration_g": _numeric(sample.get("acceleration_g")),
                    "accelerometer_accuracy": sample.get("accelerometer_accuracy"),
                    "gyro_x": _numeric(sample.get("gyro_x_rad_s")),
                    "gyro_y": _numeric(sample.get("gyro_y_rad_s")),
                    "gyro_z": _numeric(sample.get("gyro_z_rad_s")),
                    "gyro_magnitude": _numeric(
                        sample.get("gyro_magnitude_rad_s")
                    ),
                    "gyro_timestamp": _iso_timestamp(
                        sample.get("gyro_timestamp_ms")
                    ),
                    "gyroscope_accuracy": sample.get("gyroscope_accuracy"),
                    "step_count": _numeric(sample.get("step_count")),
                    "step_detected": sample.get("step_detected"),
                    "off_body": sample.get("off_body"),
                    "screen_interactive": sample.get("screen_interactive"),
                })

                sensor_rows += 1

        print(
            f"Sensor sessions: {session_number}/{len(sessions)} | "
            f"rows written: {sensor_rows:,}"
        )

ema_rows = 0

with ema_path.open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=EMA_COLUMNS)
    writer.writeheader()

    for ema_doc in paged_docs(participant_ref.collection("ema_events")):
        event = ema_doc.to_dict() or {}

        writer.writerow({
            "participant_id": PARTICIPANT_ID,
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
            "source": event.get("source"),
            "response_device": event.get("response_device"),
            "trigger_reason": event.get("trigger_reason"),
            "note": event.get("note"),
            "trigger_probability": event.get("trigger_probability"),
            "model_version": event.get("model_version"),
            "model_threshold": event.get("model_threshold"),
            "window_start": _iso_timestamp(event.get("window_start_ms")),
            "window_end": _iso_timestamp(event.get("window_end_ms")),
            "response_delay_ms": event.get("response_delay_ms"),
        })

        ema_rows += 1

sleep_rows = 0

with sleep_path.open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=SLEEP_COLUMNS)
    writer.writeheader()

    for sleep_doc in paged_docs(participant_ref.collection("sleep_sessions")):
        sleep = sleep_doc.to_dict() or {}

        writer.writerow({
            "participant_id": PARTICIPANT_ID,
            "sleep_session_id": sleep.get("sleep_session_id", sleep_doc.id),
            "status": sleep.get("status"),
            "recording_start": _iso_timestamp(sleep.get("recording_start_ms")),
            "recording_end": _iso_timestamp(sleep.get("recording_end_ms")),
            "reported_bedtime": _iso_timestamp(sleep.get("reported_bedtime_ms")),
            "reported_sleep_onset": _iso_timestamp(
                sleep.get("reported_sleep_onset_ms")
            ),
            "reported_wake": _iso_timestamp(sleep.get("reported_wake_ms")),
            "predicted_sleep_onset": _iso_timestamp(
                sleep.get("predicted_sleep_onset_ms")
            ),
            "predicted_wake": _iso_timestamp(sleep.get("predicted_wake_ms")),
            "estimated_time_in_bed_minutes": sleep.get(
                "estimated_time_in_bed_minutes"
            ),
            "estimated_total_sleep_minutes": sleep.get(
                "estimated_total_sleep_minutes"
            ),
            "estimated_waso_minutes": sleep.get("estimated_waso_minutes"),
            "estimated_sleep_efficiency": sleep.get(
                "estimated_sleep_efficiency"
            ),
            "estimated_awakenings": sleep.get("estimated_awakenings"),
            "overnight_mean_hr": sleep.get("overnight_mean_hr"),
            "overnight_movement_std_g": sleep.get("overnight_movement_std_g"),
            "sleep_estimate_confidence": sleep.get("sleep_estimate_confidence"),
            "sleep_quality": sleep.get("sleep_quality"),
            "rested_score": sleep.get("rested_score"),
            "reported_awakenings": sleep.get("reported_awakenings"),
            "watch_removed": sleep.get("watch_removed"),
            "valid_epoch_count": sleep.get("valid_epoch_count"),
            "total_epoch_count": sleep.get("total_epoch_count"),
            "sleep_estimator_version": sleep.get("sleep_estimator_version"),
            "schema_version": sleep.get("schema_version"),
        })

        sleep_rows += 1

print()
print("EXPORT COMPLETE")
print(f"Sensor rows: {sensor_rows:,}")
print(f"EMA responses: {ema_rows:,}")
print(f"Sleep sessions: {sleep_rows:,}")
print(f"Output: {output.resolve()}")


