from __future__ import annotations

from recoverysense_ml.config import load_config
from recoverysense_ml.sleep_model import (
    build_sleep_epoch_dataset,
    train_sleep_from_dataframe,
)
from recoverysense_ml.synthetic import generate_sleep_demo_data


def test_sleep_dataset_and_training() -> None:
    config = load_config("ml/config/default.yaml")
    config["sleep_model"]["n_estimators"] = 30
    config["sleep_model"]["gradient_boosting_estimators"] = 30
    config["sleep_model"]["cross_validation_folds"] = 2
    sensors, sessions = generate_sleep_demo_data(
        config, participants=6, minutes_per_night=10
    )
    dataset = build_sleep_epoch_dataset(sensors, sessions, config)
    assert set(dataset["label"].unique()) == {0, 1}
    assert dataset["epoch_start"].notna().all()
    bundle, metrics = train_sleep_from_dataframe(dataset, config)
    assert bundle["task"] == "binary_sleep_wake"
    assert metrics["clinical_stage_claim"] is False
    best = metrics["best_model"]
    assert 0.0 <= metrics["models"][best]["test"]["balanced_accuracy"] <= 1.0
