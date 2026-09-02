"""
Report the craving-score class balance among EMA events with sufficient
pre-response sensor coverage.
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

usable_scores = []

for _, row in ema.iterrows():
    t = row["timestamp"]

    previous = sensor[
        (sensor["timestamp"] >= t - pd.Timedelta(minutes=5)) &
        (sensor["timestamp"] < t)
    ]

    if len(previous) >= 300:
        usable_scores.append(int(row["craving_score"]))

print("USABLE EMA SCORES:", usable_scores)
print("Usable total:", len(usable_scores))
print("Low <7:", sum(x < 7 for x in usable_scores))
print("Elevated >=7:", sum(x >= 7 for x in usable_scores))

