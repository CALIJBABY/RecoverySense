from __future__ import annotations

import os
from datetime import timezone
from typing import Any

from app.models.schemas import SensorReadingIn, TriggerDecision


def _enabled() -> bool:
    value = os.getenv("RECOVERYSENSE_PERSIST_RISK_PREDICTIONS", "false")
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _input_modalities(reading: SensorReadingIn) -> list[str]:
    """Describe the actual inputs available for this scored sensor window."""
    modalities = ["accelerometer", "time_context"]
    if reading.heart_rate is not None and reading.heart_rate_valid is not False:
        modalities.append("heart_rate")
    if any(
        value is not None
        for value in (reading.gyro_x, reading.gyro_y, reading.gyro_z)
    ):
        modalities.append("gyroscope")
    if reading.step_count is not None or reading.step_detected is not None:
        modalities.append("steps")
    if reading.sleep_log_available == 1:
        modalities.append("prior_sleep_context")
    return modalities


def persist_risk_prediction_if_enabled(
    reading: SensorReadingIn,
    decision: TriggerDecision,
) -> None:
    """Persist a model-ready prediction for the phone dashboard when enabled.

    This is opt-in because the prototype API is not the production storage
    boundary yet. When enabled, a write failure is intentionally not swallowed:
    silent loss of model provenance would undermine research traceability.
    """
    if not _enabled() or not decision.model_ready or not decision.window_ready:
        return
    if decision.probability is None:
        return

    try:
        import firebase_admin
        from firebase_admin import firestore
    except ImportError as exc:  # pragma: no cover - environment-specific
        raise RuntimeError(
            "Prediction persistence is enabled but firebase-admin is unavailable."
        ) from exc

    if not firebase_admin._apps:
        firebase_admin.initialize_app()
    db = firestore.client()

    timestamp = reading.timestamp
    if timestamp.tzinfo is None:
        timestamp = timestamp.replace(tzinfo=timezone.utc)
    timestamp_ms = int(timestamp.astimezone(timezone.utc).timestamp() * 1000)

    payload: dict[str, Any] = {
        "participant_id": reading.participant_id,
        "session_id": reading.session_id,
        "timestamp_ms": timestamp_ms,
        "probability": decision.probability,
        "risk_probability": decision.probability,
        "threshold": decision.threshold,
        "should_trigger_ema": decision.should_trigger_ema,
        "model_name": decision.model_name,
        "model_version": decision.model_version,
        "interpretability_model": decision.interpretability_model,
        "interpretability_method": decision.interpretability_method,
        "interpretability_probability": decision.interpretability_probability,
        "top_contributors": [
            contributor.model_dump(mode="json") for contributor in decision.top_contributors
        ],
        # This provenance prevents the participant dashboard from displaying a
        # copied EMA value as if it were a sensor-model estimate. EMA remains the
        # outcome label used to train and validate the craving-risk model.
        "prediction_basis": "sensor_window_plus_prior_context",
        "input_modalities": _input_modalities(reading),
        "current_ema_direct_input": False,
        "ema_role": "training_and_validation_label",
        "sensor_window_end_ms": timestamp_ms,
        # The dashboard fails closed unless a real model record is explicitly
        # approved for participant display. Synthetic/demo bundles are already
        # blocked by ModelRuntime before reaching this persistence boundary.
        "participant_display_allowed": True,
        "demo_only": False,
        "created_at": firestore.SERVER_TIMESTAMP,
        "schema_version": 2,
    }
    document_id = f"{reading.session_id}_{timestamp_ms}"
    (
        db.collection("participants")
        .document(reading.participant_id)
        .collection("risk_predictions")
        .document(document_id)
        .set(payload, merge=True)
    )
