from __future__ import annotations

from collections import defaultdict, deque
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd

from .dataset import SLEEP_CONTEXT_FEATURES, _time_features
from .features import extract_window_features
from .explainability import decision_tree_path_contributions
from .preprocessing import prepare_sensor_data
from .ppg import extract_ppg_window_features, prepare_ppg_data


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
        self.model_name = str(self.bundle.get("model_name", "unknown"))
        self.model_version = str(self.bundle.get("framework_version", "unknown"))
        self.interpretability_pipeline = self.bundle.get("interpretability_pipeline")
        self.interpretability_model = str(
            self.bundle.get("interpretability_model", "decision_tree")
        )
        self.interpretability_method = str(
            self.bundle.get(
                "interpretability_method", "decision_tree_path_probability_delta"
            )
        )

    def predict_window(
        self,
        raw_window: pd.DataFrame,
        context_features: dict[str, float] | None = None,
        raw_ppg_window: pd.DataFrame | None = None,
    ) -> dict[str, Any]:
        processed = prepare_sensor_data(raw_window, self.config)
        if processed.empty:
            raise ValueError("The supplied window has no usable samples.")

        features = extract_window_features(processed, self.config)
        prepared_ppg = prepare_ppg_data(raw_ppg_window)
        features.update(
            extract_ppg_window_features(
                prepared_ppg,
                nominal_sampling_rate_hz=float(
                    self.config.get("ppg", {}).get("sampling_rate_hz", 25.0)
                ),
            )
        )
        timestamp_col = self.config["schema"]["timestamp_column"]
        first_timestamp = pd.to_datetime(
            processed[timestamp_col].iloc[0], utc=True, errors="coerce"
        )
        current_context = dict(context_features or {})
        timezone_offset_minutes = current_context.pop("timezone_offset_minutes", None)
        if pd.notna(first_timestamp):
            features.update(
                _time_features(first_timestamp, timezone_offset_minutes)
            )
        else:
            features.update(_time_features(pd.Timestamp("1970-01-01", tz="UTC"), None))
        # Missing sleep is explicit, not silently interpreted as a valid
        # zero-duration night. Numeric details stay NaN while availability and
        # staleness flags default to zero.
        for feature in SLEEP_CONTEXT_FEATURES:
            features.setdefault(feature, np.nan)
        features["sleep_log_available"] = 0.0
        features["sleep_log_stale"] = 0.0
        if current_context:
            features.update(current_context)

        feature_frame = pd.DataFrame(
            [
                {
                    column: features.get(column, np.nan)
                    for column in self.feature_columns
                }
            ]
        )
        probability = float(self.pipeline.predict_proba(feature_frame)[0, 1])
        explanation: dict[str, Any] | None = None
        if self.interpretability_pipeline is not None:
            explanation = decision_tree_path_contributions(
                self.interpretability_pipeline,
                feature_frame,
                top_k=3,
            )
        return {
            "probability": probability,
            "threshold": self.threshold,
            "should_trigger_ema": probability >= self.threshold,
            "model_path": str(self.model_path),
            "model_name": self.model_name,
            "model_version": self.model_version,
            "interpretability_model": self.interpretability_model,
            "interpretability_method": self.interpretability_method,
            "interpretability_probability": (
                float(explanation["leaf_probability"]) if explanation else None
            ),
            "top_contributors": (
                explanation["top_positive_contributors"] if explanation else []
            ),
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

    def add_reading(
        self,
        reading: dict[str, Any],
        context_features: dict[str, float] | None = None,
        raw_ppg_window: pd.DataFrame | None = None,
    ) -> dict[str, Any]:
        participant_value = reading.get("participant_id")
        if participant_value is None or not str(participant_value).strip():
            raise ValueError("Streaming inference requires a non-empty participant_id.")
        if "timestamp" not in reading:
            raise ValueError("Streaming inference requires a timestamp for every reading.")
        participant = str(participant_value).strip()
        self.buffers[participant].append(reading)
        self.samples_since_score[participant] += 1

        rate = float(self.config["preprocessing"]["sampling_rate_hz"])
        required = int(
            round(rate * float(self.config["windowing"]["window_seconds"]))
        )
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
        result = self.predictor.predict_window(
            raw_window,
            context_features,
            raw_ppg_window=raw_ppg_window,
        )
        result["ready"] = True

        now = pd.to_datetime(reading["timestamp"], utc=True)
        cooldown = float(
            self.config["inference"]["minimum_seconds_between_ema_triggers"]
        )
        last_trigger = self.last_trigger_time.get(participant)
        cooldown_active = (
            last_trigger is not None
            and (now - last_trigger).total_seconds() < cooldown
        )
        result["cooldown_active"] = cooldown_active
        result["should_trigger_ema"] = bool(
            result["should_trigger_ema"] and not cooldown_active
        )
        if result["should_trigger_ema"]:
            self.last_trigger_time[participant] = now
        return result
