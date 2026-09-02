"""
Run the exploratory single-participant RecoverySense craving-risk comparison.

Each usable EMA event is treated as one independent labeled observation.
Leave-one-EMA-event-out evaluation prevents sensor rows associated with the
same EMA event from being treated as independent outcomes.

Results are proof-of-pipeline pilot findings, not validated predictive or
clinical performance.
"""
from pathlib import Path

import numpy as np
import pandas as pd

from sklearn.base import clone
from sklearn.compose import ColumnTransformer
from sklearn.dummy import DummyClassifier
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    balanced_accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.naive_bayes import GaussianNB
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC
from sklearn.tree import DecisionTreeClassifier


SENSOR_PATH = r"ml\data\raw\primary_participant\sensor_readings.csv"
EMA_PATH = r"ml\data\raw\primary_participant\ema_events.csv"

OUT_DIR = Path(r"ml\reports\pilot_single_participant")
OUT_DIR.mkdir(parents=True, exist_ok=True)


sensor = pd.read_csv(SENSOR_PATH, low_memory=False)
ema = pd.read_csv(EMA_PATH)

sensor["timestamp"] = pd.to_datetime(
    sensor["timestamp"], utc=True, errors="coerce"
)
ema["timestamp"] = pd.to_datetime(
    ema["timestamp"], utc=True, errors="coerce"
)

sensor = sensor.dropna(subset=["timestamp"]).sort_values("timestamp")
ema = ema.dropna(subset=["timestamp"]).sort_values("timestamp")


numeric_cols = [
    "heart_rate",
    "acceleration_g",
    "gyro_magnitude",
    "step_count",
]

for col in numeric_cols:
    if col in sensor.columns:
        sensor[col] = pd.to_numeric(sensor[col], errors="coerce")


rows = []

for _, e in ema.iterrows():
    t = e["timestamp"]

    w = sensor[
        (sensor["timestamp"] >= t - pd.Timedelta(minutes=5))
        & (sensor["timestamp"] < t)
    ].copy()

    if len(w) < 300:
        continue

    hr = w["heart_rate"]
    acc = w["acceleration_g"]
    gyro = w["gyro_magnitude"]
    steps = w["step_count"]

    valid_steps = steps.dropna()

    if len(valid_steps) >= 2:
        step_delta = max(
            0.0,
            float(valid_steps.iloc[-1] - valid_steps.iloc[0])
        )
    else:
        step_delta = np.nan

    score = int(e["craving_score"])

    rows.append({
        "ema_timestamp": t,
        "craving_score": score,
        "label": int(score >= 7),

        "hr_mean": hr.mean(),
        "hr_std": hr.std(),
        "hr_coverage": hr.notna().mean(),

        "acc_mean": acc.mean(),
        "acc_std": acc.std(),

        "gyro_mean": gyro.mean(),

        "step_delta": step_delta,

        "sensor_rows": len(w),
    })


data = pd.DataFrame(rows)

features = [
    "hr_mean",
    "hr_std",
    "hr_coverage",
    "acc_mean",
    "acc_std",
    "gyro_mean",
    "step_delta",
]

X = data[features]
y = data["label"].astype(int)


print()
print("PILOT DATASET")
print("-------------")
print("EMA events:", len(data))
print("Low <7:", int((y == 0).sum()))
print("Elevated >=7:", int((y == 1).sum()))
print()
print(data[
    ["ema_timestamp", "craving_score", "label", "sensor_rows"]
].to_string(index=False))


scaled = lambda estimator: Pipeline([
    ("imputer", SimpleImputer(strategy="median")),
    ("scaler", StandardScaler()),
    ("model", estimator),
])

unscaled = lambda estimator: Pipeline([
    ("imputer", SimpleImputer(strategy="median")),
    ("model", estimator),
])


models = {
    "Majority baseline": unscaled(
        DummyClassifier(strategy="most_frequent")
    ),

    "Decision Tree": unscaled(
        DecisionTreeClassifier(
            max_depth=3,
            class_weight="balanced",
            random_state=42,
        )
    ),

    "Logistic Regression": scaled(
        LogisticRegression(
            class_weight="balanced",
            max_iter=2000,
            random_state=42,
        )
    ),

    "SVM": scaled(
        SVC(
            kernel="rbf",
            C=1.0,
            probability=True,
            class_weight="balanced",
            random_state=42,
        )
    ),

    "Random Forest": unscaled(
        RandomForestClassifier(
            n_estimators=300,
            class_weight="balanced",
            random_state=42,
        )
    ),

    "Gradient Boosting": unscaled(
        GradientBoostingClassifier(
            n_estimators=150,
            random_state=42,
        )
    ),

    "Gaussian Naive Bayes": unscaled(
        GaussianNB()
    ),
}


results = []
prediction_rows = []


for name, base_model in models.items():

    preds = []
    probs = []

    for test_index in range(len(X)):
        train_index = [
            i for i in range(len(X))
            if i != test_index
        ]

        X_train = X.iloc[train_index]
        y_train = y.iloc[train_index]

        X_test = X.iloc[[test_index]]

        model = clone(base_model)
        model.fit(X_train, y_train)

        pred = int(model.predict(X_test)[0])
        preds.append(pred)

        if hasattr(model, "predict_proba"):
            p = float(model.predict_proba(X_test)[0, 1])
        else:
            p = float(pred)

        probs.append(p)

        prediction_rows.append({
            "model": name,
            "ema_timestamp": data.iloc[test_index]["ema_timestamp"],
            "craving_score": data.iloc[test_index]["craving_score"],
            "actual": int(y.iloc[test_index]),
            "predicted": pred,
            "probability_elevated": p,
        })

    preds = np.asarray(preds)
    probs = np.asarray(probs)

    tn, fp, fn, tp = confusion_matrix(
        y, preds, labels=[0, 1]
    ).ravel()

    specificity = (
        tn / (tn + fp)
        if (tn + fp) > 0
        else np.nan
    )

    try:
        roc = roc_auc_score(y, probs)
    except Exception:
        roc = np.nan

    try:
        ap = average_precision_score(y, probs)
    except Exception:
        ap = np.nan

    results.append({
        "model": name,
        "accuracy": accuracy_score(y, preds),
        "balanced_accuracy": balanced_accuracy_score(y, preds),
        "precision": precision_score(
            y, preds, zero_division=0
        ),
        "recall_sensitivity": recall_score(
            y, preds, zero_division=0
        ),
        "specificity": specificity,
        "f1": f1_score(
            y, preds, zero_division=0
        ),
        "roc_auc": roc,
        "average_precision": ap,
        "true_negative": tn,
        "false_positive": fp,
        "false_negative": fn,
        "true_positive": tp,
    })


results_df = pd.DataFrame(results)

results_df = results_df.sort_values(
    ["balanced_accuracy", "average_precision"],
    ascending=False,
)

predictions_df = pd.DataFrame(prediction_rows)

data.to_csv(
    OUT_DIR / "pilot_event_features.csv",
    index=False,
)

results_df.to_csv(
    OUT_DIR / "pilot_model_metrics.csv",
    index=False,
)

predictions_df.to_csv(
    OUT_DIR / "pilot_leave_one_event_out_predictions.csv",
    index=False,
)


print()
print("LEAVE-ONE-EMA-EVENT-OUT RESULTS")
print("-------------------------------")

display_cols = [
    "model",
    "accuracy",
    "balanced_accuracy",
    "precision",
    "recall_sensitivity",
    "specificity",
    "f1",
    "roc_auc",
    "average_precision",
]

print(
    results_df[display_cols]
    .round(3)
    .to_string(index=False)
)

print()
print("Saved to:")
print(OUT_DIR.resolve())
print()
print(
    "IMPORTANT: n=10 EMA events. "
    "These are exploratory proof-of-pipeline results only."
)

