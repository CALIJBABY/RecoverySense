from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.inspection import permutation_importance
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    balanced_accuracy_score,
    brier_score_loss,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import (
    GroupKFold,
    GroupShuffleSplit,
    StratifiedGroupKFold,
    cross_validate,
)
from sklearn.naive_bayes import GaussianNB
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC
from sklearn.tree import DecisionTreeClassifier

from .explainability import global_tree_feature_importance


NON_FEATURE_COLUMNS = {
    "participant_id",
    "session_id",
    "window_start",
    "window_end",
    "ema_score",
    "ema_timestamp",
    "label",
}


def _split_indices(
    dataset: pd.DataFrame,
    config: dict[str, Any],
) -> tuple[np.ndarray, np.ndarray, str]:
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
                prevalence_error = abs(
                    float(y.iloc[test_idx].mean()) - overall_prevalence
                )
                candidates.append((fraction_error + prevalence_error, train_idx, test_idx))
        except ValueError:
            candidates = []

        if candidates:
            _, train_idx, test_idx = min(candidates, key=lambda item: item[0])
            return train_idx, test_idx, "participant-grouped-stratified"

        splitter = GroupShuffleSplit(
            n_splits=50,
            test_size=test_fraction,
            random_state=seed,
        )
        for train_idx, test_idx in splitter.split(dataset, y, groups):
            if y.iloc[train_idx].nunique() == 2 and y.iloc[test_idx].nunique() == 2:
                return train_idx, test_idx, "participant-grouped"

    # With too few participants, keep complete sessions separated when possible.
    session_groups = (
        dataset["participant_id"].astype(str)
        + "/"
        + dataset["session_id"].astype(str)
    )
    if session_groups.nunique() >= 2:
        splitter = GroupShuffleSplit(
            n_splits=100,
            test_size=test_fraction,
            random_state=seed,
        )
        for train_idx, test_idx in splitter.split(dataset, y, session_groups):
            if y.iloc[train_idx].nunique() == 2 and y.iloc[test_idx].nunique() == 2:
                return train_idx, test_idx, "session-grouped-fallback"

    # Final fallback is chronological, never a random split of adjacent windows.
    ordered = dataset.assign(_original_index=np.arange(len(dataset))).sort_values(
        ["window_start", "window_end", "_original_index"]
    )
    minimum_test = max(1, int(round(len(ordered) * test_fraction)))
    target_cut = len(ordered) - minimum_test
    window_seconds = float(config.get("windowing", {}).get("window_seconds", 30.0))
    candidate_cuts = sorted(
        range(1, len(ordered)),
        key=lambda cut: abs(cut - target_cut),
    )
    for cut in candidate_cuts:
        test_start = pd.to_datetime(ordered.iloc[cut]["window_start"], utc=True)
        purge_before = test_start - pd.Timedelta(seconds=window_seconds)
        train_rows = ordered[
            pd.to_datetime(ordered["window_end"], utc=True) < purge_before
        ]
        test_rows = ordered.iloc[cut:]
        if train_rows.empty or test_rows.empty:
            continue
        train_idx = train_rows["_original_index"].to_numpy(int)
        test_idx = test_rows["_original_index"].to_numpy(int)
        if y.iloc[train_idx].nunique() == 2 and y.iloc[test_idx].nunique() == 2:
            return train_idx, test_idx, "purged-temporal-holdout-fallback"

    raise ValueError(
        "Unable to create a leakage-resistant two-class split. Collect more "
        "participants, sessions, and both low/high EMA responses."
    )


def _metrics(
    y_true: pd.Series,
    probabilities: np.ndarray,
    threshold: float,
) -> dict[str, Any]:
    predictions = (probabilities >= threshold).astype(int)
    matrix = confusion_matrix(y_true, predictions, labels=[0, 1])
    tn, fp, fn, tp = matrix.ravel()
    specificity = float(tn / (tn + fp)) if (tn + fp) else None
    false_positive_rate = float(fp / (tn + fp)) if (tn + fp) else None
    metrics: dict[str, Any] = {
        "threshold": threshold,
        "samples": int(len(y_true)),
        "positive_samples": int(np.sum(y_true)),
        "accuracy": float(accuracy_score(y_true, predictions)),
        "balanced_accuracy": float(balanced_accuracy_score(y_true, predictions)),
        "precision": float(precision_score(y_true, predictions, zero_division=0)),
        "recall_sensitivity": float(recall_score(y_true, predictions, zero_division=0)),
        "specificity": specificity,
        "false_positive_rate": false_positive_rate,
        "f1": float(f1_score(y_true, predictions, zero_division=0)),
        "brier_score": float(brier_score_loss(y_true, probabilities)),
        "confusion_matrix": matrix.tolist(),
    }
    # Backward-compatible alias retained for existing reports and UI code.
    metrics["recall"] = metrics["recall_sensitivity"]
    metrics["roc_auc"] = (
        float(roc_auc_score(y_true, probabilities))
        if y_true.nunique() > 1
        else None
    )
    metrics["average_precision"] = (
        float(average_precision_score(y_true, probabilities))
        if y_true.nunique() > 1
        else None
    )
    return metrics


def _build_preprocessor(feature_columns: list[str]) -> ColumnTransformer:
    numeric_transformer = Pipeline(
        steps=[
            ("imputer", SimpleImputer(strategy="median", keep_empty_features=True)),
            ("scaler", StandardScaler()),
        ]
    )
    return ColumnTransformer(
        transformers=[("numeric", numeric_transformer, feature_columns)],
        remainder="drop",
        verbose_feature_names_out=False,
    )


def _candidate_classifiers(config: dict[str, Any]) -> dict[str, Any]:
    model_cfg = config["model"]
    seed = int(config["project"]["random_seed"])
    return {
        "decision_tree": DecisionTreeClassifier(
            max_depth=int(model_cfg.get("decision_tree_max_depth", 8)),
            min_samples_leaf=int(model_cfg["min_samples_leaf"]),
            class_weight="balanced",
            random_state=seed,
        ),
        "logistic_regression": LogisticRegression(
            max_iter=int(model_cfg.get("logistic_max_iter", 2000)),
            class_weight="balanced",
            random_state=seed,
        ),
        "support_vector_machine": SVC(
            C=float(model_cfg.get("svm_c", 1.0)),
            kernel="rbf",
            probability=True,
            class_weight="balanced",
            random_state=seed,
        ),
        "random_forest": RandomForestClassifier(
            n_estimators=int(model_cfg["n_estimators"]),
            max_depth=model_cfg["max_depth"],
            min_samples_leaf=int(model_cfg["min_samples_leaf"]),
            class_weight=model_cfg["class_weight"],
            random_state=seed,
            n_jobs=int(model_cfg.get("n_jobs", 1)),
        ),
        "gradient_boosting": GradientBoostingClassifier(
            n_estimators=int(model_cfg.get("gradient_boosting_estimators", 150)),
            learning_rate=float(model_cfg.get("gradient_boosting_learning_rate", 0.05)),
            max_depth=int(model_cfg.get("gradient_boosting_max_depth", 3)),
            random_state=seed,
        ),
        "naive_bayes": GaussianNB(),
    }


def _cross_validation_metrics(
    pipeline: Pipeline,
    x_train: pd.DataFrame,
    y_train: pd.Series,
    groups: pd.Series,
    requested_folds: int,
) -> dict[str, Any] | None:
    folds = min(requested_folds, groups.nunique())
    if folds < 2:
        return None

    cv = StratifiedGroupKFold(n_splits=folds, shuffle=True, random_state=42)
    scores = cross_validate(
        pipeline,
        x_train,
        y_train,
        groups=groups,
        cv=cv,
        scoring={
            "roc_auc": "roc_auc",
            "average_precision": "average_precision",
            "f1": "f1",
        },
        n_jobs=1,
        error_score=np.nan,
    )
    result: dict[str, Any] = {"folds": folds}
    for metric in ("roc_auc", "average_precision", "f1"):
        values = scores[f"test_{metric}"]
        result[metric] = {
            "mean": float(np.nanmean(values)),
            "std": float(np.nanstd(values)),
        }
    return result


def _selection_score(metrics: dict[str, Any]) -> float:
    cv = metrics.get("cross_validation")
    if cv:
        value = cv.get("average_precision", {}).get("mean")
        if value is not None and np.isfinite(value):
            return float(value)
    value = metrics["test"].get("average_precision")
    return float(value) if value is not None and np.isfinite(value) else -np.inf


def train_from_dataframe(
    dataset: pd.DataFrame,
    config: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any]]:
    feature_columns = [
        column for column in dataset.columns if column not in NON_FEATURE_COLUMNS
    ]
    if not feature_columns:
        raise ValueError("No feature columns were found in the processed dataset.")

    x = dataset[feature_columns].apply(pd.to_numeric, errors="coerce")
    y = dataset["label"].astype(int)
    train_idx, test_idx, split_method = _split_indices(dataset, config)
    x_train, x_test = x.iloc[train_idx], x.iloc[test_idx]
    y_train, y_test = y.iloc[train_idx], y.iloc[test_idx]
    train_groups = dataset.iloc[train_idx]["participant_id"].astype(str)

    if y_train.nunique() < 2:
        raise ValueError(
            "The training split contains only one class. Collect more participants/events or adjust the split."
        )

    model_cfg = config["model"]
    threshold = float(model_cfg["probability_threshold"])
    requested_folds = int(model_cfg["cross_validation_folds"])
    candidates = _candidate_classifiers(config)

    model_results: dict[str, dict[str, Any]] = {}
    fitted_pipelines: dict[str, Pipeline] = {}
    probabilities_by_model: dict[str, np.ndarray] = {}

    for model_name, classifier in candidates.items():
        pipeline = Pipeline(
            steps=[
                ("preprocess", _build_preprocessor(feature_columns)),
                ("classifier", classifier),
            ]
        )
        pipeline.fit(x_train, y_train)
        probabilities = pipeline.predict_proba(x_test)[:, 1]
        test_metrics = _metrics(y_test, probabilities, threshold)
        cv_metrics = _cross_validation_metrics(
            pipeline,
            x_train,
            y_train,
            train_groups,
            requested_folds,
        )
        model_results[model_name] = {
            "test": test_metrics,
            "cross_validation": cv_metrics,
        }
        fitted_pipelines[model_name] = pipeline
        probabilities_by_model[model_name] = probabilities

    best_model_name = max(model_results, key=lambda name: _selection_score(model_results[name]))
    best_pipeline = fitted_pipelines[best_model_name]
    best_probabilities = probabilities_by_model[best_model_name]

    permutation = permutation_importance(
        best_pipeline,
        x_test,
        y_test,
        scoring="average_precision",
        n_repeats=int(model_cfg.get("permutation_importance_repeats", 5)),
        random_state=int(config["project"]["random_seed"]),
        n_jobs=1,
    )
    ranked_importance = sorted(
        zip(feature_columns, permutation.importances_mean, permutation.importances_std),
        key=lambda item: item[1],
        reverse=True,
    )

    demo_only = bool(config.get("project", {}).get("demo_only", False))
    interpretability_pipeline = fitted_pipelines["decision_tree"]
    tree_global_importance = global_tree_feature_importance(interpretability_pipeline)
    trained_at_utc = datetime.now(timezone.utc).isoformat()
    metrics = {
        "demo_only": demo_only,
        "data_warning": (
            "Synthetic demonstration data; do not use for participant EMA triggering."
            if demo_only
            else "Model performance depends on the provenance and quality of the supplied study data."
        ),
        "split_method": split_method,
        "selection_metric": "training_group_cv_average_precision",
        "best_model": best_model_name,
        "interpretability_model": "decision_tree",
        "interpretability_method": "decision_tree_path_probability_delta",
        "interpretability_note": (
            "Local path contributions describe the companion decision tree, not causality. "
            "If the selected risk model is not the decision tree, risk probability and "
            "interpretability model are intentionally reported separately."
        ),
        "decision_tree_global_feature_importance": tree_global_importance,
        "train_samples": int(len(train_idx)),
        "test_samples": int(len(test_idx)),
        "train_participants": sorted(
            dataset.iloc[train_idx]["participant_id"].astype(str).unique().tolist()
        ),
        "test_participants": sorted(
            dataset.iloc[test_idx]["participant_id"].astype(str).unique().tolist()
        ),
        "models": model_results,
        "top_permutation_importances": [
            {
                "feature": name,
                "importance_mean": float(mean),
                "importance_std": float(std),
            }
            for name, mean, std in ranked_importance[:30]
        ],
    }

    bundle = {
        "framework_version": "0.5.3",
        "trained_at_utc": trained_at_utc,
        "demo_only": demo_only,
        "model_name": best_model_name,
        "pipeline": best_pipeline,
        "interpretability_pipeline": interpretability_pipeline,
        "interpretability_model": "decision_tree",
        "interpretability_method": "decision_tree_path_probability_delta",
        "decision_tree_global_feature_importance": tree_global_importance,
        "feature_columns": feature_columns,
        "probability_threshold": threshold,
        "config": config,
        "metrics": metrics,
    }

    prediction_frame = dataset.iloc[test_idx][
        ["participant_id", "session_id", "window_start", "window_end", "label"]
    ].copy()
    for model_name, probabilities in probabilities_by_model.items():
        prediction_frame[f"{model_name}_probability"] = probabilities
        prediction_frame[f"{model_name}_prediction"] = (
            probabilities >= threshold
        ).astype(int)
    prediction_frame["selected_probability"] = best_probabilities
    prediction_frame["selected_prediction"] = (
        best_probabilities >= threshold
    ).astype(int)
    prediction_frame["selected_model"] = best_model_name
    bundle["test_predictions"] = prediction_frame
    return bundle, metrics


def train_from_config(
    config: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any]]:
    dataset_path = Path(config["paths"]["processed_windows_csv"])
    if not dataset_path.exists():
        raise FileNotFoundError(f"Missing processed dataset: {dataset_path}")
    dataset = pd.read_csv(dataset_path)

    bundle, metrics = train_from_dataframe(dataset, config)
    prediction_frame = bundle.pop("test_predictions")

    model_path = Path(config["paths"]["model_bundle"])
    metrics_path = Path(config["paths"]["metrics_json"])
    comparison_path = Path(
        config["paths"].get("model_comparison_json", "ml/reports/model_comparison.json")
    )
    predictions_path = Path(config["paths"]["test_predictions_csv"])
    for path in (model_path, metrics_path, comparison_path, predictions_path):
        path.parent.mkdir(parents=True, exist_ok=True)

    joblib.dump(bundle, model_path)
    payload = json.dumps(metrics, indent=2)
    metrics_path.write_text(payload, encoding="utf-8")
    comparison_path.write_text(payload, encoding="utf-8")
    prediction_frame.to_csv(predictions_path, index=False)
    return bundle, metrics
