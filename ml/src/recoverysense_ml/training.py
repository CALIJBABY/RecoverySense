from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import GroupKFold, GroupShuffleSplit, StratifiedGroupKFold, StratifiedShuffleSplit, cross_validate
from sklearn.pipeline import Pipeline


NON_FEATURE_COLUMNS = {
    "participant_id",
    "session_id",
    "window_start",
    "window_end",
    "ema_score",
    "ema_timestamp",
    "label",
}


def _split_indices(dataset: pd.DataFrame, config: dict[str, Any]) -> tuple[np.ndarray, np.ndarray, str]:
    seed = int(config["project"]["random_seed"])
    test_fraction = float(config["model"]["test_fraction"])
    groups = dataset["participant_id"].astype(str)
    y = dataset["label"].astype(int)

    if groups.nunique() >= 2:
        requested_splits = max(2, int(round(1.0 / test_fraction)))
        n_splits = min(requested_splits, groups.nunique())
        candidates: list[tuple[float, np.ndarray, np.ndarray]] = []
        try:
            splitter = StratifiedGroupKFold(
                n_splits=n_splits,
                shuffle=True,
                random_state=seed,
            )
            overall_prevalence = float(y.mean())
            for train_idx, test_idx in splitter.split(dataset, y, groups):
                if y.iloc[train_idx].nunique() < 2 or y.iloc[test_idx].nunique() < 2:
                    continue
                fraction_error = abs(len(test_idx) / len(dataset) - test_fraction)
                prevalence_error = abs(float(y.iloc[test_idx].mean()) - overall_prevalence)
                candidates.append((fraction_error + prevalence_error, train_idx, test_idx))
        except ValueError:
            candidates = []

        if candidates:
            _, train_idx, test_idx = min(candidates, key=lambda item: item[0])
            return train_idx, test_idx, "participant-grouped-stratified"

        # Fallback search: preserve participant separation and prefer splits with both classes.
        splitter = GroupShuffleSplit(n_splits=50, test_size=test_fraction, random_state=seed)
        for train_idx, test_idx in splitter.split(dataset, y, groups):
            if y.iloc[train_idx].nunique() == 2 and y.iloc[test_idx].nunique() == 2:
                return train_idx, test_idx, "participant-grouped"

    splitter = StratifiedShuffleSplit(n_splits=1, test_size=test_fraction, random_state=seed)
    train_idx, test_idx = next(splitter.split(dataset, y))
    return train_idx, test_idx, "stratified-row-fallback"


def _metrics(y_true: pd.Series, probabilities: np.ndarray, threshold: float) -> dict[str, Any]:
    predictions = (probabilities >= threshold).astype(int)
    metrics: dict[str, Any] = {
        "threshold": threshold,
        "samples": int(len(y_true)),
        "positive_samples": int(np.sum(y_true)),
        "accuracy": float(accuracy_score(y_true, predictions)),
        "precision": float(precision_score(y_true, predictions, zero_division=0)),
        "recall": float(recall_score(y_true, predictions, zero_division=0)),
        "f1": float(f1_score(y_true, predictions, zero_division=0)),
        "confusion_matrix": confusion_matrix(y_true, predictions, labels=[0, 1]).tolist(),
    }
    metrics["roc_auc"] = float(roc_auc_score(y_true, probabilities)) if y_true.nunique() > 1 else None
    metrics["average_precision"] = (
        float(average_precision_score(y_true, probabilities)) if y_true.nunique() > 1 else None
    )
    return metrics


def train_from_dataframe(dataset: pd.DataFrame, config: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    feature_columns = [column for column in dataset.columns if column not in NON_FEATURE_COLUMNS]
    if not feature_columns:
        raise ValueError("No feature columns were found in the processed dataset.")

    x = dataset[feature_columns]
    y = dataset["label"].astype(int)
    train_idx, test_idx, split_method = _split_indices(dataset, config)
    x_train, x_test = x.iloc[train_idx], x.iloc[test_idx]
    y_train, y_test = y.iloc[train_idx], y.iloc[test_idx]

    if y_train.nunique() < 2:
        raise ValueError(
            "The training split contains only one class. Collect more participants/events or adjust the split."
        )

    numeric_transformer = Pipeline(
        steps=[("imputer", SimpleImputer(strategy="median", add_indicator=True))]
    )
    preprocessor = ColumnTransformer(
        transformers=[("numeric", numeric_transformer, feature_columns)],
        remainder="drop",
        verbose_feature_names_out=False,
    )

    model_cfg = config["model"]
    classifier = RandomForestClassifier(
        n_estimators=int(model_cfg["n_estimators"]),
        max_depth=model_cfg["max_depth"],
        min_samples_leaf=int(model_cfg["min_samples_leaf"]),
        class_weight=model_cfg["class_weight"],
        random_state=int(config["project"]["random_seed"]),
        n_jobs=int(model_cfg.get("n_jobs", 1)),
    )
    pipeline = Pipeline(steps=[("preprocess", preprocessor), ("classifier", classifier)])
    pipeline.fit(x_train, y_train)

    threshold = float(model_cfg["probability_threshold"])
    probabilities = pipeline.predict_proba(x_test)[:, 1]
    test_metrics = _metrics(y_test, probabilities, threshold)

    cv_metrics: dict[str, Any] | None = None
    unique_groups = dataset.iloc[train_idx]["participant_id"].astype(str).nunique()
    requested_folds = int(model_cfg["cross_validation_folds"])
    folds = min(requested_folds, unique_groups)
    if folds >= 2:
        cv = GroupKFold(n_splits=folds)
        scores = cross_validate(
            pipeline,
            x_train,
            y_train,
            groups=dataset.iloc[train_idx]["participant_id"].astype(str),
            cv=cv,
            scoring={"roc_auc": "roc_auc", "average_precision": "average_precision", "f1": "f1"},
            n_jobs=1,
            error_score=np.nan,
        )
        cv_metrics = {"folds": folds}
        for metric in ("roc_auc", "average_precision", "f1"):
            cv_metrics[metric] = {
                "mean": float(np.nanmean(scores[f"test_{metric}"])),
                "std": float(np.nanstd(scores[f"test_{metric}"])),
            }

    classifier_fit = pipeline.named_steps["classifier"]
    importances = sorted(
        zip(feature_columns, classifier_fit.feature_importances_[: len(feature_columns)]),
        key=lambda pair: pair[1],
        reverse=True,
    )

    metrics = {
        "split_method": split_method,
        "train_samples": int(len(train_idx)),
        "test_samples": int(len(test_idx)),
        "train_participants": sorted(dataset.iloc[train_idx]["participant_id"].astype(str).unique().tolist()),
        "test_participants": sorted(dataset.iloc[test_idx]["participant_id"].astype(str).unique().tolist()),
        "test": test_metrics,
        "cross_validation": cv_metrics,
        "top_feature_importances": [
            {"feature": name, "importance": float(value)} for name, value in importances[:20]
        ],
    }

    bundle = {
        "framework_version": "0.1.0",
        "pipeline": pipeline,
        "feature_columns": feature_columns,
        "probability_threshold": threshold,
        "config": config,
        "metrics": metrics,
    }

    prediction_frame = dataset.iloc[test_idx][
        ["participant_id", "session_id", "window_start", "window_end", "label"]
    ].copy()
    prediction_frame["probability"] = probabilities
    prediction_frame["prediction"] = (probabilities >= threshold).astype(int)
    bundle["test_predictions"] = prediction_frame
    return bundle, metrics


def train_from_config(config: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    dataset_path = Path(config["paths"]["processed_windows_csv"])
    if not dataset_path.exists():
        raise FileNotFoundError(f"Missing processed dataset: {dataset_path}")
    dataset = pd.read_csv(dataset_path)

    bundle, metrics = train_from_dataframe(dataset, config)
    prediction_frame = bundle.pop("test_predictions")

    model_path = Path(config["paths"]["model_bundle"])
    metrics_path = Path(config["paths"]["metrics_json"])
    predictions_path = Path(config["paths"]["test_predictions_csv"])
    for path in (model_path, metrics_path, predictions_path):
        path.parent.mkdir(parents=True, exist_ok=True)

    joblib.dump(bundle, model_path)
    metrics_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    prediction_frame.to_csv(predictions_path, index=False)
    return bundle, metrics
