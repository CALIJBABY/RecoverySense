# RecoverySense Architecture — Version 0.5.1

## Research purpose

RecoverySense collects passive wearable signals and a brief 0–10 craving/urge EMA to build and evaluate behavioral-addiction craving-risk models. The system estimates research probabilities; it does not diagnose addiction, determine relapse by itself, or provide validated clinical treatment.

## Active Android architecture

```text
Galaxy Watch4 or later Wear OS watch
  └── Kotlin app: com.recoverysense.wear
        ├── participant-facing sensor summary + 0–10 micro-EMA
        ├── foreground health recording service
        ├── processed BPM + age/accuracy
        ├── accelerometer and gyroscope
        ├── steps, optional off-body, screen state
        ├── continuous and sleep recording modes
        ├── future Samsung raw PPG adapter (disabled)
        └── Wear Data Layer queue
                         ↓
Flutter Android phone: com.recoverysense.wear
  ├── Firebase Authentication
  ├── bounded one-item-at-a-time watch ingestion
  ├── participant-scoped Firestore repositories
  ├── phone EMA fallback
  ├── sleep-session controls and provisional sleep/wake summaries
  ├── research-data ZIP export
  └── future authenticated backend/model integration
                         ↓
Current prototype storage
  └── Firestore under participants/{uid}/...
                         ↓
Offline Python research pipeline
  ├── raw export and schema validation
  ├── causal preprocessing and feature extraction
  ├── EMA-aligned craving labels
  ├── separate binary sleep/wake dataset/model
  ├── participant/session/purged-time evaluation
  └── model comparison, calibration/error metrics, ablation
```

## Version 0.5.1 participant insight layer

```text
One-time Baseline Assessment v1
  → contextual/self-reported routine, cues, motives, confidence
  → stored separately from repeated EMA labels

Repeated 0–10 EMA + passive sensor history
  → causal feature windows
  → selected risk model probability
  → companion decision-tree local path explanation
  → up to 3 positive contributors with model/version provenance

Independently timed repeated EMA
  → local-time two-hour windows
  → minimum-data guardrails
  → descriptive Higher-Risk Times dashboard
```

The Baseline Assessment does not directly set model weights. The craving gauge is the participant's latest self-report; it is not a model prediction. Participant model display fails closed unless the record is versioned, non-demo, explicitly marked participant-displayable, has a valid probability, and is recent. When the selected risk model differs from the companion decision tree, the UI identifies tree contributors as a parallel explanation view rather than an exact decomposition of the selected model probability.

## Canonical Firestore hierarchy

```text
participants/{uid}
  sessions/{watchSessionId}
    sensor_batches/{batchId}
    ppg_batches/{batchId}              # absent while PPG is disabled
  ema_events/{eventId}
  baseline_assessments/baseline_v1
  sleep_sessions/{sleepSessionId}
    epochs/{epochId}
    sensor_batches/{batchId}           # reproducibility mirror
    ppg_batches/{batchId}              # future mirror
  sleep_logs/{legacyId}                 # legacy/read-only; no new writes
  model_predictions/{id}               # reserved/future
  risk_predictions/{id}                # optional model probability + explanation provenance
  trigger_events/{id}                  # reserved/future
```

## Sensor/data semantics

- `heart_rate` is processed beats per minute, not raw PPG and not beat-to-beat ECG HRV.
- `heart_rate_age_ms` records freshness; values older than 90 seconds are not repeated as valid current BPM.
- Accelerometer values are stored in SI units plus calculated magnitude in g.
- Gyroscope values are rad/s.
- Missing/unavailable sensors remain explicit missing values.
- Raw samples are stored separately from derived model features.
- EMA clock features use participant-local time only when a valid `timezone_offset_minutes` value is available; otherwise cyclic local-time inputs remain missing and `local_time_context_available=0`.
- PPG-derived interval variability must be labeled PRV unless ECG equivalence is established.

## Craving-model path

```text
Prior-only sensor windows + eligible prior sleep summary + earlier EMA history
  → quality filtering and causal features
  → model probability
  → research threshold/cooldown policy
  → watch EMA only after validation gate
  → 0–10 response becomes a new supervised label
```

The target EMA itself and any response collected after the prediction time are not pre-prompt model inputs.

## Sleep path

```text
Phone start marker
  → watch foreground sleep mode
  → 30-second aligned epochs
  → provisional rule-based estimated sleep/wake
  → morning participant correction
  → offline binary sleep/wake training
  → eligible prior-night summary features for craving modeling
```

Four-stage sleep classification requires synchronized EEG/PSG or appropriately validated reference labels and richer cardiac information. The current output remains estimated sleep/wake.

## Future backend migration boundary

The watch communicates only with the phone. A database change should replace the phone repository/backend layer rather than embedding database credentials in the watch or Flutter APK:

```text
Watch → Phone → authenticated HTTPS API → approved database
```

Firebase Authentication may be retained temporarily while storage migrates, but a stable research `participant_id` should remain separate from provider-specific authentication IDs.
