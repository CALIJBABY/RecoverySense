
# RecoverySense Update 0.5.3.5 - Research Export Stability

## Purpose

This hotfix applies the same participant research-data export flow to the current Android and iPhone Flutter applications. The export remains participant-scoped and produces lossless Firestore NDJSON plus analysis-ready CSV files.

## Corrected flow

```text
Signed-in participant
  -> wait for pending Firestore writes
  -> paginate participant collections
  -> decode heavy sensor/PPG batches four documents at a time
  -> stream NDJSON and fixed-schema CSV rows to disk
  -> spool dynamic CSV rows to disk rather than retaining all rows in memory
  -> flush long-running sinks periodically
  -> create and verify ZIP on a background Dart isolate
  -> share as application/zip with a valid platform origin
  -> retain temporary ZIP until stale cleanup
```

## Android crash assessment

The available project files do not include the Android `adb logcat` or Flutter exception from the moment of the crash, so one definitive root cause cannot be claimed. The prior source did, however, contain four concrete instability risks:

1. Firestore pages could contain 100 large sensor-batch documents at once.
2. Dynamic collections were accumulated as complete Dart lists before CSV writing.
3. ZIP compression ran on Flutter's UI isolate.
4. The temporary ZIP was deleted immediately after the share future returned.

The hotfix removes all four risks. A physical Android export with a short history and a long history remains the final runtime gate.

## Data integrity

- No synthetic labels are added.
- The signed-in Firebase UID remains the participant scope.
- Raw Firestore document paths and values remain available in NDJSON.
- Existing CSV column semantics remain intact.
- Export schema version 4 adds flow metadata to `manifest.json` but does not reinterpret participant measurements.
- Firestore remains the current data source; a later MongoDB adapter can produce the same CSV/NDJSON contract without changing the ML windowing and training pipeline.

## Build and test commands

Android phone:

```powershell
cd apps\phone_flutter_new
flutter clean
flutter pub get
flutter analyze
flutter run --release
```

iPhone:

```zsh
cd apps/phone_flutter_new
flutter clean
flutter pub get
flutter analyze
cd ios
pod install
open Runner.xcworkspace
```

## Required runtime validation

- Export with no or minimal research records.
- Export after several minutes of sensor batches.
- Export after a long multi-session history.
- Confirm ZIP opens and contains `manifest.json`, `raw/firestore_documents.ndjson`, and the expected CSV files.
- Confirm the phone remains responsive while the status reads `Compressing export...`.
- Confirm the shared/saved ZIP still opens after the system share sheet closes.
