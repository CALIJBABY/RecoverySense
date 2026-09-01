# RecoverySense Firebase Prototype Notes — Current v0.5.1 schema

Firebase/Firestore is the current prototype storage layer. The source code and owner-only rules do not by themselves establish HIPAA compliance. Real participant use requires an approved protocol, appropriate service agreement/BAA where legally applicable, secure configuration, controlled enrollment, access logging, retention/deletion policy, incident response, and institutional review.

## Firestore structure

```text
participants/{uid}
  baseline_assessments/baseline_v1
  sessions/{watchSessionId}
    sensor_batches/{batchId}
    ppg_batches/{batchId}
  ema_events/{eventId}
  sleep_sessions/{sleepSessionId}
    epochs/{epochId}
    sensor_batches/{batchId}
    ppg_batches/{batchId}
  sleep_logs/{id}
  model_predictions/{id}
  risk_predictions/{id}
  trigger_events/{id}
```

Standard-sensor batches can contain BPM, heart-rate timestamp/age/accuracy, accelerometer, gyroscope, steps, optional off-body state, screen state, capability/quality summaries, recording mode, and optional sleep-session ID. PPG collections remain absent while raw PPG is disabled.

Version 0.5+ EMA documents preserve the required 0–10 craving score plus timing/source/device/model metadata, including `local_minute_of_day` and `timezone_offset_minutes` for local routine analysis. New phone EMA writes use schema version 4; current watch EMA transport carries local-time metadata and the phone stores it under the same research event schema.

`baseline_assessments/baseline_v1` is additive, versioned, and write-once through the normal client repository after completion. It contains contextual candidate variables rather than free-text identifiers. Participant documents receive baseline completion/version metadata.

Optional `risk_predictions` may contain selected-model probability plus `model_name`, `model_version`, `interpretability_model`, `interpretability_method`, `interpretability_probability`, and up to three local decision-tree contributors. Prototype API persistence remains disabled unless explicitly enabled.

New participant documents do not duplicate email into the research namespace. Existing historical records are not silently altered.

## Current rule behavior

The v0.5.1 rules use explicit participant subcollection matches rather than a broad recursive owner wildcard:

- signed-in participants may read/create/update their own top-level participant profile; deletes are denied;
- Baseline Assessment v1 is readable/creatable by the owner but client update/delete is denied, reinforcing write-once behavior;
- participant EMA, session sensor batches, PPG batches, sleep sessions, and sleep epochs are owner-scoped with deletes denied;
- legacy `sleep_logs` is owner-readable only;
- `risk_predictions`, `model_predictions`, and `trigger_events` are owner-readable but normal client writes are denied so participant clients cannot forge model provenance; server/Admin SDK writes must occur through separately controlled backend credentials.

These are prototype integrity/ownership controls, not a complete production security program. Before deployment add/test, as applicable:

- controlled enrollment and consent status;
- App Check/device attestation;
- schema/field/size validation;
- researcher/admin access through a separate audited backend;
- least-privilege service accounts;
- audit logging, monitoring, retention, deletion, and incident response;
- export-handling policy.

## Deploy rules

```powershell
firebase.cmd use recoverysense
firebase.cmd deploy --only firestore:rules
```

Avoid names, addresses, and direct identifiers in sensor, EMA, baseline, and sleep documents. Use an approved research participant code distinct from provider-specific authentication IDs when the study design is finalized.
