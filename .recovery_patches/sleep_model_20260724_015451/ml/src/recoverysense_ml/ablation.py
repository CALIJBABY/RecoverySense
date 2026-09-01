from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.pipeline import Pipeline

from .training import NON_FEATURE_COLUMNS, _build_preprocessor, _metrics, _split_indices


def _group_for_feature(feature: str) -> str:
    if feature.startswith("hr_") or feature.startswith("heart_rate_"):
        if "activation" in feature or "correlation" in feature:
            return "interactions"
        return "heart_rate"
    if feature.startswith(("accel_", "dynamic_accel_", "jerk_")) or feature in {
        "signal_magnitude_area",
        "stillness_fraction",
        "high_motion_fraction",
    }:
        return "accelerometer"
    if feature.startswith(("gyro_", "rotational_")) or feature == "still_wrist_fraction":
        return "gyroscope"
    if feature.startswith("step_"):
        return "steps"
    if feature.startswith(("time_", "day_", "previous_", "ema_", "session_")):
        return "context_history"
    if any(
        token in feature
        for token in ("missing", "valid_fraction", "accuracy", "off_body", "coverage")
    ):
        return "quality"
    if "correlation" in feature or "activation" in feature:
        return "interactions"
    return "other"


def _evaluate_subset(
    dataset: pd.DataFrame,
    selected_features: list[str],
    config: dict[str, Any],
) -> dict[str, Any]:
    train_idx, test_idx, split_method = _split_indices(dataset, config)
    x = dataset[selected_features].apply(pd.to_numeric, errors="coerce")
    y = dataset["label"].astype(int)
    x_train, x_test = x.iloc[train_idx], x.iloc[test_idx]
    y_train, y_test = y.iloc[train_idx], y.iloc[test_idx]

    model_cfg = config["model"]
    classifier = RandomForestClassifier(
        n_estimators=min(150, int(model_cfg["n_estimators"])),
        max_depth=model_cfg["max_depth"],
        min_samples_leaf=int(model_cfg["min_samples_leaf"]),
        class_weight=model_cfg["class_weight"],
        random_state=int(config["project"]["random_seed"]),
        n_jobs=int(model_cfg.get("n_jobs", 1)),
    )
    pipeline = Pipeline(
        steps=[
            ("preprocess", _build_preprocessor(selected_features)),
            ("classifier", classifier),
        ]
    )
    pipeline.fit(x_train, y_train)
    probabilities = pipeline.predict_proba(x_test)[:, 1]
    return {
        "split_method": split_method,
        "test": _metrics(
            y_test,
            probabilities,
            float(model_cfg["probability_threshold"]),
        ),
    }


def run_feature_group_ablation(
    dataset: pd.DataFrame,
    config: dict[str, Any],
) -> dict[str, Any]:
    feature_columns = [
        column for column in dataset.columns if column not in NON_FEATURE_COLUMNS
    ]
    groups: dict[str, list[str]] = {}
    for feature in feature_columns:
        groups.setdefault(_group_for_feature(feature), []).append(feature)

    experiments = {
        "heart_rate_only": {"heart_rate", "quality"},
        "accelerometer_only": {"accelerometer", "quality"},
        "heart_rate_plus_accelerometer": {
            "heart_rate",
            "accelerometer",
            "interactions",
            "quality",
        },
        "add_time_and_history": {
            "heart_rate",
            "accelerometer",
            "interactions",
            "context_history",
            "quality",
        },
        "add_gyroscope_and_steps": {
            "heart_rate",
            "accelerometer",
            "gyroscope",
            "steps",
            "interactions",
            "context_history",
            "quality",
        },
        "all_features": set(groups),
    }

    results: dict[str, Any] = {}
    for experiment_name, included_groups in experiments.items():
        selected = [
            feature
            for feature in feature_columns
            if _group_for_feature(feature) in included_groups
        ]
        if not selected:
            continue
        evaluation = _evaluate_subset(dataset, selected, config)
        results[experiment_name] = {
            "included_groups": sorted(included_groups),
            "feature_count": len(selected),
            "evaluation_model": "random_forest",
            **evaluation,
        }

    return {
        "feature_groups": {name: sorted(values) for name, values in groups.items()},
        "experiments": results,
    }


def run_ablation_from_config(config: dict[str, Any]) -> dict[str, Any]:
    dataset_path = Path(config["paths"]["processed_windows_csv"])
    if not dataset_path.exists():
        raise FileNotFoundError(f"Missing processed dataset: {dataset_path}")
    dataset = pd.read_csv(dataset_path)
    results = run_feature_group_ablation(dataset, config)
    output_path = Path(
        config["paths"].get(
            "feature_ablation_json",
            "ml/reports/feature_group_ablation.json",
        )
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(results, indent=2), encoding="utf-8")
    return results
