from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd
from sklearn.pipeline import Pipeline
from sklearn.tree import DecisionTreeClassifier


_DISPLAY_NAMES: dict[str, str] = {
    "hr_mean": "Heart rate level",
    "hr_median": "Heart rate level",
    "hr_std": "Heart rate variability within the window",
    "hr_slope": "Heart rate trend",
    "hr_activation_mean": "Heart rate above your recent baseline",
    "hr_activation_max": "Peak heart rate above your recent baseline",
    "accel_magnitude_mean": "Movement level",
    "accel_magnitude_std": "Movement variability",
    "gyro_magnitude_mean": "Rotation/movement level",
    "gyro_magnitude_std": "Rotation/movement variability",
    "step_delta": "Recent steps",
    "time_of_day_sin": "Time-of-day pattern",
    "time_of_day_cos": "Time-of-day pattern",
    "day_of_week_sin": "Day-of-week pattern",
    "day_of_week_cos": "Day-of-week pattern",
    "sleep_total_minutes": "Previous-night sleep duration",
    "sleep_efficiency": "Previous-night sleep efficiency",
    "sleep_quality": "Previous-night sleep quality",
    "rested_score": "Morning rested rating",
}


def humanize_feature(feature: str) -> str:
    """Return a participant-facing label without implying causality."""
    if feature in _DISPLAY_NAMES:
        return _DISPLAY_NAMES[feature]
    lowered = feature.lower()
    if lowered.startswith("time_of_day_"):
        return "Time-of-day pattern"
    if lowered.startswith("day_of_week_"):
        return "Day-of-week pattern"
    if "hr_baseline" in lowered or "hr_activation" in lowered:
        return "Heart rate relative to your recent baseline"
    if "heart" in lowered or lowered.startswith("hr_"):
        return "Heart rate pattern"
    if "sleep" in lowered or "rested" in lowered:
        return "Recent sleep pattern"
    if "accel" in lowered or "gyro" in lowered or "motion" in lowered:
        return "Movement pattern"
    if "step" in lowered:
        return "Recent activity"
    if "ema" in lowered or "craving" in lowered:
        return "Recent craving history"
    return feature.replace("_", " ").strip().capitalize()


def _positive_class_index(classifier: DecisionTreeClassifier) -> int:
    classes = list(classifier.classes_)
    if 1 in classes:
        return classes.index(1)
    if True in classes:
        return classes.index(True)
    raise ValueError("Decision-tree interpretability requires a binary positive class labeled 1.")


def _node_probability(
    classifier: DecisionTreeClassifier,
    node_id: int,
    positive_class_index: int,
) -> float:
    values = np.asarray(classifier.tree_.value[node_id][0], dtype=float)
    total = float(values.sum())
    if total <= 0:
        return 0.0
    return float(values[positive_class_index] / total)


def decision_tree_path_contributions(
    tree_pipeline: Pipeline,
    feature_frame: pd.DataFrame,
    *,
    top_k: int = 3,
) -> dict[str, Any]:
    """Explain one decision-tree prediction using exact path probability deltas.

    For each split along the sample's root-to-leaf path, the change in the
    positive-class probability from parent node to chosen child is assigned to
    the feature used at the parent. Repeated use of a feature is accumulated.
    Therefore, for the companion decision tree:

        root_probability + sum(all feature contributions) == leaf_probability

    This is a local predictive decomposition of the tree path. It is not a causal attribution
    and it should not be described as one.
    """
    if len(feature_frame) != 1:
        raise ValueError("Explainability currently expects exactly one feature row.")
    if "preprocess" not in tree_pipeline.named_steps or "classifier" not in tree_pipeline.named_steps:
        raise ValueError("Expected a pipeline with preprocess and classifier steps.")

    preprocess = tree_pipeline.named_steps["preprocess"]
    classifier = tree_pipeline.named_steps["classifier"]
    if not isinstance(classifier, DecisionTreeClassifier):
        raise TypeError("The interpretability pipeline must end in DecisionTreeClassifier.")

    transformed = np.asarray(preprocess.transform(feature_frame), dtype=float)
    if transformed.ndim != 2 or transformed.shape[0] != 1:
        raise ValueError("Unexpected transformed feature shape for decision tree.")
    transformed_row = transformed[0]
    feature_names = [str(name) for name in preprocess.get_feature_names_out()]

    positive_index = _positive_class_index(classifier)
    tree = classifier.tree_
    node_id = 0
    root_probability = _node_probability(classifier, node_id, positive_index)
    contributions: dict[str, float] = {}

    while tree.children_left[node_id] != tree.children_right[node_id]:
        feature_index = int(tree.feature[node_id])
        if feature_index < 0 or feature_index >= len(feature_names):
            break
        feature_name = feature_names[feature_index]
        parent_probability = _node_probability(classifier, node_id, positive_index)
        threshold = float(tree.threshold[node_id])
        feature_value = float(transformed_row[feature_index])
        child_id = (
            int(tree.children_left[node_id])
            if feature_value <= threshold
            else int(tree.children_right[node_id])
        )
        child_probability = _node_probability(classifier, child_id, positive_index)
        contributions[feature_name] = contributions.get(feature_name, 0.0) + (
            child_probability - parent_probability
        )
        node_id = child_id

    leaf_probability = _node_probability(classifier, node_id, positive_index)
    additive_probability = root_probability + sum(contributions.values())

    all_contributors: list[dict[str, Any]] = []
    for feature_name, contribution in contributions.items():
        raw_value: float | None = None
        if feature_name in feature_frame.columns:
            value = pd.to_numeric(feature_frame.iloc[0][feature_name], errors="coerce")
            if pd.notna(value):
                raw_value = float(value)
        all_contributors.append(
            {
                "feature": feature_name,
                "display_name": humanize_feature(feature_name),
                "contribution": float(contribution),
                "value": raw_value,
                "direction": "increasing" if contribution > 0 else "decreasing",
            }
        )

    all_contributors.sort(key=lambda item: abs(float(item["contribution"])), reverse=True)
    positive = [item for item in all_contributors if float(item["contribution"]) > 0]

    return {
        "method": "decision_tree_path_probability_delta",
        "interpretability_model": "decision_tree",
        "root_probability": root_probability,
        "leaf_probability": leaf_probability,
        "additive_probability": additive_probability,
        "additivity_error": float(abs(additive_probability - leaf_probability)),
        "all_contributors": all_contributors,
        "top_positive_contributors": positive[: max(0, int(top_k))],
    }


def global_tree_feature_importance(
    tree_pipeline: Pipeline,
    *,
    limit: int = 30,
) -> list[dict[str, Any]]:
    """Return the companion decision tree's global impurity-based importance."""
    preprocess = tree_pipeline.named_steps["preprocess"]
    classifier = tree_pipeline.named_steps["classifier"]
    if not isinstance(classifier, DecisionTreeClassifier):
        raise TypeError("Expected a DecisionTreeClassifier pipeline.")
    names = [str(name) for name in preprocess.get_feature_names_out()]
    rows = [
        {
            "feature": name,
            "display_name": humanize_feature(name),
            "importance": float(importance),
        }
        for name, importance in zip(names, classifier.feature_importances_)
    ]
    rows.sort(key=lambda item: float(item["importance"]), reverse=True)
    return rows[: max(0, int(limit))]
