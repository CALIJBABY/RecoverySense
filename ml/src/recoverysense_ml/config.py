from __future__ import annotations

from copy import deepcopy
from pathlib import Path
from typing import Any

import yaml


ML_ROOT = Path(__file__).resolve().parents[2]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]


def _resolve_config_path(path: str | Path) -> Path:
    """Resolve a config path without depending on the caller's working directory."""
    requested = Path(path).expanduser()
    if requested.is_absolute():
        candidates = [requested]
    else:
        candidates = [
            Path.cwd() / requested,
            REPOSITORY_ROOT / requested,
            ML_ROOT / requested,
        ]
        # Commands run from ``ml/`` often still use the documented
        # ``ml/config/default.yaml`` path. Strip that redundant prefix as a
        # final location-independent fallback.
        if requested.parts and requested.parts[0].lower() == "ml":
            candidates.append(ML_ROOT.joinpath(*requested.parts[1:]))

    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()

    searched = ", ".join(str(candidate) for candidate in candidates)
    raise FileNotFoundError(
        f"Configuration file not found: {requested}. Searched: {searched}"
    )


def _resolve_project_paths(config: dict[str, Any]) -> None:
    """Normalize repository-relative path settings to absolute paths.

    RecoverySense configuration files are versioned from the repository root.
    Making path values absolute at load time keeps the CLI, tests, notebooks,
    and backend behavior consistent regardless of the shell's current folder.
    """
    paths = config.get("paths")
    if not isinstance(paths, dict):
        return

    for key, raw_value in list(paths.items()):
        if not isinstance(raw_value, str) or not raw_value.strip():
            continue
        value = Path(raw_value).expanduser()
        if value.is_absolute():
            paths[key] = str(value)
            continue
        paths[key] = str((REPOSITORY_ROOT / value).resolve())


def load_config(path: str | Path) -> dict[str, Any]:
    """Load and minimally validate the YAML configuration file."""
    config_path = _resolve_config_path(path)

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
        "sleep_model",
        "sleep_context",
        "inference",
    }
    missing = sorted(required_sections.difference(config))
    if missing:
        raise ValueError(f"Configuration is missing sections: {missing}")

    normalized = deepcopy(config)
    _resolve_project_paths(normalized)
    normalized.setdefault("project", {})["config_path"] = str(config_path)
    normalized["project"]["repository_root"] = str(REPOSITORY_ROOT)
    return normalized
