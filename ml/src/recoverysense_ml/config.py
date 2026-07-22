from __future__ import annotations

from copy import deepcopy
from pathlib import Path
from typing import Any

import yaml


def load_config(path: str | Path) -> dict[str, Any]:
    """Load and minimally validate the YAML configuration file."""
    config_path = Path(path)
    if not config_path.exists():
        raise FileNotFoundError(f"Configuration file not found: {config_path}")

    with config_path.open("r", encoding="utf-8") as handle:
        config = yaml.safe_load(handle)

    if not isinstance(config, dict):
        raise ValueError("The configuration root must be a mapping.")

    required_sections = {
        "paths",
        "schema",
        "preprocessing",
        "windowing",
        "labeling",
        "model",
        "inference",
    }
    missing = sorted(required_sections.difference(config))
    if missing:
        raise ValueError(f"Configuration is missing sections: {missing}")

    return deepcopy(config)
