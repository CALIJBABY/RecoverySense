from __future__ import annotations

from pathlib import Path

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.models.schemas import EmaAnswerIn, SensorReadingIn
from app.services.prototype_api_guard import (
    prototype_api_enabled,
    require_prototype_api_enabled,
)


def test_prototype_api_is_disabled_by_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("RECOVERYSENSE_ENABLE_PROTOTYPE_API", raising=False)
    assert prototype_api_enabled() is False
    with pytest.raises(HTTPException) as error:
        require_prototype_api_enabled()
    assert error.value.status_code == 503


def test_prototype_api_requires_explicit_opt_in(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("RECOVERYSENSE_ENABLE_PROTOTYPE_API", "true")
    assert prototype_api_enabled() is True
    require_prototype_api_enabled()


def test_ema_schema_enforces_zero_to_ten() -> None:
    response = EmaAnswerIn(
        participant_id="participant-1",
        timestamp="2026-08-10T12:00:00Z",
        craving_score=7,
        response_device="watch",
    )
    assert response.craving_score == 7
    with pytest.raises(ValidationError):
        EmaAnswerIn(
            participant_id="participant-1",
            timestamp="2026-08-10T12:00:00Z",
            craving_score=11,
        )


def test_sensor_schema_preserves_sleep_context_and_rejects_unknown_fields() -> None:
    reading = SensorReadingIn(
        participant_id="participant-1",
        session_id="session-1",
        timestamp="2026-08-10T12:00:00Z",
        heart_rate=72,
        accel_x=0.1,
        accel_y=0.2,
        accel_z=9.8,
        prior_sleep_duration_minutes=420,
    )
    assert reading.prior_sleep_duration_minutes == 420
    with pytest.raises(ValidationError):
        SensorReadingIn(
            participant_id="participant-1",
            session_id="session-1",
            timestamp="2026-08-10T12:00:00Z",
            heart_rate=72,
            accel_x=0.1,
            accel_y=0.2,
            accel_z=9.8,
            unexpected_field="silent schema drift",
        )


def test_trigger_decision_accepts_interpretable_tree_contributors() -> None:
    from app.models.schemas import TriggerDecision

    decision = TriggerDecision(
        should_trigger_ema=False,
        reason="Below threshold",
        probability=0.42,
        model_ready=True,
        window_ready=True,
        model_name="random_forest",
        model_version="0.5.1",
        interpretability_model="decision_tree",
        interpretability_method="decision_tree_path_probability_delta",
        interpretability_probability=0.39,
        top_contributors=[
            {
                "feature": "hr_activation_mean",
                "display_name": "Heart rate above your recent baseline",
                "contribution": 0.12,
                "value": 8.5,
                "direction": "increasing",
            }
        ],
    )
    assert decision.top_contributors[0].contribution == 0.12
    assert decision.interpretability_model == "decision_tree"


def test_prediction_persistence_is_opt_in(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.models.schemas import TriggerDecision
    from app.services.prediction_record_service import persist_risk_prediction_if_enabled

    monkeypatch.delenv("RECOVERYSENSE_PERSIST_RISK_PREDICTIONS", raising=False)
    reading = SensorReadingIn(
        participant_id="participant-1",
        session_id="session-1",
        timestamp="2026-08-10T12:00:00Z",
        heart_rate=72,
        accel_x=0.1,
        accel_y=0.2,
        accel_z=9.8,
    )
    decision = TriggerDecision(
        should_trigger_ema=False,
        reason="test",
        probability=0.2,
        model_ready=True,
        window_ready=True,
    )
    # If persistence were not opt-in, this would attempt Firebase initialization.
    persist_risk_prediction_if_enabled(reading, decision)


def test_sensor_schema_accepts_bounded_timezone_offset() -> None:
    reading = SensorReadingIn(
        participant_id="participant-1",
        session_id="session-1",
        timestamp="2026-08-10T12:00:00Z",
        heart_rate=72,
        accel_x=0.1,
        accel_y=0.2,
        accel_z=9.8,
        timezone_offset_minutes=-420,
    )
    assert reading.timezone_offset_minutes == -420
    with pytest.raises(ValidationError):
        SensorReadingIn(
            participant_id="participant-1",
            session_id="session-1",
            timestamp="2026-08-10T12:00:00Z",
            heart_rate=72,
            accel_x=0.1,
            accel_y=0.2,
            accel_z=9.8,
            timezone_offset_minutes=900,
        )


def test_persisted_prediction_source_requires_dashboard_provenance_flags() -> None:
    source = Path(
        __file__
    ).resolve().parents[1] / "app" / "services" / "prediction_record_service.py"
    text = source.read_text(encoding="utf-8")
    assert '"participant_display_allowed": True' in text
    assert '"demo_only": False' in text
    assert '"prediction_basis": "sensor_window_plus_prior_context"' in text
    assert '"current_ema_direct_input": False' in text
    assert '"schema_version": 2' in text


def test_prediction_input_modalities_reflect_available_sensor_context() -> None:
    from app.services.prediction_record_service import _input_modalities

    reading = SensorReadingIn(
        participant_id="participant-1",
        session_id="session-1",
        timestamp="2026-08-11T12:00:00Z",
        heart_rate=72,
        heart_rate_valid=True,
        accel_x=0.1,
        accel_y=0.2,
        accel_z=9.8,
        gyro_x=0.01,
        gyro_y=0.02,
        gyro_z=0.03,
        step_count=1200,
        sleep_log_available=1,
    )
    modalities = _input_modalities(reading)
    assert modalities == [
        "accelerometer",
        "time_context",
        "heart_rate",
        "gyroscope",
        "steps",
        "prior_sleep_context",
    ]


def test_invalid_heart_rate_is_not_declared_as_model_input() -> None:
    from app.services.prediction_record_service import _input_modalities

    reading = SensorReadingIn(
        participant_id="participant-1",
        session_id="session-1",
        timestamp="2026-08-11T12:00:00Z",
        heart_rate=155,
        heart_rate_valid=False,
        accel_x=0.1,
        accel_y=0.2,
        accel_z=9.8,
    )
    assert "heart_rate" not in _input_modalities(reading)


def test_sensor_schema_accepts_heart_rate_quality_provenance() -> None:
    reading = SensorReadingIn(
        participant_id="participant-1",
        session_id="session-1",
        timestamp="2026-08-11T12:00:00Z",
        heart_rate=72,
        raw_heart_rate=72,
        heart_rate_valid=True,
        heart_rate_quality_code=0,
        heart_rate_outlier_flag=False,
        heart_rate_age_ms=500,
        off_body=0,
        accel_x=0.1,
        accel_y=0.2,
        accel_z=9.8,
    )
    assert reading.heart_rate_valid is True
    assert reading.raw_heart_rate == 72
    with pytest.raises(ValidationError):
        SensorReadingIn(
            participant_id="participant-1",
            session_id="session-1",
            timestamp="2026-08-11T12:00:00Z",
            heart_rate=72,
            raw_heart_rate=72,
            heart_rate_valid=True,
            heart_rate_quality_code=99,
            accel_x=0.1,
            accel_y=0.2,
            accel_z=9.8,
        )


def test_engineering_rule_fallback_refuses_invalid_heart_rate(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services.trigger_service import _rule_based_fallback

    monkeypatch.setenv("RECOVERYSENSE_ENABLE_RULE_TRIGGER", "true")
    reading = SensorReadingIn(
        participant_id="participant-1",
        session_id="session-1",
        timestamp="2026-08-11T12:00:00Z",
        heart_rate=None,
        raw_heart_rate=155,
        heart_rate_valid=False,
        heart_rate_quality_code=3,
        off_body=1,
        accel_x=0.1,
        accel_y=0.2,
        accel_z=9.8,
    )
    decision = _rule_based_fallback(reading)
    assert decision.should_trigger_ema is False
    assert "no analysis-ready heart-rate" in decision.reason
