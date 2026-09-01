# RecoverySense Update 0.4.2 — Research Hardening

Release date: 2026-08-10  
Base: the user-uploaded `RecoverySenseRunnableStarter` snapshot created 2026-08-08.  
Installation scope: **phone + watch + ML/backend/docs**.  
Update form: patch to the existing repository; no new permanent repository is created.

## Purpose

This patch removes the participant-facing watch engineering status, consolidates the latest export/startup/background/sleep work into the existing project structure, corrects scientific/temporal inconsistencies, adds research safeguards, and creates a reproducible audit/release process.

## Files added

```text
CHANGELOG.md
apps/phone_flutter_new/android/app/src/main/res/xml/data_extraction_rules.xml
apps/phone_flutter_new/lib/services/export/research_data_export_service.dart
apps/phone_flutter_new/lib/widgets/research_data_export_card.dart
apps/wear_android/ACTIVE_PROJECT.md
backend/api/app/services/prototype_api_guard.py
backend/api/tests/test_research_safeguards.py
docs/CURRENT_DOCUMENTATION_INDEX.md
docs/PPG_READINESS.md
docs/RESEARCH_AUDIT_0.4.2.md
docs/RESEARCH_RELEASE_CHECKLIST.md
docs/RESEARCH_VALIDATION_MATRIX.md
ml/tests/test_research_safeguards.py
scripts/research_static_audit.py
scripts/run_research_checks.ps1
updates/UPDATE_0.4.2_RESEARCH_HARDENING.md
```

## Files modified

### Phone Flutter/native Android

```text
apps/phone_flutter_new/pubspec.yaml
apps/phone_flutter_new/README.md
apps/phone_flutter_new/android/app/src/main/AndroidManifest.xml
apps/phone_flutter_new/android/app/src/main/kotlin/com/recoverysense/wear/MainActivity.kt
apps/phone_flutter_new/lib/core/theme/app_theme.dart
apps/phone_flutter_new/lib/main.dart
apps/phone_flutter_new/lib/models/watch_sensor_batch.dart
apps/phone_flutter_new/lib/models/watch_sensor_sample.dart
apps/phone_flutter_new/lib/screens/dashboard/dashboard_screen.dart
apps/phone_flutter_new/lib/screens/settings/settings_screen.dart
apps/phone_flutter_new/lib/screens/watch/watch_screen.dart
apps/phone_flutter_new/lib/services/firebase/auth_service.dart
apps/phone_flutter_new/lib/services/firebase/firestore_sensor_repository.dart
apps/phone_flutter_new/lib/services/ingestion/sensor_ingestion_service.dart
apps/phone_flutter_new/lib/services/sleep/sleep_session_service.dart
apps/phone_flutter_new/lib/services/watch/watch_connection_service.dart
```

Key effects:

- Adds participant-scoped historical Firestore export to NDJSON/CSV ZIP.
- Adds `archive` and `share_plus`; `flutter pub get` must regenerate/update `pubspec.lock` locally.
- Starts ingestion after first frame and replays only one pending Data Item at a time.
- Rotates EMA/sensor/PPG backlog types.
- Adds release Internet permission, RecoverySense label, and backup/data-transfer exclusions.
- Removes direct email duplication from new participant research documents.
- Preserves session start timestamp.
- Standardizes fonts and corrects UI wording.
- Deletes temporary export files after the system share/save operation.

### Active Wear OS app

```text
apps/wear_android/wear_android/README.md
apps/wear_android/wear_android/app/build.gradle.kts
apps/wear_android/wear_android/app/src/main/AndroidManifest.xml
apps/wear_android/wear_android/app/src/main/java/com/recoverysense/wear/MainActivity.kt
apps/wear_android/wear_android/app/src/main/java/com/recoverysense/wear/sleep/SleepTrackingService.kt
apps/wear_android/wear_android/app/src/main/java/com/recoverysense/wear/watch/DataLayerService.kt
```

Key effects:

- Removes visible engineering recorder status from participant UI.
- Keeps service diagnostics/quality data internally.
- Fixes qualified recording-mode defaults.
- Adds transient Data Layer retry queues and normal-stop drain behavior.
- Removes the PPG-only sensitive permission while PPG is disabled and marks the boot receiver non-exported.
- Version becomes `0.4.2` / code `3`.

### Backend

```text
backend/api/app/main.py
backend/api/app/models/schemas.py
backend/api/app/routes/ema.py
backend/api/app/routes/sensors.py
backend/api/app/services/trigger_service.py
```

Key effects:

- Aligns schemas with current data fields and ranges.
- Makes prototype routes and engineering trigger fail closed unless explicitly enabled.
- Marks API as a research prototype.

### ML

```text
ml/config/default.yaml
ml/src/recoverysense_ml/inference.py
ml/src/recoverysense_ml/labeling.py
ml/src/recoverysense_ml/preprocessing.py
ml/src/recoverysense_ml/sleep_model.py
ml/src/recoverysense_ml/training.py
ml/tests/test_pipeline.py
ml/tests/test_sleep_model.py
```

Key effects:

- Causal prediction preprocessing.
- No future sleep inputs.
- Nearby low-EMA requirement for negative labels.
- Participant/session/purged-time evaluation hierarchy.
- Expanded discrimination/calibration/error metrics.
- Required streaming identity/timestamp.

### Documentation/configuration

```text
README.md
RECOVERYSENSE_UPDATE_SUMMARY.md
docs/ARCHITECTURE.md
docs/FIREBASE_NEXT_STEPS.md
docs/Firebase Later.md
docs/ML_FRAMEWORK_GUIDE.md
docs/SLEEP_TRACKING_AND_MODEL.md
docs/START_HERE.md
docs/Start Here.md
docs/WEEK4_TASKS.md
docs/WHAT_CHANGED_FROM_BREATHE.md
docs/WHAT_CHANGED_FROM_EMPTY_REPO.md
docs/Week 4 Scope.md
firebase/README.md
```

## Files deleted

```text
apps/phone_flutter_new/lib/models/sensor_snapshot.dart
apps/phone_flutter_new/lib/services/sensors/mock_sensor_service.dart
```

These two files were unused prototype/mock-only source and were removed so they cannot be mistaken for live research data paths. The legacy `apps/wear_android/app` project is retained for provenance but explicitly marked inactive. Generated caches/build files are not included in the patch.

## Database/schema impact

- Existing Firestore history is not deleted or migrated.
- Existing data remain exportable under the signed-in UID.
- Standard sensor schema remains version 4.
- New participant documents no longer add `email`; old documents are not altered.
- Export reads all supported historical documents under the participant, not only records created after installation.
- No raw PPG documents are created while PPG is disabled.

## Dependencies

Added to `apps/phone_flutter_new/pubspec.yaml`:

```text
archive: ^4.0.9
share_plus: ^11.1.0
```

`pubspec.lock` is intentionally not supplied by the patch because the Flutter/Dart package resolver is not available in the audit container. Run `flutter pub get` and commit the regenerated lockfile in the master repository.

## Validation performed

```text
ML pytest:       11 passed
Backend pytest:   4 passed
Python compile:   passed
Static audit:     61 checks passed
```

## Validation not performed in the audit environment

- Flutter analyzer/build/tests
- Android/Wear OS Gradle build
- Physical phone/watch test
- Firebase export against the user's live project
- Raw PPG acquisition
- Real EMA craving-model validation
- EEG/PSG sleep validation

## Known limitations

See `docs/RESEARCH_AUDIT_0.4.2.md` and `docs/RESEARCH_RELEASE_CHECKLIST.md`. No responsible software review can guarantee “100%” research or clinical validity without the remaining hardware, protocol, security, and empirical validation.

## Rollback

The patch apply script creates a timestamped backup at:

```text
.recovery_patches/pre_0.4.2_<timestamp>/
```

Restore backed-up files to their original relative paths to roll back. Added files are listed in this document and can be removed manually if a complete rollback is required.
