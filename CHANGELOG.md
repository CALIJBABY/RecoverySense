# RecoverySense Changelog

All notable changes to the active RecoverySense Android/Wear OS research prototype are recorded here. The permanent repository root remains `RecoverySenseRunnableStarter`; release archives and patches may carry versioned filenames, but they are not separate repositories.

## 0.5.3 — UI cleanup and sensor-backed risk dashboard — 2026-08-11

### Participant interface

- Applied the requested lighter `#4F9B17` green, dark button text, 14 px rounded primary actions, and 20 px rounded cards.
- Added five-icon bottom navigation for Home, Live, Check-in, Sleep, and History while keeping Settings in the dashboard app bar.
- Moved live sensor data and sleep context to dedicated screens.
- Added a ten-block watch-derived sleep-efficiency bar and removed the duplicated latest-night summary.
- Updated the Wear OS participant surface to compact Sensors and Check-in pages with rounded bottom controls.

### Craving-risk display and provenance

- Changed the main gauge from the latest EMA self-report to a recent approved model probability.
- Shows the actual selected model name; Random forest appears only when `model_name=random_forest`.
- Sorts and displays the three strongest positive local explanation patterns and refreshes them on new approved prediction records.
- Adds schema-2 provenance proving the prediction came from a completed sensor window plus available context and that the current EMA was not copied into the score.
- Fails closed for legacy, demo, stale, incomplete, or non-approved model records.
- Keeps EMA visible separately as the repeated 0–10 training/validation label.

### Interpretation boundary

- When a non-tree model supplies the probability, the three pattern boxes remain companion decision-tree explanations, not exact random-forest weights.
- Displayed contributors remain predictive associations rather than causal triggers.

## 0.5.2 — Heart-rate quality layer and off-body semantics correction — 2026-08-11

### Wear OS heart-rate quality

- Added a pure-Kotlin heart-rate quality gate before BPM becomes analysis-ready research data.
- Corrected low-latency off-body interpretation to Android/Samsung semantics: platform `1.0` means on-body and `0.0` means off-body; RecoverySense now stores `off_body=true/1` only while removed.
- Hard-rejects Android no-contact/unreliable status, explicit off-body state, HR older than 90 seconds, and values outside a broad 30–220 BPM engineering plausibility boundary.
- Preserves low-accuracy readings but labels them explicitly.
- Adds a 60-second rolling median/MAD temporal-outlier flag after at least five prior sensor-valid events. This flag is soft by default and sustained valid transitions update the rolling reference.
- Preserves positive raw watch BPM separately from analysis-ready BPM.
- Advances the Wear sensor Data Layer schema to 5 and adds validity, quality-code, and temporal-outlier arrays/live fields.

### Phone, storage, and export

- Added a shared Dart HR quality-code model and extended live/batch parsing with raw BPM, hard-validity, quality code, and temporal-outlier provenance.
- Normalizes watch schema <=4 off-body values and prevents normalized legacy off-body samples from being treated as HR-valid.
- Advances general phone/Firestore sensor storage schema from 4 to 5 and writes quality provenance per sensor sample.
- Extends `sensor_readings.csv` with watch schema, raw HR, validity, quality code/reason, and outlier fields.
- Correctly distinguishes historical storage schema <=4 from newly normalized storage schema 5 so pending legacy watch batches are not double-inverted during later export.
- Keeps raw Firestore NDJSON unchanged for provenance. Previously exported sensor CSVs should be regenerated before analysis of historical off-body data.

### ML and backend

- Adds HR quality columns/configuration and per-reason quality features.
- Re-applies hard HR masks after interpolation and median smoothing so preprocessing cannot recreate invalid/off-body/stale BPM.
- Keeps temporal outlier exclusion disabled by default; it is an explicit sensitivity-analysis setting.
- Python Firestore export normalizes historical off-body semantics using both watch and storage schema versions.
- Backend accepts nullable analysis-ready HR plus quality provenance, and engineering-only universal HR threshold fallback refuses to trigger without a valid analysis-ready HR value.
- Adds dedicated HR quality tests and Wear JUnit coverage.

### Interpretation and validation limits

- The 30–220 BPM range is an engineering sanity boundary, not a clinical normal range, diagnosis, or craving threshold.
- The temporal-outlier rule is an engineering quality flag, not a validated artifact classifier.
- Physical Galaxy Watch remove/re-wear, no-contact, screen-off, battery, and export round-trip tests remain required before participant field deployment.


## 0.5.1 — Repository-wide research and UX polish — 2026-08-11

### Participant interface and response integrity

- Re-benchmarked participant-facing hierarchy against current public Reframe, I Am Sober, SMART Recovery, Evive, Betttr, and other gambling-recovery product patterns without copying commercial branding or gamification.
- Refined the dashboard to keep **Craving Now** (participant self-report) visually primary and **Personalized Risk Estimate** explicitly separate.
- Added a restrained probability progress indicator and clearer plain-language descriptions for local decision-tree contributors and higher-risk-time summaries.
- Added 0 and 10 endpoint labels and accessibility semantics to the custom craving gauge.
- Removed participant-facing research/backend diagnostics from the main dashboard and moved technical model provenance behind secondary disclosure.
- Added deliberate-response safeguards so phone/watch EMA, baseline sliders/time fields, and morning sleep confirmation cannot silently save untouched visual defaults as real research responses.
- Improved login, registration, splash, watch-data, history, settings, sleep, and export copy to be concise, nonjudgmental, and participant-facing; raw exception text remains in debug logs rather than the UI.

### Sleep and history consistency

- Fixed a duplicated `initialDate` argument in the sleep date picker that would prevent Dart compilation.
- Repaired History to read canonical `sleep_sessions` rather than legacy `sleep_logs` and corrected subjective sleep-quality display to the implemented 1–5 scale.
- Requires reported final wake time to be after reported sleep onset before morning confirmation can be saved.
- Replaced persisted raw watch-start exception text with the stable `watch_start_failed` code.
- Removed provisional epoch/model diagnostics from the primary participant sleep surface while preserving research data internally.

### Time, modeling, and prediction-display safeguards

- Corrected craving-model cyclic clock features to use participant-local time derived from captured timezone-offset metadata instead of silently using UTC as local routine time.
- Adds `local_time_context_available`; when local-time metadata are missing or invalid, cyclic local-time features remain missing instead of being fabricated.
- Applies the same local-time transform in training and inference.
- Keeps participant display fail-closed for incomplete, demo, stale, or non-approved prediction records and caps displayed positive local contributors at three.
- Real backend prediction records now explicitly carry `participant_display_allowed=true` and `demo_only=false`; normal clients cannot write server-authored model/prediction collections under current Firestore rules.
- Model-status responses no longer expose server filesystem paths or raw model-loader exception text.

### Authentication and data governance

- Successful sign-in/account creation now ensures the participant research profile exists; a profile-initialization failure signs the client out rather than leaving a partial authenticated state.
- Research participant documents continue to avoid duplicating email identifiers.
- Firestore rules make baseline assessment write-once, legacy `sleep_logs` read-only, and server-authored prediction/trigger collections read-only to participant clients.
- Backend sensor schema now bounds optional timezone offsets and aligns prior sleep-quality/rested inputs with the implemented 1–5 scales.

### Wear OS permissions and repository hygiene

- Added Wear OS 6/API 36 granular heart-rate permissions while capping legacy `BODY_SENSORS` permissions at API 35; raw-PPG-only permission remains undeclared while PPG is disabled.
- Removed the obsolete duplicate Wear OS sibling project so `apps/wear_android/wear_android` is the only active Android watch project.
- Removed TODO-only Apple Watch placeholder files that could be mistaken for current implementation; the separate iPhone/Apple Watch companion remains outside Android release parity.
- Removed generated Flutter environment files, IDE module files, ML demo outputs/models, Python caches, package metadata, and stale Kotlin cache logs from the release tree.
- Added repository-wide `.gitignore` coverage for build products, caches, local properties, secrets, generated ML outputs, and IDE artifacts.

### Research tooling and documentation

- Added a full repository inventory/static quality audit with SHA-256 coverage for every packaged file and explicit PASS/WARN/INFO/FAIL classification.
- Added a competitive UX benchmark, current UI design system, and v0.5.1 research/UX audit.
- Fixed ML config loading so documented repository-relative paths resolve from either the repository root or the `ml/` working directory.
- Expanded static and automated safeguard tests for response integrity, local-time features, permissions, Firestore write protections, model provenance, and source/project hygiene.
- Historical planning documents remain preserved but are explicitly labeled as not describing the current build.

### Known pre-field blocker

- The current morning/afternoon/evening study-check-in scheduler is app-process based. It does **not** guarantee prompt delivery after the Android process is terminated. A validated OS-backed scheduler/notification path and physical-device delivery testing remain required before field enrollment that depends on scheduled/random EMA.

### Validation boundary

- Python/ML/backend/static/repository checks are run for this release and recorded in the v0.5.1 validation artifact.
- Flutter dependency resolution/analyzer/tests/APK build, Wear OS Gradle build, physical Galaxy phone/watch validation, Firestore round-trip export, and Xcode/iPhone validation remain separate required checks and must not be represented as passed until run in those environments.

## 0.5.0 — Personalized risk dashboard, baseline assessment, and local explanations — 2026-08-10

### Participant interface

- Added a semicircular **Craving Now** gauge driven only by the latest 0–10 EMA self-report.
- Added a separate **Current Model Estimate** so participant-reported craving is not conflated with algorithmic risk.
- Added up to three positive local decision-tree path contributors with explicit noncausal wording and selected/interpretability model provenance.
- Added a **Higher-Risk Times** card using independently timed repeated EMA after minimum-data safeguards.
- Added a five-step one-time **Baseline Assessment v1** for new/authenticated users who have not completed it.
- Lightened the primary UI green to `#3D844B` and standardized participant EMA/onboarding CTAs at 48 logical px/dp high with 2 px/dp corners as a visual reference to the requested Groupon Buy-action proportions.
- Applied the new green and CTA dimensions to the watch EMA action while keeping engineering recorder status hidden.

### EMA and temporal sampling

- Preserved the exact recurring 0–10 craving item.
- Added `local_minute_of_day` and `timezone_offset_minutes` to phone/watch EMA transport and storage.
- Replaced the old app-active 45–75 minute schedule with one randomized in-process prompt in morning, afternoon, and evening strata.
- Restricted primary time-of-day ranking to independently timed EMA (`random`, `scheduled`, `scheduled_stratified`, `watch_scheduled`).
- Added minimum display safeguards of 30 eligible observations overall and 5 observations per two-hour window; these are engineering thresholds, not clinical cutoffs.

### Machine learning and backend

- Advanced ML/framework/API version metadata to 0.5.0.
- Retained an interpretable decision-tree companion even when another model is selected for risk probability.
- Added exact local decision-tree path probability decomposition and up to three positive contributors.
- Added model/interpretability provenance to streaming inference.
- Added optional fail-loud Firestore persistence of `risk_predictions` when explicitly enabled.
- Kept baseline assessment fields outside the default model feature matrix pending explicit ablation/validation.

### Data export and schema

- Added versioned `baseline_assessments/baseline_v1` storage and baseline completion metadata.
- Advanced phone research-export schema to 2 and added `baseline_assessments.csv`.
- Preserved local EMA timing in phone and Python exports.
- Added interpretation provenance/top contributors to optional risk-prediction records.
- All schema changes are additive; no participant data are deleted or destructively migrated.

### Validation status

- See `docs/RESEARCH_VALIDATION_0.5.0.md` for evidence-to-design rationale.
- Automated Python/backend/static validation is recorded in the release validation report.
- Flutter/Gradle builds, physical phone/watch testing, background prompt reliability, real EMA-labeled model validation, and clinical claims remain unverified until separately tested.

## 0.4.2 — Research hardening and participant-facing watch cleanup — 2026-08-10

### Participant interface

- Removed the engineering recorder-status line from the normal Galaxy Watch screen.
- Retained the short 0–10 watch micro-EMA and its save/error feedback.
- Standardized the Flutter phone app on the platform system font.
- Corrected settings text so it accurately describes the single-item 0–10 EMA, disabled raw PPG state, and non-diagnostic sleep/craving functions.

### Wear OS collection and transport

- Kept daytime and sleep recording in the same foreground health service so collection is not tied to the visible activity.
- Retained 90-second heart-rate freshness handling and screen-off diagnostics.
- Corrected the `RECORDING_MODE_CONTINUOUS` reference used by top-level batch payloads.
- Removed the unused Samsung raw-PPG permission from the active manifest while PPG is disabled.
- Marked the boot receiver non-exported so third-party apps cannot invoke it directly.
- Added ordered in-memory retry queues for standard-sensor and future PPG Data Layer writes.
- Added a bounded shutdown drain period so a normal stop attempts to transmit final partial batches.
- Preserved the limitation that forced process death can still lose a final in-memory partial batch; a disk-backed watch queue remains future work.

### Phone ingestion and export

- Changed pending Wear OS replay from full-backlog startup scans to one-item-at-a-time ingestion.
- Rotated pending replay among EMA, sensor, and PPG paths so sensor backlogs do not starve craving labels.
- Delayed ingestion startup until after the first Flutter frame to reduce startup memory pressure.
- Added participant-scoped research-data export to ZIP with lossless Firestore NDJSON and analysis-ready CSV files.
- Added export support for historical sessions, sensor samples, EMA, sleep, and future PPG data under the signed-in UID.
- Removed the UID from the temporary export filename, deletes stale temporary export ZIPs, and deletes the app's temporary copy after the platform share/save operation.
- Added Android Internet permission to the main manifest and disabled Android cloud backup/device-transfer backup for app-private data.
- Corrected session start handling so later batches do not move `started_at_ms` forward.
- Stopped duplicating email into newly created Firestore participant documents.
- Removed the unused mock sensor service and mock sensor snapshot model from active phone source.

### Sleep pipeline

- Added a short stabilization wait when ending a sleep session so late queued epochs can arrive before the provisional summary is finalized.
- Recomputes an unconfirmed provisional summary when late sleep batches arrive.
- Prevents late batches from overwriting a participant-confirmed summary.
- Preserves binary estimated sleep/wake terminology; no sleep-stage or diagnostic claim is made.

### Machine learning and evaluation

- Made filtering and interpolation causal for pre-EMA prediction features.
- Preserved heart-rate age and screen-interactive fields through preprocessing.
- Removed future-epoch (`next_*`) sleep-model input features.
- Restricted negative craving labels to windows paired with a nearby low-craving EMA rather than treating distant unlabeled periods as confirmed negatives.
- Prioritized participant-grouped evaluation, added session-grouped fallback, and replaced random row fallback with a purged chronological holdout.
- Added balanced accuracy, sensitivity, specificity, false-positive rate, AUROC, average precision, and Brier score reporting where defined.
- Required participant ID and timestamp for streaming inference rather than silently using demonstration defaults.
- Added research-safeguard tests for temporal leakage, label construction, and split logic.

### Backend safeguards

- Expanded and bounded API schemas to match current watch/phone fields.
- Disabled the universal engineering trigger rule by default.
- Made unauthenticated in-memory prototype routes fail closed unless explicitly enabled through an environment flag.
- Marked the backend as a research prototype, not a clinical decision system.

### Documentation and release governance

- Added an authoritative documentation index, research audit, evidence-validation matrix, PPG readiness guide, release checklist, active Wear OS project marker, and static audit script.
- Marked older planning documents as historical where their mock/Firebase/EMA descriptions are no longer current.
- Added a full update manifest under `updates/`.

### Validation completed in the build environment

- `11` machine-learning tests passed.
- `4` backend safeguard tests passed.
- Python source compilation passed.
- `61` source/configuration/static consistency checks passed, including Dart imports, transport-channel contracts, source hygiene, manifests, permission minimization, and research safeguards.

### Validation still required on the development computer and physical devices

- `flutter pub get`, `dart format`, `flutter analyze`, Flutter tests, and Android phone build.
- Wear OS Gradle build and installation on the Galaxy Watch.
- Screen-off heart-rate continuity, battery, Data Layer backlog, sleep-session, EMA, and export tests on hardware.
- Real participant/EMA model validation and EEG/PSG sleep validation.

## 0.4.1 — Install-ready consolidation — 2026-08-08

- Consolidated background BPM, sleep, 0–10 EMA, disabled-but-ready PPG, startup-memory, and in-app export work into one working snapshot.
- This version was a staging snapshot. Version 0.4.2 is the documented patch for the existing `RecoverySenseRunnableStarter` repository.

## Earlier prototype history

Earlier summaries remain in the repository for provenance, but may describe mock login, expanded EMA forms, activity-bound sensing, zero-phase filtering, or older schema/version numbers. Use `docs/CURRENT_DOCUMENTATION_INDEX.md` to identify authoritative current documents.
