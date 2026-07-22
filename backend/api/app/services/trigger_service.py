from __future__ import annotations

from math import sqrt

from app.models.schemas import SensorReadingIn, TriggerDecision
from app.services.model_service import model_runtime


def _rule_based_fallback(reading: SensorReadingIn) -> TriggerDecision:
    accel_mag = sqrt(reading.accel_x**2 + reading.accel_y**2 + reading.accel_z**2)

    if reading.heart_rate >= 100 and accel_mag >= 1.5:
        return TriggerDecision(
            should_trigger_ema=True,
            reason="Fallback rule: elevated heart rate and movement detected.",
            model_ready=False,
            window_ready=True,
        )

    if reading.heart_rate >= 110:
        return TriggerDecision(
            should_trigger_ema=True,
            reason="Fallback rule: elevated heart rate detected.",
            model_ready=False,
            window_ready=True,
        )

    return TriggerDecision(
        should_trigger_ema=False,
        reason="Model unavailable; fallback rules did not trigger an EMA.",
        model_ready=False,
        window_ready=True,
    )


def evaluate_trigger(reading: SensorReadingIn) -> TriggerDecision:
    result = model_runtime.add_reading(reading.model_dump(mode="json"))
    if result is None:
        return _rule_based_fallback(reading)

    if not result.get("ready", False):
        return TriggerDecision(
            should_trigger_ema=False,
            reason="Collecting enough samples for the first 30-second model window.",
            threshold=model_runtime.threshold,
            model_ready=True,
            window_ready=False,
            buffered_samples=result.get("buffered_samples"),
            required_samples=result.get("required_samples"),
        )

    probability = float(result["probability"])
    should_trigger = bool(result["should_trigger_ema"])
    cooldown_active = bool(result.get("cooldown_active", False))
    if cooldown_active:
        reason = "Risk probability exceeded the threshold, but the EMA cooldown is active."
    elif should_trigger:
        reason = "Random Forest probability met or exceeded the EMA threshold."
    else:
        reason = "Random Forest probability remained below the EMA threshold."

    return TriggerDecision(
        should_trigger_ema=should_trigger,
        reason=reason,
        probability=probability,
        threshold=float(result["threshold"]),
        model_ready=True,
        window_ready=True,
        cooldown_active=cooldown_active,
    )
