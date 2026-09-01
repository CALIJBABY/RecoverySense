from fastapi import APIRouter, Depends

from app.models.schemas import ModelStatus, SensorReadingIn, TriggerDecision
from app.services.model_service import model_runtime
from app.services.prototype_api_guard import require_prototype_api_enabled
from app.services.prediction_record_service import persist_risk_prediction_if_enabled
from app.services.trigger_service import evaluate_trigger

router = APIRouter()

# Temporary in-memory store for isolated local engineering tests only.
SENSOR_READINGS: list[SensorReadingIn] = []


@router.post(
    "/reading",
    response_model=TriggerDecision,
    dependencies=[Depends(require_prototype_api_enabled)],
)
def create_sensor_reading(reading: SensorReadingIn) -> TriggerDecision:
    SENSOR_READINGS.append(reading)
    decision = evaluate_trigger(reading)
    persist_risk_prediction_if_enabled(reading, decision)
    return decision


@router.get(
    "/latest",
    response_model=SensorReadingIn | None,
    dependencies=[Depends(require_prototype_api_enabled)],
)
def get_latest_reading() -> SensorReadingIn | None:
    if not SENSOR_READINGS:
        return None
    return SENSOR_READINGS[-1]


@router.get("/model", response_model=ModelStatus)
def get_model_status() -> ModelStatus:
    detail = (
        "Model loaded and ready."
        if model_runtime.ready
        else (model_runtime.error or "Model unavailable.")
    )
    return ModelStatus(
        model_ready=model_runtime.ready,
        model_path=model_runtime.model_path.name,
        threshold=model_runtime.threshold,
        detail=detail,
    )


@router.post(
    "/model/reload",
    response_model=ModelStatus,
    dependencies=[Depends(require_prototype_api_enabled)],
)
def reload_model() -> ModelStatus:
    model_runtime.reload()
    return get_model_status()
