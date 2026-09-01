# RecoverySense Research and UX Audit — Version 0.5.1

**Audit date:** 2026-08-11  
**Base:** RecoverySense 0.5.0 personalized risk dashboard applied to the 0.4.2 research-hardening baseline.

## Purpose

Version 0.5.1 is a quality/polish pass rather than a claim of clinical validation. The audit inventories the repository, checks active source contracts, compares participant interaction hierarchy with current craving/addiction/gambling-recovery apps, and strengthens places where defaults, stale paths, technical UI, or time handling could compromise research data.

## Material findings corrected

### Participant-response integrity

- Phone EMA cannot save the visually neutral slider position until the participant deliberately selects a rating.
- Watch EMA follows the same rule.
- One-time Baseline Assessment numeric/default fields require deliberate responses.
- Morning sleep confirmation now requires deliberate sleep-quality, rested, awakening-count, and watch-removal responses instead of silently accepting prefilled values.
- Morning confirmation rejects a wake time that is not after reported sleep onset.

### Sleep UI / data consistency

- Corrected a duplicated `initialDate` named argument in the sleep date picker that would be a Dart compile error.
- History reads the current `sleep_sessions` path rather than the legacy `sleep_logs` path.
- History displays sleep quality on the implemented 1–5 scale.
- Participant sleep screens no longer lead with 30-second epoch counts/provisional model probability diagnostics.
- Raw start-failure exception strings are no longer stored as research data; a stable error code is stored instead.

### Time-of-day research integrity

The descriptive phone dashboard already uses EMA `local_minute_of_day`. The ML audit identified a separate inconsistency: cyclic ML clock features had been derived from UTC timestamps. Version 0.5.1 changes craving-model time features to use the participant timezone offset captured with the matched EMA during training and current timezone metadata during inference. If local-time metadata are unavailable, time features remain missing with an availability flag rather than silently treating UTC as local routine time.

### Model display integrity

- The dashboard continues to fail closed unless a prediction is complete, non-demo, explicitly participant-displayable, versioned, and recent.
- The model estimate now includes a restrained progress visualization while remaining clearly separated from the participant's 0–10 self-report.
- Local top-three factors remain positive decision-tree path contributions, not global impurity importance presented as an individual explanation.
- Server-authored prediction collections are read-only to normal participant clients in Firestore rules.

### Authentication/profile consistency

Successful sign-in/account creation now ensures the participant research profile exists without duplicating email into the research namespace. If this required profile step fails, the client signs out instead of leaving the UI in an ambiguous partially initialized authenticated state.

### Repository hygiene

- Removed obsolete duplicate Wear OS prototype files.
- Removed TODO-only Apple Watch placeholders that could be mistaken for implementation.
- Removed generated IDE module files and generated Python/cache artifacts from the release tree.
- Added repository-wide ignore rules for build products, caches, secrets, local properties, and ML generated outputs.
- Current Wear OS path remains `apps/wear_android/wear_android`.

## Competitive UX benchmark

See `docs/COMPETITIVE_UX_BENCHMARK_0.5.1.md`. The benchmark reviewed current public Reframe, I Am Sober, SMART Recovery, Evive, Betttr, and GamQuit materials. Common patterns—one obvious current-state/progress element, a highly visible urge/check-in action, simple supportive copy, and secondary technical detail—were used as hierarchy references without copying a commercial design.

## Automated validation available in the audit environment

The release process runs:

- Python source compilation
- ML tests from repository root
- ML tests from the `ml/` working directory
- backend safeguard tests
- RecoverySense static source/configuration audit
- XML/JSON/YAML parsing where applicable
- local Dart import resolution
- active-source merge-marker/empty-source checks
- watch/native-phone/Dart transport contract checks
- patch SHA-256 and clean-base application simulation
- repository-wide inventory/static quality scan

## Validation not available in this environment

The following remain required and must not be represented as passed until performed on the actual development machine/devices:

- `flutter pub get`
- `dart format lib`
- `flutter analyze`
- `flutter test`
- `flutter build apk --release`
- Wear OS Gradle dependency resolution and APK compilation
- Galaxy S21 + Galaxy Watch4 install/permission/transport testing
- screen-off BPM continuity and battery testing
- real Firestore export round-trip
- OS-backed scheduled EMA delivery after process termination (not implemented yet)
- raw Samsung PPG acquisition (disabled)
- real EMA-labeled craving model validation
- sleep validation against synchronized reference labels/PSG where claims require it
- iPhone/Apple Watch Xcode build and parity audit

## Pre-field blocker

The current stratified study-check-in scheduler is intentionally app-process based. It supports app-active prototype collection but **does not guarantee delivery after the phone process is terminated**. A field study requiring scheduled/random prompts must replace or supplement this with a validated OS-backed notification/scheduling mechanism and test delivery/reboot/timezone behavior before enrollment.
