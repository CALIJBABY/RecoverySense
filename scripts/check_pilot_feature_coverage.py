"""
Summarize heart-rate and motion availability for EMA events considered usable
in the exploratory single-participant pilot analysis.
"""
import pandas as pd

sensor = pd.read_csv(
    r"ml\data\raw\primary_participant\sensor_readings.csv",
    low_memory=False
)
ema = pd.read_csv(
    r"ml\data\raw\primary_participant\ema_events.csv"
)

sensor["timestamp"] = pd.to_datetime(sensor["timestamp"], utc=True, errors="coerce")
ema["timestamp"] = pd.to_datetime(ema["timestamp"], utc=True, errors="coerce")

sensor = sensor.dropna(subset=["timestamp"]).sort_values("timestamp")
ema = ema.dropna(subset=["timestamp"]).sort_values("timestamp")

print("\nUSABLE 5-MINUTE EMA SENSOR QUALITY\n")

for _, row in ema.iterrows():
    t = row["timestamp"]

    w = sensor[
        (sensor["timestamp"] >= t - pd.Timedelta(minutes=5)) &
        (sensor["timestamp"] < t)
    ]

    if len(w) < 300:
        continue

    hr = pd.to_numeric(w["heart_rate"], errors="coerce")
    acc = pd.to_numeric(w["acceleration_g"], errors="coerce")
    gyro = pd.to_numeric(w["gyro_magnitude"], errors="coerce")

    print(
        f"craving={int(row['craving_score'])} | "
        f"rows={len(w):,} | "
        f"HR={hr.notna().sum():,} | "
        f"ACC={acc.notna().sum():,} | "
        f"GYRO={gyro.notna().sum():,}"
    )

