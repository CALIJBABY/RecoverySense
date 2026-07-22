from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from .features import extract_window_features
from .labeling import AMBIGUOUS_LABEL, label_window, prepare_ema_data
from .preprocessing import prepare_sensor_data


METADATA_COLUMNS = [
    "participant_id",
    "session_id",
    "window_start",
    "window_end",
    "ema_score",
    "ema_timestamp",
    "label",
]


def build_window_dataset(
    sensor_frame: pd.DataFrame,
    ema_frame: pd.DataFrame,
    config: dict[str, Any],
) -> pd.DataFrame:
    processed = prepare_sensor_data(sensor_frame, config)
    ema = prepare_ema_data(ema_frame, config)

    schema = config["schema"]
    window_cfg = config["windowing"]
    participant_col = schema["participant_column"]
    session_col = schema["session_column"]
    timestamp_col = schema["timestamp_column"]

    rate = float(config["preprocessing"]["sampling_rate_hz"])
    window_samples = int(round(float(window_cfg["window_seconds"]) * rate))
    stride_samples = int(round(float(window_cfg["stride_seconds"]) * rate))
    minimum_samples = int(round(window_samples * float(window_cfg["minimum_window_coverage"])))
    maximum_missing = float(window_cfg["maximum_missing_fraction"])

    rows: list[dict[str, Any]] = []
    for (participant_id, session_id), group in processed.groupby(
        [participant_col, session_col], sort=False
    ):
        group = group.sort_values(timestamp_col).reset_index(drop=True)
        if len(group) < minimum_samples:
            continue

        for start in range(0, max(1, len(group) - minimum_samples + 1), stride_samples):
            end = start + window_samples
            window = group.iloc[start:end]
            if len(window) < minimum_samples:
                continue

            observed_missing = float(
                window["row_missing_fraction_before_fill"].mean()
            )
            if observed_missing > maximum_missing:
                continue

            window_start = window[timestamp_col].iloc[0]
            window_end = window[timestamp_col].iloc[-1]
            label, ema_score, ema_timestamp = label_window(
                str(participant_id), window_end, ema, config
            )
            if label == AMBIGUOUS_LABEL and config["labeling"]["drop_ambiguous_windows"]:
                continue

            features = extract_window_features(window, config)
            rows.append(
                {
                    participant_col: participant_id,
                    session_col: session_id,
                    "window_start": window_start,
                    "window_end": window_end,
                    "ema_score": np.nan if ema_score is None else ema_score,
                    "ema_timestamp": ema_timestamp,
                    "label": label,
                    **features,
                }
            )

    if not rows:
        raise ValueError(
            "No labeled windows were produced. Check timestamps, EMA events, and labeling horizons."
        )

    result = pd.DataFrame(rows)
    if result["label"].nunique() < 2:
        raise ValueError("The window dataset must contain both positive and negative labels.")
    return result


def build_dataset_from_config(config: dict[str, Any]) -> pd.DataFrame:
    sensor_path = Path(config["paths"]["raw_sensor_csv"])
    ema_path = Path(config["paths"]["ema_csv"])
    if not sensor_path.exists():
        raise FileNotFoundError(f"Missing sensor data: {sensor_path}")
    if not ema_path.exists():
        raise FileNotFoundError(f"Missing EMA data: {ema_path}")

    dataset = build_window_dataset(
        pd.read_csv(sensor_path),
        pd.read_csv(ema_path),
        config,
    )
    output_path = Path(config["paths"]["processed_windows_csv"])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    dataset.to_csv(output_path, index=False)
    return dataset
