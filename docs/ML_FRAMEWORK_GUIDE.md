# RecoverySense Craving Machine-Learning Framework — Version 0.5.1

## 1. Purpose and current status

RecoverySense is designed to estimate the probability of an elevated self-reported behavioral-addiction craving/urge and to determine whether an EMA prompt is scientifically and operationally appropriate. The repository provides data export, causal preprocessing, label construction, feature extraction, candidate-model comparison, leakage-resistant evaluation, ablation, model persistence, and a streaming inference interface.

It does **not** yet contain a validated craving model. Synthetic data are engineering demonstrations only. Model-triggered EMA must remain disabled until real participant EMA-labeled data meet prespecified performance, burden, and safety criteria.

## 2. Required supervised label

The required repeated EMA is:

```text
How strong is your urge or craving right now?
0 = none, 10 = extreme
```

Stored core fields include:

```text
participant_id
session_id
timestamp_ms
prompted_at_ms
opened_at_ms
submitted_at_ms
response_delay_ms
craving_score
source
response_device
model/trigger metadata when applicable
```

The primary continuous target remains `craving_score` (0–10). For the current binary classifier configuration, a configurable high-craving threshold converts the score to an elevated/not-elevated label. The threshold is a study parameter, not a universal clinical cutoff.

## 3. End-to-end flow

```text
Raw watch samples and quality metadata
        ↓
Schema/range checks and session-gap splitting
        ↓
Causal uniform resampling and short-gap handling
        ↓
Causal heart-rate/motion preprocessing
        ↓
Prior-only 30-second windows
        ↓
EMA-aligned positive/nearby-low labels
        ↓
Heart, motion, steps, quality, time/history, sleep, future PPG features
        ↓
Participant-grouped candidate-model comparison
        ↓
Held-out discrimination + calibration + error/burden metrics
        ↓
Ablation and research review
        ↓
Only after validation: versioned mobile inference and EMA policy
```

## 4. Raw input and data quality

The Firestore exporter creates analysis tables containing participant/session identity, watch timestamps, processed BPM, BPM source timestamp/age/accuracy, accelerometer, gyroscope, steps, optional off-body state, screen-interactive state, recording mode, sleep-session ID, and capability/quality metadata.

Important semantics:

- BPM is not raw PPG and `hr_rmssd_bpm` is not clinical HRV.
- PPG interval features, when available, are labeled PRV.
- Watch timestamps are used instead of upload/receipt time for physiological alignment.
- Raw records are preserved; analysis preprocessing creates separate derived data.
- Missing data remain measurable and can become explicit model indicators.

## 5. Causal preprocessing

Prediction features must use only information available at or before the prediction time.

Current safeguards:

1. Timestamps are converted to UTC and sorted within participant/session.
2. Duplicate timestamps and configured impossible values are handled.
3. Long gaps split continuous segments.
4. Uniform resampling uses forward-only short-gap filling; it does not fill a past sample using a future measurement.
5. Heart-rate median smoothing is trailing rather than centered.
6. Accelerometer/gyroscope low-pass filtering uses causal `sosfilt`, not forward-backward `filtfilt`.
7. `heart_rate_age_ms` and `screen_interactive` survive preprocessing for quality analysis.
8. Windows end before the EMA/prediction time.

Offline retrospective descriptions may use noncausal visualization/smoothing only when clearly separated from live prediction inputs.

## 6. Label construction

Configured positive/negative horizons are research parameters and must be prespecified.

Current binary-label logic:

- A **positive** window requires a nearby EMA whose score meets the configured elevated-craving threshold.
- A **negative** window requires a nearby EMA whose score is in the configured low-craving range.
- A distant unlabeled period is not assumed to be a confirmed negative.
- Ambiguous/unpaired windows are excluded from supervised fitting.

This prevents the model from treating “no prompt/no report” as proof that no craving existed.

## 7. Feature groups

### Heart-rate/BPM features

- Distribution, range, slope, change, and coverage
- Difference from prior-only personal/activity baseline
- BPM-reading variability explicitly named as BPM variability, not HRV
- Freshness/accuracy and missingness

### Accelerometer features

- Axis and magnitude summaries
- Dynamic magnitude, jerk, stillness, movement bursts
- Frequency-domain summaries computed within the prior window
- Axis correlations and coverage

### Gyroscope and steps

- Rotation magnitude/jerk and coverage
- Step delta/events/cadence where available
- Interaction features to distinguish locomotion from low-movement physiological elevation

### Time/history

- Participant-local time-of-day/day-of-week cyclic variables derived from the matched EMA/current inference timezone offset
- `local_time_context_available` indicator; cyclic local-time fields remain missing rather than treating UTC as local time when offset metadata are unavailable
- Earlier EMA history only
- Time since prior response/prompt where available
- Session elapsed time

### Sleep

Only an eligible prior-night summary whose wake time precedes the prediction window is joined. Availability, age, freshness/staleness, and missingness remain explicit.

### Future PPG

Quality-controlled green/infrared/red waveform and PRV features are included only after real raw PPG is enabled and validated. No fake PPG values are generated.

## 8. Evaluation splits

The framework avoids random row splitting of overlapping/correlated windows.

Priority order:

1. **Participant-grouped holdout** — entire participants remain outside training.
2. **Session-grouped fallback** — complete sessions remain separated when participant count is insufficient.
3. **Purged chronological fallback** — earlier windows train, later windows test, with a temporal purge gap to prevent overlapping-window leakage.
4. If none can produce two classes, training stops and requests more participants/sessions/low-and-high EMA examples.

Cross-validation within training data uses grouped methods when the number of groups/classes permits. Hyperparameter/model selection must not use the final held-out test outcomes.

## 9. Candidate models

Current comparison includes:

- Logistic Regression
- Support Vector Machine
- Decision Tree
- Random Forest
- Gradient Boosting
- Naive Bayes

A Decision Tree is retained as an interpretable baseline, not automatically selected. The best model is selected only from training-group validation. Tree-based and non-tree pipelines use appropriate imputation/scaling choices and preserve missing-value indicators.

## 10. Required reporting

At minimum report:

- Participant, session, window, positive, and negative counts
- Prompt counts, response rate, response delay, and prompts/day
- Missingness and sensor availability by participant/device/day
- Exact preprocessing, label horizons, feature set, threshold, model version, and split method
- Balanced accuracy
- Sensitivity/recall and specificity
- Precision and F1
- False-positive rate and false prompts/day
- AUROC and average precision when defined
- Brier score/calibration assessment
- Confusion matrix and confidence intervals/uncertainty where feasible
- Performance by participant and relevant subgroups
- Ablation results and failure cases

Accuracy alone is insufficient for an imbalanced prompt-trigger problem.

## 11. Ablation plan

Compare at least:

```text
BPM only
accelerometer only
BPM + accelerometer
+ gyroscope/steps
+ time and prior EMA history
+ prior-night sleep
+ future raw PPG/PRV
full available feature set
```

A modality should remain enabled only if its incremental value justifies battery, storage, privacy, and participant burden.

## 12. Trigger gate

The backend's generic engineering rule is disabled by default. A model or rule must not trigger participant-facing intervention logic until:

- real protocol-approved EMA-labeled data exist;
- the model passes leakage-resistant evaluation;
- calibration and false-prompt burden are acceptable;
- failure/safety behavior and cooldown policy are reviewed;
- the exact model/version/threshold is frozen and documented;
- prospective pilot/device tests are completed.

## 13. Commands

From the repository root:

```powershell
$env:PYTHONPATH = "ml/src"
python -m pytest -q ml/tests
python -m recoverysense_ml.cli --config ml/config/default.yaml --help
```

Use the CLI commands documented in `ml/README.md` for export, dataset construction, training, ablation, and demonstration. Any bundle with `demo_only=true` is automatically unsuitable for participant EMA triggering.

## 14. Reporting standards used as audit references

- TRIPOD+AI (prediction-model reporting): https://doi.org/10.1136/bmj-2023-078378
- DECIDE-AI (early live clinical AI evaluation): https://doi.org/10.1038/s41591-022-01772-9
- mERA (mHealth intervention reporting): https://doi.org/10.1136/bmj.i1174

These are reporting/evaluation frameworks; they do not by themselves certify the model or study.

## 15. Personalized explanation layer

Version 0.5+ keeps two model roles separate:

1. **Selected risk model:** the candidate selected under the prespecified evaluation criteria and used for the displayed risk probability when deployed.
2. **Interpretability companion:** a decision tree fitted on the same training data/feature set and retained for transparent local path explanations.

For a current feature vector, the companion tree follows its actual root-to-leaf path. The change in positive-class node probability at each split is attributed to the feature used at that split. Repeated features are accumulated, producing an exact additive decomposition of the companion tree probability:

```text
root probability + sum(feature path contributions) = leaf probability
```

The three largest positive local contributions may be displayed to the participant. They are **predictive associations, not causal effects**.

If the selected risk model is not the companion decision tree, the tree contributors must be labeled as a parallel interpretability view and must not be represented as an exact explanation of the selected model's probability.

Global decision-tree impurity importance is retained for model audit/overview only; it is not substituted for local per-prediction explanation.

## 16. Baseline and participant-local time variables

The one-time baseline assessment is exported as a separate table. Version 0.5+ deliberately does not inject those fields automatically into the default feature matrix. Any baseline variable added later must be prespecified and evaluated by ablation so participant identity, stable proxies, or sparse categorical levels do not create apparent performance without deployable generalization.

EMA records preserve `local_minute_of_day` and `timezone_offset_minutes`. Primary descriptive time-of-day ranking uses independently timed EMA rather than manual/model-triggered observations. In v0.5.1, craving-model clock/day features are already cyclic and participant-local: training uses the timezone offset associated with the matched EMA, and streaming inference uses current timezone metadata from the inference context. If a valid offset is unavailable, the cyclic local-time fields are left missing and `local_time_context_available=0`; UTC is not silently substituted as a participant routine proxy. This preserves midnight adjacency while avoiding a timezone-dependent labeling artifact.
