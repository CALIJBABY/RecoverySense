"""
Measure sensor coverage during the five minutes preceding each EMA response.

Used to identify EMA events with enough pre-response wearable data for
exploratory analysis. No model is trained by this script.
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

print("\nEMA PRE-RESPONSE SENSOR COVERAGE\n")

usable = 0

for i, row in ema.iterrows():
    t = row["timestamp"]

    previous = sensor[
        (sensor["timestamp"] >= t - pd.Timedelta(minutes=5)) &
        (sensor["timestamp"] < t)
    ]

    count = len(previous)

    if count >= 300:
        usable += 1

    print(
        f"{t} | craving={row['craving_score']} | "
        f"previous 5-min sensor rows={count:,}"
    )

print()
print(f"EMA events total: {len(ema)}")
print(f"EMA with >=300 pre-response sensor rows: {usable}")

