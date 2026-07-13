from __future__ import annotations

import numpy as np
import pandas as pd


def accel_magnitude(df: pd.DataFrame) -> pd.Series:
    return np.sqrt(df["accel_x"] ** 2 + df["accel_y"] ** 2 + df["accel_z"] ** 2)


def window_features(df: pd.DataFrame) -> dict[str, float]:
    """Compute simple features for one sensor window.

    Expected columns:
    - heart_rate
    - accel_x
    - accel_y
    - accel_z
    """
    accel_mag = accel_magnitude(df)
    return {
        "hr_mean": float(df["heart_rate"].mean()),
        "hr_std": float(df["heart_rate"].std(ddof=1)),
        "accel_mag_mean": float(accel_mag.mean()),
        "accel_mag_std": float(accel_mag.std(ddof=1)),
        "accel_x_var": float(df["accel_x"].var(ddof=1)),
        "accel_y_var": float(df["accel_y"].var(ddof=1)),
        "accel_z_var": float(df["accel_z"].var(ddof=1)),
    }
