# RecoverySense Machine-Learning Framework Guide

## 1. Purpose

RecoverySense uses smartwatch heart-rate and accelerometer measurements to estimate the probability that the current sensor window is associated with a high-recovery-risk or high-craving state. The model returns a probability between 0 and 1. The application compares that probability with the configured threshold of **0.70**. If the probability is at least 0.70 and the EMA cooldown has expired, the API tells the phone app to display an EMA questionnaire.

This is a complete **software framework** for data preparation, training, evaluation, model persistence, and streaming inference. It is not yet a clinically validated model because the repository does not contain real labeled participant data.

## 2. End-to-end data flow

```text
Galaxy Watch sensors
        |
        v
Timestamped heart-rate and accelerometer rows
        |
        v
Validation and cleaning
        |
        v
Uniform resampling + short-gap interpolation
        |
        v
Heart-rate median filter + accelerometer low-pass filter
        |
        v
30-second windows, starting every 15 seconds
        |
        v
EMA-aligned labels
        |
        v
Time-domain and frequency-domain features
        |
        v
Participant-grouped Random Forest training
        |
        v
Probability P(high-risk state)
        |
        v
0.70 threshold + 15-minute cooldown
        |
        v
Trigger or suppress EMA
```

## 3. Files added

```text
ml/
  config/default.yaml
  pyproject.toml
  data/raw/
    sensor_readings_template.csv
    ema_events_template.csv
  src/recoverysense_ml/
    config.py
    schema.py
    preprocessing.py
    labeling.py
    features.py
    dataset.py
    training.py
    inference.py
    synthetic.py
    cli.py
  tests/
    test_features.py
    test_pipeline.py
  models/
  reports/

backend/api/app/services/
  model_service.py
  trigger_service.py
```

## 4. Step 1: Raw sensor data

The training pipeline expects one synchronized CSV:

```text
participant_id,session_id,timestamp,heart_rate,accel_x,accel_y,accel_z
```

- `participant_id` identifies a research participant without using a real name.
- `session_id` separates recording sessions.
- `timestamp` must be an ISO-8601 timestamp. UTC timestamps ending in `Z` are preferred.
- `heart_rate` is beats per minute.
- `accel_x`, `accel_y`, and `accel_z` are acceleration values in units of g.

The watch sensors may report at different rates. The ingestion layer should retain the most recent heart-rate value when an accelerometer row is written, producing a synchronized table. The preprocessing pipeline then resamples the table uniformly.

Template:

```text
ml/data/raw/sensor_readings_template.csv
```

## 5. Step 2: EMA labels

The EMA file uses:

```text
participant_id,timestamp,craving_score,source
```

`craving_score` is currently configured on a 0-10 scale. A score of 7 or higher is treated as a positive event.

The framework labels a sensor window as follows:

- **Positive (`1`)**: a high-score EMA occurs within 120 seconds after the window ends.
- **Negative (`0`)**: no high-score EMA occurs within 300 seconds after the window ends.
- **Ambiguous (`-1`)**: the window falls between those definitions. Ambiguous windows are dropped by default.

This design links physiology immediately preceding an EMA to the self-reported outcome while avoiding mislabeled negatives too close to a positive event. The horizons are research parameters and should be justified and tested, not treated as permanent truths.

## 6. Step 3: Schema validation

`schema.py` verifies that required columns exist and that datasets are nonempty. The pipeline stops with a direct error instead of silently training on malformed data.

This matters because a typo such as `heartrate` instead of `heart_rate` should fail immediately rather than produce an invalid model.

## 7. Step 4: Cleaning and physiological range checks

`preprocessing.py` performs the following operations separately for each participant and session:

1. Convert timestamps to UTC-aware datetimes.
2. Convert sensor columns to numbers.
3. Sort rows chronologically.
4. Remove duplicate timestamps.
5. Replace impossible heart-rate values outside 30-220 BPM with missing values.
6. Replace acceleration values outside -16 g to +16 g with missing values.
7. Split sessions when a gap exceeds 10 seconds.

The ranges are configurable in `ml/config/default.yaml`.

## 8. Step 5: Uniform resampling

The default sampling rate is 10 Hz, meaning one row every 0.1 seconds. Each continuous session segment is reindexed onto this uniform time grid.

Uniform spacing is important because:

- window lengths become deterministic;
- frequency-domain features require a known sampling rate;
- missing intervals can be measured consistently;
- the streaming and training paths use the same assumptions.

Short gaps up to two seconds are interpolated. Long gaps remain disconnected and cannot be bridged by a 30-second window.

## 9. Step 6: Filtering

### Heart rate

A median filter removes isolated spikes without averaging every value toward the center. The default kernel covers three seconds.

### Acceleration

A fourth-order Butterworth low-pass filter removes high-frequency noise above 4 Hz. The filter is applied forward and backward so the offline training data does not receive a time shift.

Filtering parameters are configuration values because the best cutoff depends on the sensor, activity, and sampling frequency.

## 10. Step 7: Sliding windows

The cleaned data is divided into:

- **Window length:** 30 seconds
- **Stride:** 15 seconds
- **Overlap:** 15 seconds, or 50 percent

At 10 Hz, each full window contains 300 rows. A new feature vector is produced every 150 rows.

A window is rejected when:

- it has less than 80 percent of the expected coverage; or
- more than 20 percent of its source values were missing before interpolation.

Windowing converts a continuous signal into individual examples that a standard classifier can learn from.

## 11. Step 8: Feature extraction

`features.py` converts each 30-second window into a fixed-length numeric vector.

### Heart-rate features

- mean, standard deviation, minimum, maximum, range;
- median and interquartile range;
- RMS;
- linear slope in BPM per second;
- mean absolute change;
- RMSSD of successive BPM changes.

The final item is named `hr_rmssd_bpm` rather than claiming to be clinical HRV. True HRV normally requires beat-to-beat intervals, not ordinary BPM samples.

### Motion features

For each axis, magnitude, dynamic magnitude, and jerk:

- mean, standard deviation, minimum, maximum, range;
- median, interquartile range, and RMS.

Additional motion features include:

- signal magnitude area;
- stillness fraction;
- high-motion fraction;
- correlations between axes;
- dominant frequency;
- spectral energy;
- spectral entropy;
- pre-fill and post-fill missingness.

These features allow the model to distinguish patterns such as an elevated heart rate while still from an elevated heart rate during substantial movement.

## 12. Step 9: Participant-grouped split

The model is evaluated on participants it did not train on whenever at least two participants exist.

A random row-level split would put overlapping windows from the same person and session into both training and testing. That can make performance look much better than it actually is. Grouping by participant reduces this leakage.

The framework uses:

- `GroupShuffleSplit` for the final held-out test set;
- `GroupKFold` for cross-validation on the training participants (three folds by default).

When only one participant exists, the framework falls back to a stratified row split and marks the split method in `metrics.json`. That fallback is useful for debugging only, not for a strong research result.

## 13. Step 10: Random Forest model

The model is a scikit-learn pipeline containing:

1. median imputation for missing feature values;
2. a missing-value indicator;
3. a Random Forest classifier.

Default Random Forest settings:

```text
300 trees
minimum 3 samples per leaf
balanced_subsample class weighting
fixed random seed 42
```

The classifier produces a probability, not a final yes/no answer.

## 14. Step 11: Probability threshold

The configured decision rule is:

```text
if probability >= 0.70:
    trigger EMA
else:
    do not trigger EMA
```

The threshold is stored inside the model bundle so training and inference cannot accidentally use different values.

A 0.70 threshold is a design choice, not a universally optimal value. Later analysis should compare precision, recall, participant burden, missed events, and the number of questionnaires per day across several thresholds.

## 15. Step 12: Evaluation

The framework records:

- accuracy;
- precision;
- recall;
- F1 score;
- ROC AUC;
- average precision;
- confusion matrix;
- cross-validation mean and standard deviation;
- top feature importances;
- participant IDs assigned to train and test sets.

Files:

```text
ml/reports/metrics.json
ml/reports/test_predictions.csv
```

Average precision is particularly useful when positive events are much less common than negative windows.

## 16. Step 13: Saved model bundle

Training produces:

```text
ml/models/random_forest_bundle.joblib
```

The bundle contains:

- the fitted preprocessing and classifier pipeline;
- the exact feature-column order;
- the 0.70 threshold;
- the configuration used for training;
- evaluation metadata.

Keeping these together prevents inference from silently using a different feature order or threshold.

## 17. Step 14: Streaming inference

`StreamingInferenceEngine` maintains a separate rolling buffer for each participant.

1. Each incoming sensor row is appended to the participant buffer.
2. The first score occurs after a complete 30-second window exists.
3. A new score occurs every 15 seconds.
4. The exact same preprocessing and feature code used during training is applied.
5. The model returns a probability.
6. A trigger is emitted only when the probability is at least 0.70.
7. A 15-minute cooldown suppresses repeated EMA prompts.

The cooldown is not part of model learning. It is an application policy designed to reduce questionnaire burden.

## 18. Step 15: FastAPI integration

The existing endpoint remains:

```text
POST /sensors/reading
```

The response now contains:

```json
{
  "should_trigger_ema": false,
  "reason": "Collecting enough samples for the first 30-second model window.",
  "probability": null,
  "threshold": 0.7,
  "model_ready": true,
  "window_ready": false,
  "buffered_samples": 120,
  "required_samples": 300,
  "cooldown_active": false
}
```

Model status:

```text
GET /sensors/model
```

Reload a newly trained model without rewriting the API code:

```text
POST /sensors/model/reload
```

When no trained bundle exists, the backend remains operational and uses the original simple heart-rate/motion rules as a clearly identified fallback.

## 19. Step 16: Synthetic demo

Synthetic data verifies that all code paths work before real collection begins. It creates artificial periods with changing heart rate and movement and places high EMA scores after selected events.

Synthetic results must never be presented as evidence that the model works on real people.

Run:

```powershell
recoverysense-ml --config ml/config/default.yaml run-demo
```

## 20. Step 17: Automated tests

Run:

```powershell
pytest ml/tests
```

The tests verify:

- feature extraction returns many finite numeric features;
- synthetic data can pass through preprocessing, labeling, feature construction, training, and evaluation.

## 21. Windows setup commands

From the repository root:

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -e ".\ml[dev]"
recoverysense-ml --config ml/config/default.yaml run-demo
pytest ml/tests
```

Start the backend:

```powershell
pip install -r backend\api\requirements.txt
cd backend\api
uvicorn app.main:app --reload
```

API documentation will be available at:

```text
http://127.0.0.1:8000/docs
```

## 22. Replacing synthetic data with real data

1. Export synchronized watch rows to `ml/data/raw/sensor_readings.csv`.
2. Export completed EMA events to `ml/data/raw/ema_events.csv`.
3. Confirm that timestamps use the same time zone.
4. Run `build-dataset`.
5. Inspect label counts and missingness.
6. Run `train`.
7. Review participant-grouped metrics, not only overall accuracy.
8. Restart the API or call `/sensors/model/reload`.

Commands:

```powershell
recoverysense-ml --config ml/config/default.yaml build-dataset
recoverysense-ml --config ml/config/default.yaml train
```

## 23. What must happen before research deployment

- Confirm the prediction target and EMA wording with the research team.
- Decide whether the target is craving, stress, relapse risk, recovery difficulty, or another defined outcome.
- Document the sensor sampling protocol.
- Validate units from the watch.
- Collect data from multiple participants and multiple days.
- Review class balance and missingness by participant.
- Tune the labeling horizon without examining the final test participants.
- Compare Random Forest against simple baselines.
- Calibrate predicted probabilities if threshold interpretation matters.
- Perform participant-level external validation.
- Establish privacy, consent, retention, and access controls.
- Treat model output as research support, not medical diagnosis.
