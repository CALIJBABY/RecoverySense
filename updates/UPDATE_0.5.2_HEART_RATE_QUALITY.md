# RecoverySense Update 0.5.2 — Heart-Rate Quality Layer

**Release date:** 2026-08-11  
**Patch target:** existing `RecoverySenseRunnableStarter` repository only  
**Exact base:** RecoverySense 0.5.1 Research & UX Polish (`phone 0.5.1+8`, `watch 0.5.1 / versionCode 5`, `backend 0.5.1`, `ML 0.5.1`)  
**Result:** `phone 0.5.2+9`, `watch 0.5.2 / versionCode 6`, `backend 0.5.2`, `ML 0.5.2`

## Purpose

Version 0.5.2 adds an explicit, provenance-preserving heart-rate quality layer so a watch-provided BPM is not automatically treated as valid research data. Strong off-wrist/contact/status evidence, staleness, and a deliberately broad engineering plausibility boundary remove BPM from the analysis-ready stream while preserving raw values and quality reasons. A robust temporal outlier detector is stored as a soft flag rather than silently deleting plausible rapid physiological changes.

This update also corrects a pre-existing off-body semantic inversion discovered during the audit: Android/Samsung report `1.0=on-body` and `0.0=off-body`, whereas RecoverySense watch schema <=4 had stored that signal under an `offBody` name without inversion.

## Added files

```text
apps/phone_flutter_new/lib/models/heart_rate_quality.dart
apps/wear_android/wear_android/app/src/main/java/com/recoverysense/wear/sensors/HeartRateQualityGate.kt
apps/wear_android/wear_android/app/src/test/java/com/recoverysense/wear/sensors/HeartRateQualityGateTest.kt
docs/HEART_RATE_QUALITY_LAYER.md
ml/tests/test_heart_rate_quality.py
updates/UPDATE_0.5.2_HEART_RATE_QUALITY.md
```

## Modified areas

### Watch

- Corrects low-latency off-body interpretation: `1=on-body`, `0=off-body` from Android is converted to RecoverySense `offBody=true` only when the platform value is below 0.5.
- Adds a pure-Kotlin `HeartRateQualityGate`.
- Rejects hard-invalid/no-contact/unreliable/off-body/stale/broad-implausible BPM from analysis-ready samples.
- Preserves positive raw BPM separately.
- Records stable quality code, hard-validity flag, and temporal-outlier flag per sample.
- Advances Wear sensor schema to version 5.
- Adds JUnit test dependency for the pure quality gate.

### Phone

- Parses new raw/validity/quality/outlier fields for live and batch Data Layer payloads.
- Normalizes watch schema <=4 off-body semantics.
- Prevents legacy off-body samples from being marked HR-valid during parsing.
- Stores analysis-ready and raw HR plus quality provenance in Firestore sensor samples.
- Advances general phone sensor/storage schema to 5.
- Extends research CSV export with HR quality fields.
- Normalizes historical off-body values during CSV export while avoiding double inversion for storage schema 5 records.
- Keeps lossless raw Firestore NDJSON unchanged.
- Advances new phone-derived sleep epochs/summaries to `rules-v2-hr-quality` and records HR-quality semantics provenance; historical `rules-v1` summaries should be recomputed from normalized raw sensor batches before research analysis.

### ML

- Adds raw-HR, validity, quality-code, and temporal-outlier schema columns.
- Excludes hard-invalid/off-body/stale HR before analysis.
- Re-applies hard-invalid masks after interpolation and median smoothing so invalid HR cannot be recreated by preprocessing.
- Keeps temporal outliers by default and makes exclusion an explicit sensitivity-analysis option.
- Adds per-reason HR quality features/metrics.
- Normalizes historical off-body values in the Python Firestore CSV exporter without double-inverting storage schema 5 records.
- Adds dedicated heart-rate quality tests.

### Backend

- Accepts HR quality provenance fields.
- Allows analysis-ready `heart_rate` to be null when the watch quality gate rejects the value.
- Engineering-only universal HR threshold fallback refuses to trigger when no analysis-ready HR exists.

## Database / schema changes

No destructive Firestore migration is performed.

- Wear sensor Data Layer schema: `4 → 5`.
- General phone/Firestore sensor storage schema: `4 → 5`.
- Research ZIP export schema: `2 → 3`.
- Added sample fields: `raw_heart_rate`, `heart_rate_valid`, `heart_rate_quality_code`, `heart_rate_quality_reason`, `heart_rate_outlier_flag`.
- Existing `off_body` is normalized to true=off-body for new storage schema 5 writes.
- Historical raw documents remain unchanged.

### Historical off-body migration rule

Historical storage schema <=4 and watch schema <=4 used inverted semantics. v0.5.2 exporters normalize those records on analysis export. Pending legacy watch batches ingested by v0.5.2 are normalized before Firestore storage and carry storage schema 5, preventing a later second inversion.

**Action:** regenerate previously exported sensor CSVs before using historical off-body fields in analysis.

## Threshold policy

Hard watch plausibility boundary: **30–220 BPM**. This is a broad engineering sanity boundary, not a normal-range, clinical, or craving threshold.

Temporal outlier rule: 60-second rolling median/MAD history; at least 5 prior sensor-valid events; flag when deviation exceeds `max(30 BPM, 5×MAD with a 1 BPM MAD floor)`. This flag is soft and values remain analysis-usable by default.

## Dependencies

- Added watch test dependency: `junit:junit:4.13.2`.
- No new Flutter runtime dependency.
- No new Python runtime dependency.
- Raw Samsung PPG remains disabled; no Samsung raw-PPG dependency is activated.

## Install scope

- **Phone:** rebuild/reinstall required.
- **Watch:** rebuild/reinstall required.
- **ML:** use the v0.5.2 preprocessing/config for new analyses; regenerate historical sensor CSV exports.
- **Backend:** redeploy only if the prototype API is being used.
- **Database:** no destructive rewrite; exports normalize legacy values.

## Validation performed in packaging environment

The release package records exact results. Validation includes Python ML tests, backend tests, Python compilation, the pure-Kotlin quality gate harness, static schema/transport checks, patch checksum validation, clean-base patch simulation, and ZIP integrity.

## Explicitly untested here

- Flutter/Dart analyzer/tests/build.
- Full Wear OS Android Gradle build if dependency resolution is unavailable.
- Physical Galaxy Watch off-body/no-contact behavior.
- Screen-off HR continuity and battery behavior.
- Live Firestore round-trip/export on the user's project.
- Final pilot-derived review of the 30–220 boundary/outlier parameters.
- Any clinical interpretation of HR quality.

## Known limitations

- The low-latency off-body sensor may be unavailable on some Wear OS hardware; RecoverySense records that capability and falls back to available status/staleness/plausibility evidence.
- The temporal outlier rule is an engineering quality flag, not a validated artifact classifier.
- Low-accuracy Android status remains usable but explicitly labeled; sensitivity analyses can examine its impact.
- Historical raw Firestore off-body values are not rewritten, by design.

## Rollback

The patch apply script creates a timestamped `.recovery_patches/pre_0.5.2_*` backup of all touched paths. The rollback script restores the exact pre-update files and removes added v0.5.2 files. Firestore data written while 0.5.2 is installed are not deleted by source-code rollback.
