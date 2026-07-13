from __future__ import annotations

from pathlib import Path

import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report
import joblib

DATA_PATH = Path("ml/data/processed/training_windows.csv")
MODEL_PATH = Path("ml/models/random_forest_baseline.joblib")


def main() -> None:
    if not DATA_PATH.exists():
        raise FileNotFoundError(
            f"Missing {DATA_PATH}. Create this later after collecting sensor + EMA data."
        )

    df = pd.read_csv(DATA_PATH)
    y = df["label"]
    x = df.drop(columns=["label"])

    x_train, x_test, y_train, y_test = train_test_split(
        x, y, test_size=0.2, random_state=7, stratify=y
    )

    model = RandomForestClassifier(n_estimators=100, random_state=7)
    model.fit(x_train, y_train)

    predictions = model.predict(x_test)
    print(classification_report(y_test, predictions))

    MODEL_PATH.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(model, MODEL_PATH)
    print(f"Saved model to {MODEL_PATH}")


if __name__ == "__main__":
    main()
