# RecoverySense Sleep Pattern Tracking and ML Integration — Version 0.5.1

## Purpose

Sleep is a supporting context signal for the behavioral-addiction craving-risk model. The current implementation estimates binary **sleep versus wake** and nightly summaries. It is not a medical sleep diagnosis and does not claim validated Wake/N1/N2/N3/REM staging.

RecoverySense collects its own overnight watch data instead of requiring Samsung Health sleep outputs. Samsung Health data may later be imported and stored separately as a commercial-device comparison; it must not overwrite the independent RecoverySense estimate or be treated as EEG/PSG ground truth.

## End-to-end flow

```text
Phone: Start sleep recording
        ↓ Wear OS Data Layer command
Watch foreground health service
        ↓ BPM + motion + steps/off-body/quality metadata
Aligned batches and 30-second epochs
        ↓
Phone authenticated ingestion
        ├── raw sleep sensor batches
        ├── provisional estimated sleep/wake probabilities
        └── provisional nightly summary
        ↓
Phone: End sleep recording
        ├── waits briefly for queued epoch count to stabilize
        ├── finalizes provisional summary
        └── allows morning participant correction
        ↓
Offline binary sleep/wake training/evaluation
        ↓
Eligible prior-night summary features for craving prediction
```

## Watch implementation

Active project:

```text
apps/wear_android/wear_android
```

`SleepTrackingService` owns both `continuous` and `sleep` modes so collection is not dependent on the visible activity. Current streams include:

- Processed heart-rate BPM, source timestamp, age, and accuracy
- Accelerometer x/y/z and magnitude
- Gyroscope x/y/z and magnitude
- Step count/events when available
- Optional off-body state
- Screen-interactive state and sensor capability/quality metadata
- Future raw PPG only after the documented enablement gate

The standard application sampling target is 10 Hz and batches target 30 seconds. The transport includes `recording_mode`, `sleep_session_id`, watch/session IDs, timestamps, and schema/version metadata.

The watch retries transient Data Layer write failures in order and attempts to drain final partial batches during a normal stop. Forced process death can still lose a final in-memory partial batch; disk-backed watch persistence remains a future hardening item.

## Phone implementation

The Sleep Pattern Tracking screen supports:

- Start and stop commands
- Provisional estimated sleep/wake timeline
- Estimated onset, final wake, total sleep, WASO, awakenings, efficiency, and confidence
- Participant correction of onset/wake/awakenings
- Subjective sleep quality and rested score
- Explicit watch-removal Yes/No response

Morning confirmation requires deliberate participant responses for sleep quality, rested score, awakening count, and watch-removal status. Visible neutral/default positions are not silently stored as answers, and the corrected wake time must be after corrected sleep onset.

Canonical storage:

```text
participants/{uid}/sleep_sessions/{sleepSessionId}
participants/{uid}/sleep_sessions/{sleepSessionId}/epochs/{epochId}
participants/{uid}/sleep_sessions/{sleepSessionId}/sensor_batches/{batchId}
participants/{uid}/sleep_logs/{legacyId}             # legacy/read-only; no new sleep writes
```

New sleep writes use `sleep_sessions`; `sleep_logs` is retained only for historical export/read compatibility. Raw sleep batches remain available even if the provisional estimator or model changes. Failed watch-start attempts store a stable `start_error_code` rather than raw exception text in research records.

## Binary sleep/wake model inputs

The dataset builder creates non-overlapping 30-second epochs and uses current/prior information only:

- Motion magnitude, variability, stillness, and bursts
- Current/prior gyroscope summaries where available
- BPM level/change/coverage and quality
- Steps/off-body/coverage
- Clock/time-within-recording context
- Previous-epoch and prior rolling summaries

`next_*` features and centered model-input windows are prohibited because they would use future information. Completed-night retrospective smoothing may use neighboring predicted epochs only as clearly labeled offline postprocessing; it is not a live model input.

## Labels

Initial participant-reported onset/wake corrections are weak labels suitable for pipeline development and approximate sleep/wake research. True stage research requires synchronized 30-second reference labels from PSG or an appropriately validated EEG device.

## Evaluation

Use participant-grouped holdout and grouped cross-validation whenever possible. Report:

- Sleep sensitivity
- Wake specificity
- Balanced accuracy
- Precision/F1 where defined
- Cohen's kappa
- AUROC/calibration where appropriate
- Sleep-onset, final-wake, total-sleep, WASO, and efficiency errors
- Missingness, off-body periods, battery, and failure cases

## Craving-model integration

Only prior-night summaries are joined to a craving-prediction window. Eligibility rules:

- Wake time must be at or before the prediction window.
- 0–36 hours old is current.
- More than 36 through 48 hours is marked stale; measurements remain missing by default.
- Older than 48 hours is excluded.
- Missing sleep is represented as missing plus explicit availability/freshness indicators, not zero sleep.

Ablation must test whether sleep actually adds predictive value beyond BPM, movement, time, and EMA history.

## Evidence basis and limitation

A 2023 wearable sleep-staging study used PPG-derived cardiac activity plus accelerometry in 30-second epochs and validated against manually scored PSG, supporting the general epoching/multimodal approach: https://pubmed.ncbi.nlm.nih.gov/37280297/

A 2025 smartwatch study likewise used instantaneous heart rate, accelerometry, and EEG-derived labels for four-class 30-second staging: https://pubmed.ncbi.nlm.nih.gov/40971274/

These studies do not validate RecoverySense. RecoverySense requires its own synchronized reference data and participant-held-out testing before any staging claim.
