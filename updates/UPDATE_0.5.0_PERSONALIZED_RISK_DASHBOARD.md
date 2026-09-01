# RecoverySense Update 0.5.0 — Personalized Risk Dashboard and Baseline Assessment

Date: 2026-08-10
Base: RecoverySense 0.4.2 research-hardening patch
Target repository root: `RecoverySenseRunnableStarter`

## Purpose

Version 0.5.0 adds a participant-facing personalized craving dashboard, a one-time baseline assessment, time-of-day pattern analysis, and traceable local decision-tree explanations while preserving the research safeguards introduced in 0.4.2.

This is a research-prototype update. It does not make the craving model clinically validated and does not enable raw PPG.

## Participant-facing changes

- Adds a large semicircular **Craving Now** gauge based only on the latest 0–10 EMA self-report.
- Adds a separate **Current Model Estimate** card so self-report is not confused with model inference.
- Adds a **Top decision-tree contributors** section with up to three current positive feature contributions.
- Adds a **Higher-Risk Times** section using personal repeated-EMA observations once minimum data safeguards are met.
- Shows self-reported baseline high-risk periods only as a clearly labeled provisional baseline while empirical data are insufficient.
- Adds a five-step one-time **Baseline Assessment** after registration/first authenticated use when baseline v1 has not been completed.
- Replaces the old dark green with a lighter, restrained research palette centered on `#3D844B`.
- Standardizes primary EMA/onboarding CTAs at 48 logical px/dp high, full content width, 2 px/dp corner radius, based on the requested Groupon Buy-button visual reference.
- Preserves the watch engineering-status cleanup from 0.4.2 and applies the new green/CTA proportions to the watch EMA action.

## Baseline Assessment v1

Collected once under:

```text
participants/{uid}/baseline_assessments/baseline_v1
```

The assessment records research context rather than identifiers/free text:

- target behavioral urge;
- current goal;
- days engaged in past 30 days;
- typical craving intensity;
- typical episode duration;
- self-reported high-risk time blocks and days;
- common cue/trigger categories;
- motive categories;
- routine regularity and typical sleep/wake time;
- activity level;
- confidence to resist;
- typical stress.

Once `baseline_v1` is completed, the repository prevents normal client overwrite. The participant document receives baseline completion/version metadata. Baseline responses are candidate/context variables and are not automatically converted into model weights.

## Repeated EMA and local-time metadata

The recurring EMA remains exactly:

```text
How strong is your urge or craving right now?
0 = none, 10 = extreme
```

EMA documents now preserve:

```text
local_minute_of_day
timezone_offset_minutes
```

Phone EMA schema version is advanced to 4. Watch EMA payload schema is advanced to 2 so local timing can survive watch-to-phone transport.

## Time-stratified prompting

The old app-active 45–75 minute schedule was replaced with one randomized in-process prompt per broad local-time stratum:

```text
09:00–11:59
13:00–16:59
18:00–21:59
```

Source is `scheduled_stratified`.

Important limitation: these are in-process timers, not guaranteed background/terminated-app notifications. At most one prompt per stratum is enforced while the process remains alive; delivered-stratum state resets after process restart. The schedule is for sampling coverage and is not a clinical risk schedule.

## Time-of-day risk summary

Primary descriptive rankings use only independently timed EMA sources:

```text
random
scheduled
scheduled_stratified
watch_scheduled
```

Manual and model-triggered EMA are excluded from the primary estimate to reduce ascertainment bias.

The current display guardrails are:

```text
minimum eligible EMA observations: 30
minimum observations per two-hour window: 5
```

These are engineering safeguards, not validated cutoffs.

## Model explainability

The training pipeline now keeps an interpretable decision-tree companion even if another candidate model is selected for risk probability.

For the companion tree, local feature contributions are computed from changes in positive-class node probability along the current decision path. Repeated uses of a feature are accumulated. The explanation is additive for that companion tree:

```text
root probability + sum(feature path contributions) = leaf probability
```

Inference returns the three largest positive contributors plus:

```text
model_name
model_version
interpretability_model
interpretability_method
interpretability_probability
top_contributors
```

If the selected risk model differs from the companion tree, the dashboard explicitly states that the tree is a parallel explanation view rather than an exact decomposition of the selected model probability.

## Optional prediction persistence

The prototype API can optionally persist current prediction provenance to:

```text
participants/{participantId}/risk_predictions/{sessionId_timestamp}
```

This is disabled by default and requires:

```text
RECOVERYSENSE_PERSIST_RISK_PREDICTIONS=true
```

The API itself remains prototype/fail-closed unless explicitly enabled under the existing safeguard.

## Research export changes

Research export schema advances to version 2 and adds:

- baseline-assessment raw documents;
- `csv/baseline_assessments.csv`;
- EMA local minute/time-zone offset fields;
- risk-prediction explanation/provenance data when present.

The Python Firestore exporter likewise emits baseline-assessment CSV and local EMA timing metadata.

## Machine-learning changes

- Framework/package version advanced to 0.5.0.
- Adds exact local decision-tree path probability decomposition.
- Persists companion-tree global impurity importance for audit/overview, but does not use global importance as a per-prediction explanation.
- Returns top three positive local contributors during streaming inference.
- Keeps participant/session/purged-time validation safeguards from 0.4.2.
- Baseline-assessment fields are exported but not automatically injected into the default modeling feature frame; later inclusion requires explicit ablation/evaluation.

## Version/build changes

```text
Phone:       0.4.2+6 → 0.5.0+7
Wear OS:     0.4.2 (code 3) → 0.5.0 (code 4)
Backend API: → 0.5.0
ML package:  → 0.5.0
ML bundle:   → 0.5.0
```

## Dependencies

No new production Python or Flutter package is required solely for the new dashboard/baseline/explainability implementation. The implementation deliberately avoids adding SHAP; decision-tree path contributions are calculated directly from the fitted scikit-learn tree.

## Files deleted

None in version 0.5.0.

## Database/schema changes

Additive only; no destructive migration is performed.

New/additional concepts:

```text
participants/{uid}/baseline_assessments/baseline_v1
ema_events.local_minute_of_day
ema_events.timezone_offset_minutes
risk_predictions.interpretability_model
risk_predictions.interpretability_method
risk_predictions.interpretability_probability
risk_predictions.top_contributors
```

Old documents without the new fields remain exportable; missing values remain missing.

## Install scope

Both phone and watch should be rebuilt because participant-facing UI/version metadata changed on both. ML/backend code should be updated for research analysis and optional prediction persistence.

## Validation performed in the packaging environment

See `docs/RESEARCH_VALIDATION_0.5.0.md` for evidence rationale and the release validation report for exact automated results.

## Validation not performed here

- Flutter dependency resolution/analyzer/tests/build.
- Phone APK installation on the Galaxy S21.
- Wear OS Gradle dependency resolution/build/install on the Galaxy Watch.
- Physical CTA sizing/usability screenshots against the current Groupon app.
- Background/terminated-app scheduled EMA delivery.
- Real participant time-of-day uncertainty analysis.
- Real EMA-labeled craving-model performance/calibration.
- Real model-prediction persistence against production backend/storage.

## Known limitations

- Risk contributors cannot be shown until a current prediction with explanation provenance exists.
- Companion-tree factors do not exactly explain a different selected model's probability; the UI now states this explicitly.
- Time-of-day estimates can be unstable with sparse or behaviorally biased observations.
- Baseline answers are self-report and may contain recall/reporting bias.
- The randomized EMA scheduler currently depends on the Flutter process being alive; delivered-stratum state is in memory and resets after process restart.
- The selected green/CTA proportions are research/HCI reference choices, not validated treatment components.
- The Groupon-like dimensions are a visual-reference implementation; no official universal Groupon dp specification was found in the official pages reviewed.

## Rollback

Rollback should restore the 0.4.2 versions of every file listed in the patch manifest. Additive Firestore documents/fields do not need to be deleted for code rollback; older clients ignore them. Do not delete participant baseline or EMA data merely to roll back application code.
