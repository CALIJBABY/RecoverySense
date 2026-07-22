# RecoverySense ML Framework

This folder contains an end-to-end, reproducible development pipeline for turning synchronized smartwatch sensor readings and EMA responses into a probability that an EMA should be triggered.

## What is included

- Input schema validation
- Physiological range checks
- Uniform resampling and short-gap interpolation
- Median filtering for heart rate
- Butterworth low-pass filtering for acceleration
- 30-second windows with 15-second overlap
- EMA-based window labeling
- Time-domain and frequency-domain feature extraction
- Participant-grouped train/test splitting
- Random Forest probability model
- Fixed 0.70 EMA trigger threshold
- Metrics, predictions, model bundle, and streaming inference
- FastAPI integration with rule-based fallback
- Synthetic demo data and automated tests

## Important limitation

The framework is complete as software, but the included synthetic data is only for testing. It is not a clinically valid model. A useful model requires real participant data, reliable EMA labels, protocol review, and participant-level external validation.

## Quick start from the repository root

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -e ".\ml[dev]"
recoverysense-ml --config ml/config/default.yaml run-demo
pytest ml/tests
```

Outputs:

- `ml/data/raw/sensor_readings.csv`
- `ml/data/raw/ema_events.csv`
- `ml/data/processed/training_windows.csv`
- `ml/models/random_forest_bundle.joblib`
- `ml/reports/metrics.json`
- `ml/reports/test_predictions.csv`

See `docs/ML_FRAMEWORK_GUIDE.md` for the complete explanation.
