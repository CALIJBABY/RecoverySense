# RecoverySense Phone App — Version 0.5.3

The Flutter phone app authenticates the participant, runs a one-time contextual Baseline Assessment, receives queued Galaxy Watch data, stores participant-scoped records, supports the 0–10 EMA fallback, displays personalized research patterns/model explanations when available, manages independent sleep recording, and exports historical research data.

## Current functions

- Firebase Authentication
- One-time Baseline Assessment v1 after first authenticated use
- Craving Risk Now semicircular gauge driven by a recent approved sensor-window model probability
- Actual selected-model badge plus three automatically sorted local decision-tree explanation patterns
- Latest 0–10 EMA shown separately as the most recent check-in
- Five-icon bottom navigation with dedicated Live Sensors, Check-in, Sleep, and History screens
- Higher-risk time-of-day pattern from independently timed repeated EMA after minimum-data safeguards
- Bounded one-item-at-a-time sensor/PPG/EMA ingestion
- Clean participant-facing live watch measurements; engineering diagnostics remain internal
- HR quality provenance: raw BPM, analysis-ready BPM, validity/reason/outlier fields, and legacy off-body normalization
- Phone fallback EMA: craving/urge 0–10
- Time-stratified app-active EMA sampling across morning/afternoon/evening (prototype timer)
- Sleep start/stop, provisional estimated sleep/wake, and deliberate morning confirmation fields
- Firestore storage for raw batches, EMA, baseline, sleep, quality, and optional model records
- Settings → Research Data Export

Participant-facing default values are never treated as submitted EMA/baseline/morning-confirmation responses until the participant deliberately interacts with the control.

The export creates lossless NDJSON plus CSVs for historical and new data under the signed-in participant UID, including baseline-assessment data, local EMA timing fields, and HR quality provenance. For historical storage schema <=4, CSV `off_body` is normalized to true=off-body while raw NDJSON remains unchanged; regenerate older CSV exports before analysis. The app's temporary ZIP is removed after the system share/save action; the user-saved copy remains and must be protected.

## Participant-facing visual system

Primary green is `#4F9B17`, sampled from the supplied rounded-button reference. Bright-green actions use dark text, a 50 logical-pixel height, and a 14-pixel corner radius. Standard cards use a 20-pixel radius. Settings remains in the dashboard app bar.

## Run and verify

```powershell
flutter clean
flutter pub get
dart format lib
flutter analyze
flutter test
flutter run
```

`flutter pub get` must update/verify `pubspec.lock` for the declared dependencies.

## Research limitations

- Baseline context is self-report and does not determine model weights by itself.
- Time-of-day patterns require adequate independently timed repeated EMA and remain descriptive.
- The gauge fails closed unless model provenance proves a sensor-window prediction; the latest EMA is never copied into it.
- Model contributors are associations from an interpretable companion decision tree, not causal factors or exact random-forest weights unless model and explanation provenance identify the same tree.
- Model clock features use participant-local timezone metadata when available; missing offsets do not silently become UTC routine features.
- App-active timers do not guarantee scheduled EMA delivery after process termination.
- Raw PPG remains disabled until Samsung access and validation.
- Sleep output is estimated binary sleep/wake, not validated stages or diagnosis.
- No real validated craving model is currently enabled.
- Authentication/storage configuration, institutional approval, BAA where applicable, enrollment control, retention, and incident response must be approved separately before participant deployment.


## Platform note

Android is the configured release target in this repository. Flutter-generated iOS/macOS/web/Windows/Linux wrappers remain scaffolding and are not configured with RecoverySense Firebase/platform credentials. Do not describe those wrappers as validated releases.
