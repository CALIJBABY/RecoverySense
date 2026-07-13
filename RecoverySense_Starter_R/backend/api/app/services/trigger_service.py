from math import sqrt
from app.models.schemas import SensorReadingIn, TriggerDecision


def evaluate_trigger(reading: SensorReadingIn) -> TriggerDecision:
    accel_mag = sqrt(reading.accel_x**2 + reading.accel_y**2 + reading.accel_z**2)

    if reading.heart_rate >= 100 and accel_mag >= 1.5:
        return TriggerDecision(
            should_trigger_ema=True,
            reason="Elevated heart rate and movement detected.",
        )

    if reading.heart_rate >= 110:
        return TriggerDecision(
            should_trigger_ema=True,
            reason="Elevated heart rate detected.",
        )

    return TriggerDecision(
        should_trigger_ema=False,
        reason="No rule-based EMA trigger.",
    )
