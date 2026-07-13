from fastapi import APIRouter
from app.models.schemas import SensorReadingIn, TriggerDecision
from app.services.trigger_service import evaluate_trigger

router = APIRouter()

# Temporary in-memory store for early testing only.
SENSOR_READINGS: list[SensorReadingIn] = []


@router.post("/reading", response_model=TriggerDecision)
def create_sensor_reading(reading: SensorReadingIn) -> TriggerDecision:
    SENSOR_READINGS.append(reading)
    return evaluate_trigger(reading)


@router.get("/latest", response_model=SensorReadingIn | None)
def get_latest_reading() -> SensorReadingIn | None:
    if not SENSOR_READINGS:
        return None
    return SENSOR_READINGS[-1]
