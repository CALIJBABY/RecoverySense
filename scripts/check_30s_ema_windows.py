"""
Check pre-EMA coverage for the intended 30-second RecoverySense sensor window.

This is a data-quality diagnostic only. It does not train or evaluate a
craving-risk model.
"""
import pandas as pd

sensor = pd.read_csv(
    r"ml\data\raw\primary_participant\sensor_readings.csv",
    low_memory=False
)

ema = pd.read_csv(
    r"ml\data\raw\primary_participant\ema_events.csv"
)

sensor["timestamp"] = pd.to_datetime(
    sensor["timestamp"], utc=True, errors="coerce"
)
ema["timestamp"] = pd.to_datetime(
    ema["timestamp"], utc=True, errors="coerce"
)

sensor = sensor.dropna(subset=["timestamp"]).sort_values("timestamp")
ema = ema.dropna(subset=["timestamp"]).sort_values("timestamp")

usable = []

print("\n30-SECOND PRE-EMA WINDOWS\n")

for _, row in ema.iterrows():

    t = row["timestamp"]

    window = sensor[
        (sensor["timestamp"] >= t - pd.Timedelta(seconds=30)) &
        (sensor["timestamp"] < t)
    ]

    count = len(window)
    score = int(row["craving_score"])
    valid = count >= 240

    print(
        f"{t} | craving={score} | "
        f"rows={count} | usable={valid}"
    )

    if valid:
        usable.append(score)

print()
print("30-second usable EMA events:", len(usable))
print("Usable scores:", usable)
print("Low <7:", sum(x < 7 for x in usable))
print("Elevated >=7:", sum(x >= 7 for x in usable))

