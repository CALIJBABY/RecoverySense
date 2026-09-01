# RecoverySense Research Release Checklist

**Current review:** RecoverySense v0.5.1 (2026-08-11)

A checked software build is not the same as a validated research instrument. Complete the applicable gates before collecting participant data or enabling model-triggered prompts.

## A. Source and build identity

- [ ] Existing master repository is `RecoverySenseRunnableStarter`.
- [ ] Phone version and watch version are recorded.
- [ ] `apps/wear_android/wear_android` is the only Wear OS project opened/built.
- [ ] Package/application ID is `com.recoverysense.wear` on phone and watch.
- [ ] Release commit/tag and signing certificate hashes are recorded.
- [ ] `CHANGELOG.md` and the update manifest match the installed build.
- [ ] Raw-PPG-only permission is absent while PPG is disabled; add it only during the documented enablement process.
- [ ] The boot receiver remains non-exported; only the Wear Data Layer listener service is externally reachable as required.

## B. Automated checks

- [ ] `flutter pub get` completes and updates `pubspec.lock`.
- [ ] `dart format lib` produces no unexpected source changes.
- [ ] `flutter analyze` reports no errors.
- [ ] Flutter unit/widget tests pass.
- [ ] Phone release APK builds.
- [ ] Active Wear OS Gradle build passes.
- [ ] `python -m pytest -q ml/tests` passes.
- [ ] `python -m pytest -q backend/api/tests` passes.
- [ ] `python scripts/research_static_audit.py` passes.

## C. Physical watch and phone validation

- [ ] Phone and watch install from the documented source paths.
- [ ] Required permissions are granted and recorded by OS version.
- [ ] Foreground recording notification remains visible.
- [ ] At least a 30-minute screen-off test verifies motion continuity.
- [ ] BPM timestamps continue or missing BPM is correctly marked rather than repeated stale.
- [ ] `heart_rate_age_ms`, `screen_interactive`, accuracy, and off-body fields are present where available.
- [ ] Data Layer disconnect/reconnect test preserves and later uploads batches.
- [ ] EMA submitted on the watch appears once in Firestore with correct timestamps and 0–10 value.
- [ ] Start/stop sleep test creates the expected session, epochs, and summary.
- [ ] Full-night battery, thermal, comfort, missingness, and gap tests are documented.
- [ ] Export ZIP contains historical and new data, opens successfully, and record counts match Firestore samples.

## D. Data integrity and security

- [ ] Study-approved participant code strategy is defined; direct identifiers are separated.
- [ ] Authentication/enrollment is restricted to approved participants before real study use.
- [ ] Database service/account, BAA where legally required, encryption, access control, logging, retention, deletion, and incident-response plans are approved.
- [ ] Firestore/App Check or replacement-backend production controls are configured and tested.
- [ ] Exported ZIP handling, transfer, retention, and deletion procedures are documented.
- [ ] Raw data are immutable/preserved separately from filtered features.
- [ ] Time-zone, clock drift, device model, firmware, app version, wrist, wear/removal, and battery metadata are collected as required by protocol.

## E. EMA protocol

- [ ] Exact 0–10 wording and anchors are approved by the study team/IRB.
- [ ] Manual, random/scheduled, and future model-triggered prompt frequencies are prespecified.
- [ ] Prompt expiry, snooze, missed-response, and response-delay rules are prespecified.
- [ ] Positive and low/negative EMA examples will both be collected.
- [ ] Prompt burden outcomes are reported: delivered, opened, completed, expired, delay, and prompts/day.

## F. Craving-model release gate

- [ ] Training uses real EMA-labeled observations; synthetic data are demonstration-only.
- [ ] Target definition and label horizons are prespecified.
- [ ] Participant grouping is used when multiple participants exist.
- [ ] Session grouping and purged temporal holdout are used only as documented fallbacks.
- [ ] No feature uses information after the prediction time.
- [ ] Model selection and hyperparameter tuning are separated from final evaluation.
- [ ] Metrics include class counts, balanced accuracy, sensitivity, specificity, precision, F1, AUROC/average precision where defined, calibration/Brier score, false prompts/day, and missingness.
- [ ] Ablations quantify the contribution of heart rate, motion, gyroscope, sleep, timing/history, and future PPG.
- [ ] Model-triggered EMA is disabled until the protocol's performance and safety thresholds are met.

## G. Sleep-model release gate

- [ ] Output is called estimated sleep/wake unless validated otherwise.
- [ ] Thirty-second timestamps are synchronized to reference labels.
- [ ] Participant-level train/test separation is used.
- [ ] Sleep sensitivity, wake specificity, balanced accuracy, F1, kappa, calibration/confidence, and timing errors are reported.
- [ ] Stage labels or diagnostic claims are not used without EEG/PSG validation and applicable regulatory/clinical review.

## H. Reporting

- [ ] Report follows relevant TRIPOD+AI items for prediction-model development/evaluation.
- [ ] Early live decision-support evaluation follows relevant DECIDE-AI items.
- [ ] Mobile intervention/implementation reporting follows mERA.
- [ ] Device/firmware/app/model versions, missing data, exclusions, preprocessing, split logic, and all deviations are reported.
