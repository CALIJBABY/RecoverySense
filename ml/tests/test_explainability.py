from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.tree import DecisionTreeClassifier

from recoverysense_ml.explainability import decision_tree_path_contributions


def _pipeline() -> tuple[Pipeline, pd.DataFrame]:
    frame = pd.DataFrame(
        {
            "hr_activation_mean": [-3, -2, -1, 0, 6, 7, 8, 9],
            "accel_magnitude_std": [3, 2, 2, 1, 1, 1, 0.8, 0.6],
            "time_of_day_sin": [-1, -0.8, -0.4, 0, 0.4, 0.7, 0.9, 1.0],
        }
    )
    labels = pd.Series([0, 0, 0, 0, 1, 1, 1, 1])
    columns = list(frame.columns)
    preprocess = ColumnTransformer(
        [("numeric", Pipeline([("imputer", SimpleImputer()), ("scaler", StandardScaler())]), columns)],
        remainder="drop",
        verbose_feature_names_out=False,
    )
    pipeline = Pipeline(
        [
            ("preprocess", preprocess),
            (
                "classifier",
                DecisionTreeClassifier(max_depth=3, min_samples_leaf=1, random_state=42),
            ),
        ]
    )
    pipeline.fit(frame, labels)
    return pipeline, frame


def test_tree_path_contributions_are_additive() -> None:
    pipeline, frame = _pipeline()
    row = frame.iloc[[6]].copy()
    explanation = decision_tree_path_contributions(pipeline, row, top_k=3)
    tree_probability = float(pipeline.predict_proba(row)[0, 1])
    assert np.isclose(explanation["leaf_probability"], tree_probability)
    assert np.isclose(explanation["additive_probability"], tree_probability)
    assert explanation["additivity_error"] < 1e-10


def test_tree_explanation_returns_only_positive_top_contributors() -> None:
    pipeline, frame = _pipeline()
    explanation = decision_tree_path_contributions(pipeline, frame.iloc[[7]], top_k=3)
    contributors = explanation["top_positive_contributors"]
    assert len(contributors) <= 3
    assert all(item["contribution"] > 0 for item in contributors)
    assert all(item["direction"] == "increasing" for item in contributors)
    assert all(item["display_name"] for item in contributors)
