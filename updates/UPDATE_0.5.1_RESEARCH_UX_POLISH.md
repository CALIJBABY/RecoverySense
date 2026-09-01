# RecoverySense Update 0.5.1 — Research & UX Polish

**Release date:** 2026-08-11  
**Patch target:** existing `RecoverySenseRunnableStarter` repository only  
**Exact base:** RecoverySense 0.5.0 Personalized Risk Dashboard (`phone 0.5.0+7`, `watch 0.5.0 / versionCode 4`, `backend 0.5.0`, `ML 0.5.0`)  
**Result:** `phone 0.5.1+8`, `watch 0.5.1 / versionCode 5`, `backend 0.5.1`, `ML 0.5.1`

## Purpose

Version 0.5.1 is a repository-wide research-quality and participant-UX hardening pass. It does not create a new RecoverySense repository and it does not claim clinical validation. The update reviews every packaged file through the repository inventory audit, performs deeper checks on active authored source/configuration, aligns participant-facing hierarchy with current craving/addiction/gambling-recovery product patterns, and corrects research-data integrity, time handling, privacy, documentation, and project-structure inconsistencies discovered during the audit.

## High-level change summary and rationale

### Phone / participant UX

- Keeps the latest 0–10 EMA self-report as the primary **Craving Now** gauge and keeps algorithmic risk visually and semantically separate.
- Makes model probability restrained and transparent, with up to three positive local decision-tree contributors and explicit noncausal wording.
- Makes Higher-Risk Times labels self-explanatory by showing an explicit proportion of independently timed ratings at or above the descriptive 7/10 threshold.
- Requires deliberate interaction before EMA, baseline, or morning sleep default-looking values can be stored as participant responses.
- Cleans login, registration, dashboard, settings, watch-data, history, sleep, splash, and export surfaces so participant-facing UI does not expose backend/session/debug information or raw exception strings.
- Adds gauge endpoint labels and accessibility semantics.

### Watch / Wear OS

- Keeps the engineering recorder-status section removed.
- Requires deliberate watch EMA selection before save.
- Keeps the lighter green/soft-card design and standardized 48 dp primary EMA action.
- Adds current Android/Wear OS granular health permissions for API 36 while capping legacy body-sensor permissions at API 35.
- Keeps raw Samsung PPG disabled and does not declare the raw-PPG-only permission.
- Removes the obsolete sibling Wear OS project so `apps/wear_android/wear_android` is the single active watch project.

### Sleep / history

- Fixes a duplicate Dart named argument in the sleep date picker.
- Uses canonical `sleep_sessions` in History instead of legacy `sleep_logs`.
- Corrects subjective sleep quality to the implemented 1–5 scale.
- Requires wake time after sleep onset and deliberate morning-confirmation responses.
- Persists a stable watch-start failure code rather than raw exception text.

### ML / interpretation / time

- Fixes config path resolution so tests/CLI can be run from either repository root or `ml/`.
- Corrects cyclic time features to participant-local time using captured timezone-offset metadata; missing local-time context remains missing with an explicit availability feature rather than silently using UTC as local.
- Uses the same local-time transformation in training and streaming inference.
- Preserves participant/session/time-aware validation and local decision-tree path contributions.

### Backend / Firebase

- Bounds optional timezone-offset input and aligns prior sleep-quality/rested fields with the implemented 1–5 scales.
- Real persisted predictions explicitly carry participant-display provenance; demo predictions remain blocked from participant display.
- Model-status responses no longer expose raw model-loader errors or server filesystem paths.
- Firestore rules make baseline assessment write-once, legacy `sleep_logs` read-only, and server-authored prediction/trigger collections read-only to participant clients.

### Repository / documentation

- Adds a repository-wide SHA-256 inventory and quality audit.
- Removes generated/cache/build metadata and generated ML demonstration artifacts from the release tree.
- Removes TODO-only Apple Watch placeholder files that could be mistaken for a current implementation.
- Adds the v0.5.1 competitive UX benchmark, participant UI design system, research/UX audit, and this update record.
- Preserves historical planning files but clearly marks them as historical relative to v0.5.1.

## Database / schema changes

No destructive database migration is performed.

Additive/contract changes:

- Existing EMA `local_minute_of_day` and `timezone_offset_minutes` fields are now also used consistently by the ML pipeline.
- Backend sensor schema accepts optional `timezone_offset_minutes` bounded from `-840` through `840` minutes.
- Backend prior sleep quality and rested score are constrained to `1..5`, matching the current participant instrument.
- New sleep-start failures write `start_error_code: "watch_start_failed"` instead of persisting raw exception strings. Historical `start_error` fields are not deleted or rewritten.
- Server-authored real risk predictions persist `participant_display_allowed: true` and `demo_only: false`; participant UI remains fail-closed for missing/invalid provenance.
- Firestore client-write permissions are tightened for baseline/model/prediction/trigger collections as documented in `firebase/firestore.rules`.

## Dependencies

**New dependencies in 0.5.1:** None.

The v0.5.0 export feature already declared Flutter dependencies `archive` and `share_plus`. The packaged `pubspec.lock` still predates those declarations because Flutter/Dart is unavailable in the audit environment. **Run `flutter pub get` on the development machine before any release build and commit the regenerated lockfile after review.** Do not fabricate dependency hashes.

Raw Samsung PPG remains disabled. No new Samsung SDK dependency is enabled by this update.

## Install scope

- **Phone:** rebuild/reinstall required.
- **Watch:** rebuild/reinstall required because watch version, permissions, and participant EMA UI changed.
- **Backend:** redeploy required only if the prototype API/backend is being used.
- **ML:** retrain/regenerate bundles when using the changed local-time feature pipeline; do not mix old feature-schema bundles with the new code without schema/version verification.
- **iPhone/Apple Watch:** not part of this Android 0.5.1 release and not claimed at parity.

## Validation performed in the audit environment

The final validation artifact records exact counts. Release checks include:

- repository-wide file inventory and SHA-256 scan;
- source/configuration static audit;
- ML tests from the repository root;
- ML tests from the `ml/` working directory;
- backend safeguard tests;
- Python `compileall`;
- JSON/YAML/XML parsing;
- local Dart import resolution;
- active-source conflict-marker/empty-source checks;
- watch/native-phone/Dart transport-contract checks;
- clean-base patch simulation and payload SHA-256 verification;
- ZIP integrity check.

## Explicitly not validated here

The following must not be reported as passed until run on the appropriate development machine/device:

- `flutter pub get`
- `dart format lib`
- `flutter analyze`
- `flutter test`
- `flutter build apk --release`
- Wear OS Gradle dependency resolution and APK build
- Galaxy S21 + Galaxy Watch4 install/permission/transport tests
- screen-off heart-rate continuity, battery, reboot, and Data Layer backlog behavior
- live Firestore export round-trip
- Xcode/iPhone/Apple Watch build/parity
- raw Samsung PPG acquisition
- real EMA-labeled craving-model performance/generalization
- sleep validation against synchronized reference labels/PSG where required by claims

## Known limitation / pre-field blocker

The morning/afternoon/evening study-check-in scheduler remains an **app-process timer**. It does not guarantee delivery once the Android process is terminated. A field study that depends on scheduled/random EMA must use a validated OS-backed scheduler/notification path and test process death, reboot, Doze/battery restrictions, timezone changes, and delivery/response logging before participant enrollment.

## Rollback / migration notes

- The update-only patch creates a timestamped `.recovery_patches/pre_0.5.1_*` backup before modifying/deleting files.
- The rollback script restores modified/deleted files from that backup and removes files added by the patch.
- Additive Firestore documents are not deleted by code rollback.
- Historical records containing old raw `start_error` fields are left untouched.
- If a 0.5.1 model bundle is produced using the local-time feature semantics, do not deploy it with 0.5.0 inference code after rollback without explicit feature-schema compatibility checks.

## Exact file changes

The release package includes `FILES_ADDED_MODIFIED_DELETED.csv`, generated by SHA-256 comparison against the exact 0.5.0 base. It is the authoritative per-file change list for this update. Deleted entries include generated/cache artifacts, the obsolete sibling Wear OS project, and three TODO-only Apple Watch placeholders; no participant research records are deleted by the patch.


## Added files — exact paths

```text
.gitignore
docs/COMPETITIVE_UX_BENCHMARK_0.5.1.md
docs/RESEARCH_UX_AUDIT_0.5.1.md
docs/UI_DESIGN_SYSTEM_0.5.1.md
ml/tests/test_config_paths.py
scripts/repository_quality_audit.py
updates/UPDATE_0.5.1_RESEARCH_UX_POLISH.md
```

## Modified files — exact paths

```text
CHANGELOG.md
CURRENT_BUILD_INFO.txt
CURRENT_UPDATE_SUMMARY.md
README.md
RECOVERYSENSE_UPDATE_SUMMARY.md
apps/phone_flutter_new/README.md
apps/phone_flutter_new/lib/core/constants/app_strings.dart
apps/phone_flutter_new/lib/models/risk_prediction.dart
apps/phone_flutter_new/lib/screens/dashboard/dashboard_screen.dart
apps/phone_flutter_new/lib/screens/ema/ema_screen.dart
apps/phone_flutter_new/lib/screens/history/history_screen.dart
apps/phone_flutter_new/lib/screens/login/login_screen.dart
apps/phone_flutter_new/lib/screens/onboarding/baseline_assessment_screen.dart
apps/phone_flutter_new/lib/screens/register/register_screen.dart
apps/phone_flutter_new/lib/screens/settings/settings_screen.dart
apps/phone_flutter_new/lib/screens/sleep/sleep_screen.dart
apps/phone_flutter_new/lib/screens/splash/splash_screen.dart
apps/phone_flutter_new/lib/screens/watch/watch_screen.dart
apps/phone_flutter_new/lib/services/ema/ema_prompt_service.dart
apps/phone_flutter_new/lib/services/firebase/auth_service.dart
apps/phone_flutter_new/lib/services/firebase/sleep_repository.dart
apps/phone_flutter_new/lib/widgets/craving_gauge.dart
apps/phone_flutter_new/lib/widgets/research_data_export_card.dart
apps/phone_flutter_new/pubspec.yaml
apps/watch_ios/README.md
apps/wear_android/ACTIVE_PROJECT.md
apps/wear_android/wear_android/README.md
apps/wear_android/wear_android/app/build.gradle.kts
apps/wear_android/wear_android/app/src/main/AndroidManifest.xml
apps/wear_android/wear_android/app/src/main/java/com/recoverysense/wear/MainActivity.kt
backend/api/app/main.py
backend/api/app/models/schemas.py
backend/api/app/routes/sensors.py
backend/api/app/services/model_service.py
backend/api/app/services/prediction_record_service.py
backend/api/tests/test_research_safeguards.py
docs/ARCHITECTURE.md
docs/CURRENT_DOCUMENTATION_INDEX.md
docs/EMA_QUESTIONS.md
docs/FIREBASE_NEXT_STEPS.md
docs/Firebase Later.md
docs/ML_FRAMEWORK_GUIDE.md
docs/PPG_READINESS.md
docs/RESEARCH_RELEASE_CHECKLIST.md
docs/SLEEP_TRACKING_AND_MODEL.md
docs/START_HERE.md
docs/Start Here.md
docs/WEEK4_TASKS.md
docs/WHAT_CHANGED_FROM_BREATHE.md
docs/WHAT_CHANGED_FROM_EMPTY_REPO.md
docs/Week 4 Scope.md
firebase/README.md
firebase/firestore.rules
ml/README.md
ml/pyproject.toml
ml/src/recoverysense_ml/config.py
ml/src/recoverysense_ml/dataset.py
ml/src/recoverysense_ml/inference.py
ml/src/recoverysense_ml/synthetic.py
ml/src/recoverysense_ml/training.py
ml/tests/test_research_safeguards.py
scripts/research_static_audit.py
```

## Deleted files — exact paths

```text
apps/phone_flutter_new/.flutter-plugins-dependencies
apps/phone_flutter_new/android/phone_flutter_new_android.iml
apps/phone_flutter_new/ios/Flutter/Generated.xcconfig
apps/phone_flutter_new/ios/Flutter/flutter_export_environment.sh
apps/phone_flutter_new/phone_flutter_new.iml
apps/watch_ios/RecoverySenseWatch/Services/HealthSensorService.swift
apps/watch_ios/RecoverySenseWatch/Services/MotionSensorService.swift
apps/watch_ios/RecoverySenseWatch/Views/WatchDashboardView.swift
apps/wear_android/app/build.gradle.kts
apps/wear_android/app/src/main/AndroidManifest.xml
apps/wear_android/app/src/main/java/edu/uci/recoverysense/wear/MainActivity.kt
apps/wear_android/app/src/main/java/edu/uci/recoverysense/wear/SensorCollector.kt
apps/wear_android/app/src/main/java/edu/uci/recoverysense/wear/SensorReading.kt
apps/wear_android/app/src/main/java/edu/uci/recoverysense/wear/WearDataClient.kt
apps/wear_android/app/src/main/java/edu/uci/recoverysense/wear/WearMessagePaths.kt
apps/wear_android/app/src/main/res/values/styles.xml
apps/wear_android/build.gradle.kts
apps/wear_android/gradle.properties
apps/wear_android/gradle/gradle-daemon-jvm.properties
apps/wear_android/gradle/wrapper/gradle-wrapper.jar
apps/wear_android/gradle/wrapper/gradle-wrapper.properties
apps/wear_android/gradlew
apps/wear_android/gradlew.bat
apps/wear_android/local.properties
apps/wear_android/settings.gradle.kts
apps/wear_android/wear_android/.kotlin/errors/errors-1784625412533.log
ml/.pytest_cache/.gitignore
ml/.pytest_cache/CACHEDIR.TAG
ml/.pytest_cache/README.md
ml/.pytest_cache/v/cache/lastfailed
ml/.pytest_cache/v/cache/nodeids
ml/data/processed/training_windows.csv
ml/data/raw/ema_events.csv
ml/data/raw/sensor_readings.csv
ml/models/random_forest_bundle.joblib
ml/reports/metrics.json
ml/reports/test_predictions.csv
ml/src/recoverysense_ml.egg-info/PKG-INFO
ml/src/recoverysense_ml.egg-info/SOURCES.txt
ml/src/recoverysense_ml.egg-info/dependency_links.txt
ml/src/recoverysense_ml.egg-info/entry_points.txt
ml/src/recoverysense_ml.egg-info/requires.txt
ml/src/recoverysense_ml.egg-info/top_level.txt
ml/src/recoverysense_ml/__pycache__/__init__.cpython-313.pyc
ml/src/recoverysense_ml/__pycache__/config.cpython-313.pyc
ml/src/recoverysense_ml/__pycache__/dataset.cpython-313.pyc
ml/src/recoverysense_ml/__pycache__/explainability.cpython-313.pyc
ml/src/recoverysense_ml/__pycache__/features.cpython-313.pyc
ml/src/recoverysense_ml/__pycache__/inference.cpython-313.pyc
ml/src/recoverysense_ml/__pycache__/labeling.cpython-313.pyc
ml/src/recoverysense_ml/__pycache__/ppg.cpython-313.pyc
ml/src/recoverysense_ml/__pycache__/preprocessing.cpython-313.pyc
ml/src/recoverysense_ml/__pycache__/schema.cpython-313.pyc
ml/src/recoverysense_ml/__pycache__/sleep_model.cpython-313.pyc
ml/src/recoverysense_ml/__pycache__/synthetic.cpython-313.pyc
ml/src/recoverysense_ml/__pycache__/training.cpython-313.pyc
ml/tests/__pycache__/test_explainability.cpython-313-pytest-9.0.2.pyc
ml/tests/__pycache__/test_features.cpython-313-pytest-9.0.2.pyc
ml/tests/__pycache__/test_pipeline.cpython-313-pytest-9.0.2.pyc
ml/tests/__pycache__/test_ppg.cpython-313-pytest-9.0.2.pyc
ml/tests/__pycache__/test_research_safeguards.cpython-313-pytest-9.0.2.pyc
ml/tests/__pycache__/test_sleep_context.cpython-313-pytest-9.0.2.pyc
ml/tests/__pycache__/test_sleep_model.cpython-313-pytest-9.0.2.pyc
```
