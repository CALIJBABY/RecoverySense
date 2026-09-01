from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    balanced_accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import GroupKFold, GroupShuffleSplit, cross_validate
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.tree import DecisionTreeClassifier

from .features import extract_window_features
from .preprocessing import prepare_sensor_data
from .ppg import ppg_features_for_interval, prepare_ppg_data


SLEEP_METADATA_COLUMNS = {
    "participant_id",
    "sleep_session_id",
    "segment_id",
    "epoch_start",
    "epoch_end",
    "label_source",
    "label",
}


def _normalize_sleep_sessions(frame: pd.DataFrame) -> pd.DataFrame:
    required = {"participant_id", "sleep_session_id"}
    missing = required.difference(frame.columns)
    if missing:
        raise ValueError(
            "Sleep session CSV is missing required columns: " + ", ".join(sorted(missing))
        )
    result = frame.copy()
    for column in (
        "recording_start",
        "recording_end",
        "reported_sleep_onset",
        "reported_wake",
        "predicted_sleep_onset",
        "predicted_wake",
    ):
        if column in result.columns:
            result[column] = pd.to_datetime(
                result[column], utc=True, errors="coerce", format="mixed"
            )

    if "status" in result.columns:
        status = result["status"].fillna("").astype(str).str.lower()
        result = result[status.isin({"confirmed", "complete", "completed"})]

    if "reported_sleep_onset" not in result.columns or "reported_wake" not in result.columns:
        raise ValueError(
            "Sleep session CSV needs reported_sleep_onset and reported_wake for weak sleep/wake labels."
        )
    result = result.dropna(
        subset=["participant_id", "sleep_session_id", "reported_sleep_onset", "reported_wake"]
    )
    result = result[result["reported_wake"] > result["reported_sleep_onset"]]
    return result.drop_duplicates(
        ["participant_id", "sleep_session_id"], keep="last"
    ).reset_index(drop=True)


def _time_features(timestamp: pd.Timestamp) -> dict[str, float]:
    seconds = timestamp.hour * 3600 + timestamp.minute * 60 + timestamp.second
    fraction = seconds / 86_400.0
    return {
        "time_of_day_sin": float(np.sin(2 * np.pi * fraction)),
        "time_of_day_cos": float(np.cos(2 * np.pi * fraction)),
    }


def _add_sequence_features(dataset: pd.DataFrame) -> pd.DataFrame:
    ordered = dataset.sort_values(
        ["participant_id", "sleep_session_id", "epoch_start"]
    ).copy()
    group_keys = ["participant_id", "sleep_session_id"]
    grouped = ordered.groupby(group_keys, sort=False)

    for source, prefix in (
        ("dynamic_accel_mag_std", "movement"),
        ("stillness_fraction", "stillness"),
        ("gyro_mag_mean", "rotation"),
        ("hr_mean", "heart_rate"),
    ):
        if source not in ordered.columns:
            continue
        ordered[f"previous_{prefix}"] = grouped[source].shift(1)
        ordered[f"next_{prefix}"] = grouped[source].shift(-1)
        ordered[f"rolling_5_{prefix}_mean"] = grouped[source].transform(
            lambda values: values.rolling(5, center=True, min_periods=1).mean()
        )

    if "stillness_fraction" in ordered.columns:
        low_motion = (ordered["stillness_fraction"] >= 0.90).astype(float)
        ordered["low_motion_epoch"] = low_motion
        ordered["rolling_5_low_motion_fraction"] = low_motion.groupby(
            [ordered[key] for key in group_keys]
        ).transform(lambda values: values.rolling(5, center=True, min_periods=1).mean())
    return ordered.reset_index(drop=True)


def build_sleep_epoch_dataset(
    sensor_frame: pd.DataFrame,
    sleep_sessions_frame: pd.DataFrame,
    config: dict[str, Any],
    ppg_frame: pd.DataFrame | None = None,
) -> pd.DataFrame:
    """Create 30-second binary sleep/wake epochs from watch data and user corrections.

    The user-confirmed sleep onset and final wake time are weak labels suitable
    for an initial prototype. They are not EEG/PSG sleep-stage labels.
    """
    sleep_sessions = _normalize_sleep_sessions(sleep_sessions_frame)
    ppg = prepare_ppg_data(ppg_frame)
    sensor = sensor_frame.copy()
    if "recording_mode" in sensor.columns:
        sensor = sensor[sensor["recording_mode"].fillna("").astype(str) == "sleep"]
    if "sleep_session_id" not in sensor.columns:
        raise ValueError(
            "Sensor CSV needs sleep_session_id. Export new overnight batches before training the sleep model."
        )
    sensor = sensor[sensor["sleep_session_id"].notna()].copy()
    if sensor.empty:
        raise ValueError("No overnight sleep-mode sensor rows were found.")

    schema = config["schema"]
    participant_col = schema["participant_column"]
    session_col = schema["session_column"]
    timestamp_col = schema["timestamp_column"]
    sensor[session_col] = sensor["sleep_session_id"].astype(str)
    processed = prepare_sensor_data(sensor, config)

    labels = sleep_sessions.set_index(["participant_id", "sleep_session_id"])
    rate = float(config["preprocessing"]["sampling_rate_hz"])
    epoch_seconds = float(config.get("sleep_model", {}).get("epoch_seconds", 30.0))
    epoch_samples = max(1, int(round(epoch_seconds * rate)))
    minimum_samples = int(
        round(
            epoch_samples
            * float(config.get("sleep_model", {}).get("minimum_epoch_coverage", 0.60))
        )
    )
    rows: list[dict[str, Any]] = []

    for (participant_id, segment_id), group in processed.groupby(
        [participant_col, session_col], sort=False
    ):
        sleep_session_id = str(segment_id).split("-segment-", 1)[0]
        key = (str(participant_id), sleep_session_id)
        if key not in labels.index:
            continue
        session = labels.loc[key]
        if isinstance(session, pd.DataFrame):
            session = session.iloc[-1]
        onset = session["reported_sleep_onset"]
        wake = session["reported_wake"]
        recording_start = session.get("recording_start")
        if pd.isna(recording_start):
            recording_start = group[timestamp_col].min()

        group = group.sort_values(timestamp_col).reset_index(drop=True)
        for start in range(0, len(group), epoch_samples):
            window = group.iloc[start : start + epoch_samples]
            if len(window) < minimum_samples:
                continue
            missing = float(window["row_missing_fraction_before_fill"].mean())
            if missing > 1.0 - float(
                config.get("sleep_model", {}).get("minimum_epoch_coverage", 0.60)
            ):
                continue
            epoch_start = window[timestamp_col].iloc[0]
            epoch_end = window[timestamp_col].iloc[-1]
            midpoint = epoch_start + (epoch_end - epoch_start) / 2
            label = int(onset <= midpoint < wake)
            features = extract_window_features(window, config)
            features.update(_time_features(epoch_start))
            features.update(
                ppg_features_for_interval(
                    ppg,
                    str(participant_id),
                    epoch_start,
                    epoch_end,
                    session_id=sleep_session_id,
                    nominal_sampling_rate_hz=float(
                        config.get("ppg", {}).get("sampling_rate_hz", 25.0)
                    ),
                )
            )
            features["epoch_coverage"] = float(len(window) / epoch_samples)
            features["minutes_since_recording_start"] = float(
                (epoch_start - recording_start).total_seconds() / 60.0
            )
            rows.append(
                {
                    "participant_id": str(participant_id),
                    "sleep_session_id": sleep_session_id,
                    "segment_id": str(segment_id),
                    "epoch_start": epoch_start,
                    "epoch_end": epoch_end,
                    "label_source": "user_confirmed_sleep_interval",
                    "label": label,
                    **features,
                }
            )

    if not rows:
        raise ValueError(
            "No sleep epochs could be aligned with confirmed sleep sessions. Check IDs and timestamps."
        )
    dataset = _add_sequence_features(pd.DataFrame(rows))
    if dataset["label"].nunique() < 2:
        raise ValueError(
            "The sleep dataset contains only one class. Record awake time before sleep onset or after final wake."
        )
    return dataset


def build_sleep_dataset_from_config(config: dict[str, Any]) -> pd.DataFrame:
    sensor_path = Path(config["paths"]["raw_sensor_csv"])
    sleep_path = Path(config["paths"]["sleep_sessions_csv"])
    if not sensor_path.exists():
        raise FileNotFoundError(f"Missing sensor data: {sensor_path}")
    if not sleep_path.exists():
        raise FileNotFoundError(f"Missing sleep session data: {sleep_path}")
    ppg_path = Path(config["paths"].get("raw_ppg_csv", "ml/data/raw/raw_ppg.csv"))
    ppg_frame = pd.read_csv(ppg_path, low_memory=False) if ppg_path.exists() else None
    dataset = build_sleep_epoch_dataset(
        pd.read_csv(sensor_path, low_memory=False),
        pd.read_csv(sleep_path),
        config,
        ppg_frame=ppg_frame,
    )
    output = Path(config["paths"]["processed_sleep_epochs_csv"])
    output.parent.mkdir(parents=True, exist_ok=True)
    dataset.to_csv(output, index=False)
    return dataset


def _preprocessor(feature_columns: list[str]) -> ColumnTransformer:
    return ColumnTransformer(
        [("numeric", Pipeline([
            ("imputer", SimpleImputer(strategy="median", keep_empty_features=True)),
            ("scaler", StandardScaler()),
        ]), feature_columns)],
        remainder="drop",
        verbose_feature_names_out=False,
    )


def _candidate_models(config: dict[str, Any]) -> dict[str, Any]:
    cfg = config.get("sleep_model", {})
    seed = int(config["project"]["random_seed"])
    return {
        "decision_tree": DecisionTreeClassifier(
            max_depth=int(cfg.get("decision_tree_max_depth", 8)),
            min_samples_leaf=int(cfg.get("min_samples_leaf", 3)),
            class_weight="balanced",
            random_state=seed,
        ),
        "random_forest": RandomForestClassifier(
            n_estimators=int(cfg.get("n_estimators", 300)),
            max_depth=cfg.get("max_depth"),
            min_samples_leaf=int(cfg.get("min_samples_leaf", 3)),
            class_weight="balanced_subsample",
            random_state=seed,
            n_jobs=1,
        ),
        "gradient_boosting": GradientBoostingClassifier(
            n_estimators=int(cfg.get("gradient_boosting_estimators", 150)),
            learning_rate=float(cfg.get("gradient_boosting_learning_rate", 0.05)),
            max_depth=int(cfg.get("gradient_boosting_max_depth", 3)),
            random_state=seed,
        ),
        "logistic_regression": LogisticRegression(
            max_iter=2000,
            class_weight="balanced",
            random_state=seed,
        ),
    }


def _split(dataset: pd.DataFrame, config: dict[str, Any]) -> tuple[np.ndarray, np.ndarray, str]:
    groups = dataset["participant_id"].astype(str)
    y = dataset["label"].astype(int)
    cfg = config.get("sleep_model", {})
    fraction = float(cfg.get("test_fraction", 0.20))
    seed = int(config["project"]["random_seed"])
    if groups.nunique() >= 2:
        splitter = GroupShuffleSplit(n_splits=100, test_size=fraction, random_state=seed)
        for train, test in splitter.split(dataset, y, groups):
            if y.iloc[train].nunique() == 2 and y.iloc[test].nunique() == 2:
                return train, test, "participant-grouped"
    # A session-grouped fallback still avoids mixing epochs from the same night.
    session_groups = (
        dataset["participant_id"].astype(str)
        + "/"
        + dataset["sleep_session_id"].astype(str)
    )
    if session_groups.nunique() >= 2:
        splitter = GroupShuffleSplit(n_splits=100, test_size=fraction, random_state=seed)
        for train, test in splitter.split(dataset, y, session_groups):
            if y.iloc[train].nunique() == 2 and y.iloc[test].nunique() == 2:
                return train, test, "sleep-session-grouped-fallback"
    raise ValueError(
        "Unable to create a two-class held-out split. Collect more participants and nights."
    )


def _smooth_predictions(
    prediction_frame: pd.DataFrame, probability_column: str, threshold: float, window: int
) -> np.ndarray:
    ordered = prediction_frame.sort_values(
        ["participant_id", "sleep_session_id", "epoch_start"]
    ).copy()
    raw = (ordered[probability_column] >= threshold).astype(float)
    smoothed = raw.groupby(
        [ordered["participant_id"], ordered["sleep_session_id"]]
    ).transform(lambda values: values.rolling(window, center=True, min_periods=1).mean())
    ordered["_smoothed"] = (smoothed >= 0.5).astype(int)
    return ordered.sort_index()["_smoothed"].to_numpy(int)


def _metrics(y_true: pd.Series, probabilities: np.ndarray, predictions: np.ndarray) -> dict[str, Any]:
    return {
        "samples": int(len(y_true)),
        "sleep_samples": int(np.sum(y_true)),
        "accuracy": float(accuracy_score(y_true, predictions)),
        "balanced_accuracy": float(balanced_accuracy_score(y_true, predictions)),
        "precision": float(precision_score(y_true, predictions, zero_division=0)),
        "recall": float(recall_score(y_true, predictions, zero_division=0)),
        "f1": float(f1_score(y_true, predictions, zero_division=0)),
        "roc_auc": float(roc_auc_score(y_true, probabilities)) if y_true.nunique() > 1 else None,
        "average_precision": float(average_precision_score(y_true, probabilities)) if y_true.nunique() > 1 else None,
        "confusion_matrix": confusion_matrix(y_true, predictions, labels=[0, 1]).tolist(),
    }


def train_sleep_from_dataframe(
    dataset: pd.DataFrame, config: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, Any]]:
    feature_columns = [c for c in dataset.columns if c not in SLEEP_METADATA_COLUMNS]
    x = dataset[feature_columns].apply(pd.to_numeric, errors="coerce")
    y = dataset["label"].astype(int)
    train_idx, test_idx, split_method = _split(dataset, config)
    x_train, x_test = x.iloc[train_idx], x.iloc[test_idx]
    y_train, y_test = y.iloc[train_idx], y.iloc[test_idx]
    train_groups = dataset.iloc[train_idx]["participant_id"].astype(str)

    cfg = config.get("sleep_model", {})
    threshold = float(cfg.get("probability_threshold", 0.50))
    smoothing_window = max(1, int(cfg.get("temporal_smoothing_epochs", 5)))
    if smoothing_window % 2 == 0:
        smoothing_window += 1

    results: dict[str, Any] = {}
    fitted: dict[str, Pipeline] = {}
    probabilities_by_model: dict[str, np.ndarray] = {}
    prediction_base = dataset.iloc[test_idx][
        ["participant_id", "sleep_session_id", "epoch_start", "epoch_end", "label"]
    ].copy()

    for name, classifier in _candidate_models(config).items():
        pipeline = Pipeline(
            [("preprocess", _preprocessor(feature_columns)), ("classifier", classifier)]
        )
        pipeline.fit(x_train, y_train)
        probabilities = pipeline.predict_proba(x_test)[:, 1]
        prediction_base[f"{name}_probability"] = probabilities
        smoothed = _smooth_predictions(
            prediction_base, f"{name}_probability", threshold, smoothing_window
        )
        model_metrics = _metrics(y_test, probabilities, smoothed)

        folds = min(int(cfg.get("cross_validation_folds", 3)), train_groups.nunique())
        cv_payload = None
        if folds >= 2:
            scores = cross_validate(
                pipeline,
                x_train,
                y_train,
                groups=train_groups,
                cv=GroupKFold(n_splits=folds),
                scoring={"balanced_accuracy": "balanced_accuracy", "f1": "f1"},
                n_jobs=1,
                error_score=np.nan,
            )
            cv_payload = {
                "folds": folds,
                "balanced_accuracy": {
                    "mean": float(np.nanmean(scores["test_balanced_accuracy"])),
                    "std": float(np.nanstd(scores["test_balanced_accuracy"])),
                },
                "f1": {
                    "mean": float(np.nanmean(scores["test_f1"])),
                    "std": float(np.nanstd(scores["test_f1"])),
                },
            }
        results[name] = {"test": model_metrics, "cross_validation": cv_payload}
        fitted[name] = pipeline
        probabilities_by_model[name] = probabilities

    def score(name: str) -> float:
        cv = results[name].get("cross_validation")
        if cv and np.isfinite(cv["balanced_accuracy"]["mean"]):
            return float(cv["balanced_accuracy"]["mean"])
        return float(results[name]["test"]["balanced_accuracy"])

    best_name = max(results, key=score)
    best_probabilities = probabilities_by_model[best_name]
    prediction_base["selected_probability"] = best_probabilities
    prediction_base["selected_prediction"] = _smooth_predictions(
        prediction_base, "selected_probability", threshold, smoothing_window
    )
    prediction_base["selected_model"] = best_name

    demo_only = bool(config.get("project", {}).get("demo_only", False))
    metrics = {
        "demo_only": demo_only,
        "data_warning": (
            "Synthetic demonstration data; not evidence of sleep accuracy."
            if demo_only
            else "User-confirmed onset/wake labels support a prototype only; EEG/PSG is required for stage claims."
        ),
        "scope": "binary_sleep_wake_prototype",
        "label_source": "user_confirmed_sleep_interval",
        "clinical_stage_claim": False,
        "split_method": split_method,
        "selection_metric": "group_cv_balanced_accuracy",
        "best_model": best_name,
        "train_samples": int(len(train_idx)),
        "test_samples": int(len(test_idx)),
        "train_participants": sorted(dataset.iloc[train_idx]["participant_id"].astype(str).unique()),
        "test_participants": sorted(dataset.iloc[test_idx]["participant_id"].astype(str).unique()),
        "models": results,
    }
    bundle = {
        "framework_version": "0.3.0",
        "demo_only": demo_only,
        "task": "binary_sleep_wake",
        "label_source": "user_confirmed_sleep_interval",
        "model_name": best_name,
        "pipeline": fitted[best_name],
        "feature_columns": feature_columns,
        "probability_threshold": threshold,
        "temporal_smoothing_epochs": smoothing_window,
        "config": config,
        "metrics": metrics,
        "test_predictions": prediction_base,
    }
    return bundle, metrics


def train_sleep_from_config(config: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    dataset_path = Path(config["paths"]["processed_sleep_epochs_csv"])
    if not dataset_path.exists():
        raise FileNotFoundError(f"Missing processed sleep dataset: {dataset_path}")
    dataset = pd.read_csv(dataset_path)
    bundle, metrics = train_sleep_from_dataframe(dataset, config)
    predictions = bundle.pop("test_predictions")

    model_path = Path(config["paths"]["sleep_model_bundle"])
    metrics_path = Path(config["paths"]["sleep_metrics_json"])
    comparison_path = Path(config["paths"]["sleep_model_comparison_json"])
    predictions_path = Path(config["paths"]["sleep_test_predictions_csv"])
    for path in (model_path, metrics_path, comparison_path, predictions_path):
        path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(bundle, model_path)
    payload = json.dumps(metrics, indent=2)
    metrics_path.write_text(payload, encoding="utf-8")
    comparison_path.write_text(payload, encoding="utf-8")
    predictions.to_csv(predictions_path, index=False)
    return bundle, metrics
