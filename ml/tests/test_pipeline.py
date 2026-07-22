from __future__ import annotations

from recoverysense_ml.config import load_config
from recoverysense_ml.dataset import build_window_dataset
from recoverysense_ml.synthetic import generate_demo_data
from recoverysense_ml.training import train_from_dataframe


def test_end_to_end_pipeline(tmp_path) -> None:
    config = load_config("ml/config/default.yaml")
    config["paths"]["raw_sensor_csv"] = str(tmp_path / "sensors.csv")
    config["paths"]["ema_csv"] = str(tmp_path / "ema.csv")
    config["model"]["n_estimators"] = 30
    config["model"]["cross_validation_folds"] = 2
    sensors, ema = generate_demo_data(config, participants=6, minutes=6)
    dataset = build_window_dataset(sensors, ema, config)
    bundle, metrics = train_from_dataframe(dataset, config)
    assert "pipeline" in bundle
    assert 0.0 <= metrics["test"]["accuracy"] <= 1.0
