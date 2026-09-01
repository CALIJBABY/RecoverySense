# RecoverySense Heart-Rate Quality Layer — Version 0.5.2

**Status:** active Android/Wear OS research-processing specification  
**Release:** 0.5.2  
**Scope:** Galaxy Watch `Sensor.TYPE_HEART_RATE` BPM quality control before research analysis/modeling

## Purpose

RecoverySense records the watch-provided heart-rate value, but a numeric BPM is not automatically treated as an analysis-ready physiological observation. Version 0.5.2 adds a provenance-preserving quality layer so off-wrist, no-contact, unreliable, stale, and broad implausible readings are excluded from the analysis-ready `heart_rate` field while the original positive watch-provided value is retained as `raw_heart_rate` when available.

This is a data-quality rule, not a diagnostic or clinical heart-rate classifier.

## Primary quality gates

The watch evaluates heart rate in this order:

1. Android sensor status `SENSOR_STATUS_NO_CONTACT` → reject.
2. Android sensor status `SENSOR_STATUS_UNRELIABLE` → reject.
3. No positive finite BPM → reject as no reading.
4. Broad engineering plausibility boundary outside **30–220 BPM** → reject.
5. `SENSOR_STATUS_ACCURACY_LOW` → retain as analysis-usable but label `low_accuracy`.
6. Explicit low-latency off-body state → reject at sample time.
7. Heart-rate age greater than **90,000 ms** → reject as stale.
8. A robust rolling median/MAD detector can flag a temporal outlier, but the value remains usable by default.

The 30–220 BPM range is deliberately broad. It is an engineering sanity boundary, **not a normal-range claim**, clinical threshold, or craving threshold. It must be reviewed against pilot data and the study population before field use.

## Off-body semantics correction

Android defines `TYPE_LOW_LATENCY_OFFBODY_DETECT` as:

- `1.0` = device is **on-body**
- `0.0` = device is **off-body**

RecoverySense watch schema versions `<=4` accidentally stored this signal under an `off_body` field without inversion, so historical `1` meant worn and historical `0` meant removed. Watch schema version **5** corrects the semantics so stored `off_body=true/1` means the watch is off the body.

No raw Firestore document is destructively rewritten by this release. Instead:

- the v0.5.2 phone parser normalizes pending legacy watch payloads before storage;
- storage schema version 5 marks records produced by the corrected phone pipeline;
- current phone/Python CSV exporters normalize historical storage schema <=4 records during export;
- the lossless raw NDJSON export preserves historical Firestore values unchanged for provenance.

**Previously generated sensor CSV files should be regenerated after upgrading to v0.5.2 before analysis.**

Historical phone-derived sleep epochs/summaries created with `rules-v1` may also reflect the old off-body interpretation. Version 0.5.2 writes `rules-v2-hr-quality`, `watch_schema_version`, and `heart_rate_quality_semantics_version: 2` on new derived sleep epochs. Do not use pre-v0.5.2 phone-derived sleep summaries as validated outcomes without recomputing from normalized raw sensor batches.

## Stored sample fields

Current sensor samples preserve:

```text
heart_rate                      analysis-ready BPM or null
raw_heart_rate                  positive watch-provided BPM when available
heart_rate_valid                hard-gate result
heart_rate_quality_code         integer quality code
heart_rate_quality_reason       human-readable stable code
heart_rate_outlier_flag         soft temporal-outlier flag
heart_rate_timestamp_ms         watch HR event timestamp
heart_rate_age_ms               age at the synchronized motion sample
heart_rate_accuracy             Android sensor status/accuracy
off_body                        normalized true=off-body state
```

Quality code contract:

```text
0 valid
1 no_reading
2 stale
3 off_body
4 no_contact
5 unreliable
6 implausible
7 low_accuracy
```

## Temporal outlier rule

The watch maintains a 60-second rolling history of sensor-valid HR events. After at least five prior events, a new value is flagged when its absolute deviation from the recent median exceeds:

```text
max(30 BPM, 5 × max(MAD, 1 BPM))
```

This is intentionally a **soft flag**. Flagged readings continue updating the rolling reference so sustained legitimate transitions such as exercise can become the new local pattern. The default ML configuration does not discard them:

```yaml
exclude_temporal_outliers: false
```

Sensitivity analyses can explicitly set the option to `true`; results should report that choice.

## Analysis safeguards

The Python preprocessing pipeline independently re-applies hard exclusions for explicit invalid status, normalized off-body state, and HR age >90 seconds before interpolation. It re-applies the same mask after interpolation and trailing median smoothing so filtered/interpolated values cannot resurrect a hard-invalid BPM.

Recommended reporting includes:

- raw-heart-rate observed fraction
- analysis-valid heart-rate fraction
- no-reading fraction
- stale fraction
- off-body fraction
- no-contact fraction
- unreliable fraction
- implausible fraction
- low-accuracy fraction
- temporal-outlier fraction
- mean heart-rate age

## Physical validation required

Before participant field deployment, validate on the target Galaxy Watch hardware:

1. Wear the watch and record at rest.
2. Remove the watch while recording and verify `off_body=true`, `heart_rate_valid=false`, and no analysis-ready BPM.
3. Re-wear the watch and verify recovery without restarting the study session.
4. Test screen-off collection for at least 30 minutes.
5. Verify no-contact/unreliable statuses and HR age when available.
6. Exercise briefly to confirm rapid legitimate changes are not hard-rejected by the temporal outlier rule.
7. Compare raw versus filtered counts and inspect all rejection reasons.
8. Export the same session and verify watch → phone → Firestore → CSV semantics agree.

## Source basis

Implementation semantics are based on Android `SensorEvent` documentation for `TYPE_LOW_LATENCY_OFFBODY_DETECT`, Android `SensorManager` status definitions, and Samsung's Galaxy Watch off-body/heart-rate sample guidance. These platform definitions establish contact/status semantics; they do **not** validate RecoverySense's 30–220 engineering boundary or temporal-outlier parameters.
