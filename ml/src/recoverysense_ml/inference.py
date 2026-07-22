from __future__ import annotations

from collections import defaultdict, deque
from pathlib import Path
from typing import Any

import joblib
import pandas as pd

from .features import extract_window_features
from .preprocessing import prepare_sensor_data


class RecoverySensePredictor:
    """Load a trained bundle and score complete sensor windows."""

    def __init__(self, model_path: str | Path):
        self.model_path = Path(model_path)
        if not self.model_path.exists():
            raise FileNotFoundError(f"Model bundle not found: {self.model_path}")
        self.bundle: dict[str, Any] = joblib.load(self.model_path)
        self.pipeline = self.bundle["pipeline"]
        self.feature_columns: list[str] = self.bundle["feature_columns"]
        self.threshold = float(self.bundle["probability_threshold"])
        self.config: dict[str, Any] = self.bundle["config"]

    def predict_window(self, raw_window: pd.DataFrame) -> dict[str, Any]:
        processed = prepare_sensor_data(raw_window, self.config)
        if processed.empty:
            raise ValueError("The supplied window has no usable samples.")
        features = extract_window_features(processed, self.config)
        feature_frame = pd.DataFrame([{column: features.get(column, 0.0) for column in self.feature_columns}])
        probability = float(self.pipeline.predict_proba(feature_frame)[0, 1])
        return {
            "probability": probability,
            "threshold": self.threshold,
            "should_trigger_ema": probability >= self.threshold,
            "model_path": str(self.model_path),
        }


class StreamingInferenceEngine:
    """Maintain per-participant buffers and score each completed stride."""

    def __init__(self, predictor: RecoverySensePredictor):
        self.predictor = predictor
        self.config = predictor.config
        rate = float(self.config["preprocessing"]["sampling_rate_hz"])
        window_seconds = float(self.config["windowing"]["window_seconds"])
        stride_seconds = float(self.config["windowing"]["stride_seconds"])
        self.maximum_samples = int(round(rate * window_seconds * 1.5))
        self.stride_samples = max(1, int(round(rate * stride_seconds)))
        self.buffers: dict[str, deque[dict[str, Any]]] = defaultdict(
            lambda: deque(maxlen=self.maximum_samples)
        )
        self.samples_since_score: dict[str, int] = defaultdict(int)
        self.last_trigger_time: dict[str, pd.Timestamp] = {}

    def add_reading(self, reading: dict[str, Any]) -> dict[str, Any]:
        participant = str(reading.get("participant_id", "demo-participant"))
        self.buffers[participant].append(reading)
        self.samples_since_score[participant] += 1

        rate = float(self.config["preprocessing"]["sampling_rate_hz"])
        required = int(round(rate * float(self.config["windowing"]["window_seconds"])))
        if len(self.buffers[participant]) < required:
            return {
                "ready": False,
                "buffered_samples": len(self.buffers[participant]),
                "required_samples": required,
            }
        if self.samples_since_score[participant] < self.stride_samples:
            return {
                "ready": False,
                "buffered_samples": len(self.buffers[participant]),
                "required_samples": required,
            }

        self.samples_since_score[participant] = 0
        raw_window = pd.DataFrame(list(self.buffers[participant])[-required:])
        result = self.predictor.predict_window(raw_window)
        result["ready"] = True

        now = pd.to_datetime(reading["timestamp"], utc=True)
        cooldown = float(self.config["inference"]["minimum_seconds_between_ema_triggers"])
        last_trigger = self.last_trigger_time.get(participant)
        cooldown_active = last_trigger is not None and (now - last_trigger).total_seconds() < cooldown
        result["cooldown_active"] = cooldown_active
        result["should_trigger_ema"] = bool(result["should_trigger_ema"] and not cooldown_active)
        if result["should_trigger_ema"]:
            self.last_trigger_time[participant] = now
        return result
