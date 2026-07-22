from __future__ import annotations

from pathlib import Path
from threading import Lock

from recoverysense_ml import RecoverySensePredictor, StreamingInferenceEngine


REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_MODEL_PATH = REPOSITORY_ROOT / "ml" / "models" / "random_forest_bundle.joblib"


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
                self.engine = StreamingInferenceEngine(self.predictor)
                self.error = None
                return True
            except Exception as exc:  # API must remain available with fallback logic.
                self.predictor = None
                self.engine = None
                self.error = f"Unable to load model bundle: {exc}"
                return False

    def add_reading(self, reading: dict) -> dict | None:
        with self._lock:
            if self.engine is None:
                return None
            return self.engine.add_reading(reading)


model_runtime = ModelRuntime()
