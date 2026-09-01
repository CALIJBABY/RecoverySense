# RecoverySense Runnable Starter — Version 0.5.3

RecoverySense is a mobile and wearable **research prototype** for collecting passive smartwatch signals and brief ecological momentary assessments (EMA) to develop individualized behavioral-addiction craving-risk models. Sleep is a supporting context feature. The system is not a diagnostic device or a validated clinical intervention.

## Authoritative project paths

```text
apps/phone_flutter_new                 Current Flutter phone application
apps/wear_android/wear_android         Current Galaxy Watch/Wear OS application
backend/api                            Fail-closed FastAPI engineering prototype
firebase                               Current prototype Firestore notes/rules
ml                                     Craving and binary sleep/wake research pipelines
docs                                   Current and historical documentation
updates                                Versioned change manifests
scripts                                Setup, checks, and engineering scripts
```

Read `docs/CURRENT_DOCUMENTATION_INDEX.md` before relying on older project notes.

## Supported release targets

The validated development focus of this repository is currently **Android phone + Wear OS**. Flutter-generated iOS/macOS/web/Windows/Linux scaffolding is retained for future work but is not a configured RecoverySense release target; `firebase_options.dart` currently contains Android Firebase options only. The more developed iPhone/Apple Watch companion remains a separate baseline until it receives its own Xcode/parity audit.

## Current participant flow

```text
First authenticated use
  → one-time Baseline Assessment v1
  → five-page participant interface
      ├── Home: sensor-window Craving Risk Now probability + three top patterns
      ├── Live: heart rate, motion, rotation, steps, and signal quality
      ├── Check-in: deliberate 0–10 craving EMA
      ├── Sleep: block score, recording, timeline, and morning confirmation
      └── History: recent sleep and craving records

Settings remains in the Home app bar.
```

The main gauge is a model probability only when a schema-2 Firestore record proves it came from a completed sensor window plus available context. The latest EMA remains a separate 0–10 label and is never copied into that gauge. The model badge shows the actual selected model. The three displayed patterns are sorted positive local decision-tree contributions; when another model supplies the probability, they are companion-tree explanations rather than exact weights.

## Current data flow

```text
Galaxy Watch foreground health service
  → raw watch BPM + analysis-ready BPM + HR quality provenance
  → accelerometer + gyroscope
  → steps + optional off-body + screen state
  → optional future raw PPG (disabled)
  → queued Wear OS Data Items

Flutter phone
  → one-at-a-time authenticated ingestion
  → participant-scoped Firestore storage
  → 0–10 watch/phone EMA + local-time metadata
  → one-time baseline context
  → sleep-session controls and estimated sleep/wake
  → protected research-data export

Offline ML / optional prototype backend
  → causal preprocessing
  → pre-EMA feature windows + EMA labels
  → participant/session/time-separated evaluation
  → candidate-model comparison
  → selected risk model + interpretable decision-tree companion
  → versioned probability/explanation provenance
```

## Run the phone app

```powershell
cd apps\phone_flutter_new
flutter clean
flutter pub get
dart format lib
flutter analyze
flutter test
flutter run
```

The export feature continues to require the declared `archive` and `share_plus` dependencies. Run `flutter pub get` after applying an update.

## Build the current watch app

Open this exact folder in Android Studio:

```text
apps/wear_android/wear_android
```

Or run:

```powershell
cd apps\wear_android\wear_android
.\gradlew.bat clean assembleDebug
```

## Run research checks

```powershell
python scripts\research_static_audit.py
$env:PYTHONPATH = "ml/src"
python -m pytest -q ml/tests
$env:PYTHONPATH = "ml/src;backend/api"
python -m pytest -q backend/api/tests
```

## Important release state

- Required repeated EMA: one 0–10 craving/urge item.
- Baseline assessment: one-time contextual instrument; not a diagnostic scale and not direct feature weighting.
- Risk display: recent approved sensor-window model probability; EMA remains a separate training/validation label.
- Risk explanations: three sorted positive local decision-tree path contributions; predictive associations, not causes.
- ML time-of-day features: participant-local when timezone metadata are available; missing rather than silently UTC when they are not.
- Higher-risk times: descriptive repeated-EMA patterns with minimum-data safeguards, not clinical thresholds.
- Heart-rate quality: hard invalid/off-body/stale values are excluded from analysis-ready BPM while raw provenance is preserved; see `docs/HEART_RATE_QUALITY_LAYER.md`.
- Raw PPG: framework present, collection disabled until Samsung access and validation.
- Craving model: framework only; no real participant-validated craving model is enabled.
- Study check-in scheduling: app-active prototype timer only; OS-backed delivery after process termination is a pre-field blocker.
- Sleep: estimated binary sleep/wake; no validated stages or diagnosis.
- Storage: current prototype uses Firebase/Firestore; HIPAA status depends on the actual institutional service agreement, configuration, protocol, and operational controls, not the source code alone.

See:

- `CHANGELOG.md`
- `docs/HEART_RATE_QUALITY_LAYER.md`
- `docs/RESEARCH_UX_AUDIT_0.5.1.md`
- `docs/COMPETITIVE_UX_BENCHMARK_0.5.1.md`
- `docs/UI_DESIGN_SYSTEM_0.5.3.md`
- `docs/UI_DESIGN_SYSTEM_0.5.1.md`
- `docs/RESEARCH_VALIDATION_0.5.0.md`
- `docs/RESEARCH_AUDIT_0.4.2.md`
- `docs/RESEARCH_RELEASE_CHECKLIST.md`
- `updates/UPDATE_0.5.3_UI_CLEANUP.md`
- `updates/UPDATE_0.5.2_HEART_RATE_QUALITY.md`
- `updates/UPDATE_0.5.1_RESEARCH_UX_POLISH.md`
- `updates/UPDATE_0.5.0_PERSONALIZED_RISK_DASHBOARD.md`
