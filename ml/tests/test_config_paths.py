from __future__ import annotations

from pathlib import Path

from recoverysense_ml.config import ML_ROOT, load_config


def test_documented_config_path_works_from_ml_working_directory(monkeypatch) -> None:
    monkeypatch.chdir(ML_ROOT)
    config = load_config("ml/config/default.yaml")
    assert Path(config["project"]["config_path"]).name == "default.yaml"
    assert Path(config["paths"]["ema_csv"]).is_absolute()
