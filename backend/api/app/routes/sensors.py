from fastapi import APIRouter

from app.models.schemas import ModelStatus, SensorReadingIn, TriggerDecision
from app.services.model_service import model_runtime
from app.services.trigger_service import evaluate_trigger

router = APIRouter()

# Temporary in-memory store for prototype testing only. Replace with Firestore or
# another persistent data store before collecting research data.
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


@router.get("/model", response_model=ModelStatus)
def get_model_status() -> ModelStatus:
    detail = "Model loaded and ready." if model_runtime.ready else (model_runtime.error or "Model unavailable.")
    return ModelStatus(
        model_ready=model_runtime.ready,
        model_path=str(model_runtime.model_path),
        threshold=model_runtime.threshold,
        detail=detail,
    )


@router.post("/model/reload", response_model=ModelStatus)
def reload_model() -> ModelStatus:
    model_runtime.reload()
    return get_model_status()
