from __future__ import annotations

import logging
from pathlib import Path
from threading import Lock

from recoverysense_ml import RecoverySensePredictor, StreamingInferenceEngine


REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
LOGGER = logging.getLogger(__name__)

DEFAULT_MODEL_PATH = REPOSITORY_ROOT / "ml" / "models" / "best_craving_model_bundle.joblib"


class ModelRuntime:
    """Thread-safe lazy model loader used by the FastAPI process."""

    def __init__(self, model_path: Path = DEFAULT_MODEL_PATH):
        self.model_path = model_path
        self.predictor: RecoverySensePredictor | None = None
        self.engine: StreamingInferenceEngine | None = None
        self.error: str | None = None
        self._lock = Lock()
        self.reload()

    @property
    def ready(self) -> bool:
        return self.engine is not None

    @property
    def threshold(self) -> float:
        return self.predictor.threshold if self.predictor is not None else 0.70

    def reload(self) -> bool:
        with self._lock:
            if not self.model_path.exists():
                self.predictor = None
                self.engine = None
                self.error = "Model bundle has not been trained yet."
                return False
            try:
                self.predictor = RecoverySensePredictor(self.model_path)
                if bool(getattr(self.predictor, "bundle", {}).get("demo_only", False)):
                    self.predictor = None
                    self.engine = None
                    self.error = (
                        "The available model was trained on synthetic demo data and is "
                        "disabled for participant EMA triggering."
                    )
                    return False
                self.engine = StreamingInferenceEngine(self.predictor)
                self.error = None
                return True
            except Exception:  # API must remain available with fallback logic.
                LOGGER.exception("Unable to load RecoverySense model bundle")
                self.predictor = None
                self.engine = None
                self.error = "Model bundle could not be loaded."
                return False

    def add_reading(self, reading: dict) -> dict | None:
        with self._lock:
            if self.engine is None:
                return None
            context_names = {
                "sleep_log_available",
                "sleep_log_stale",
                "sleep_log_age_hours",
                "prior_sleep_duration_minutes",
                "prior_sleep_efficiency",
                "prior_sleep_awakenings",
                "prior_sleep_waso_minutes",
                "prior_sleep_overnight_mean_hr",
                "prior_sleep_overnight_movement_std_g",
                "prior_sleep_estimate_confidence",
                "prior_sleep_quality",
                "prior_rested_score",
                "prior_sleep_watch_removed",
                "timezone_offset_minutes",
            }
            context = {
                name: value
                for name, value in reading.items()
                if name in context_names and value is not None
            }
            return self.engine.add_reading(reading, context_features=context)


model_runtime = ModelRuntime()
