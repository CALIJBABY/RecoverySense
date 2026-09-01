# RecoverySense Research Software Audit — Version 0.4.2

Audit date: 2026-08-10  
Audit scope: active Flutter Android phone app, active Galaxy Watch Wear OS app, Firebase repository layer/export, FastAPI prototype, craving/sleep Python ML pipelines, and current documentation.

## Executive assessment

Version 0.4.2 is a substantially hardened **research prototype**. It has a coherent passive-sensing → phone ingestion → participant-scoped storage → EMA labeling → offline ML workflow. It should not be represented as a validated craving detector, a clinical intervention, a sleep-staging device, or a HIPAA-compliant system solely because the software runs.

The audit removed participant-facing engineering clutter, corrected documentation/model leakage inconsistencies, added fail-closed safeguards, improved transport/replay reliability, and added reproducible release gates. Automated Python checks pass. Android/Flutter compilation and physical-device validation remain required on the development computer.

## Audit results by severity

### Resolved critical/high issues

| Finding | Risk | Resolution in 0.4.2 |
|---|---|---|
| Engineering recorder status exposed on participant watch UI | Participant confusion, reactivity, unprofessional interface | Removed from normal watch screen; internal state/quality metadata remain available to code and export. |
| Daytime sensing previously depended on visible activity | Screen-off data loss | Active design uses a foreground health service for continuous and sleep modes. Hardware validation is still required. |
| Full Wear Data Layer backlog replayed during phone startup | Memory exhaustion and app startup failure | Replaced with bounded, one-item-at-a-time ingestion after first Flutter frame. |
| Sensor backlog could delay EMA labels | Biased/incomplete supervised labels | Pending replay rotates among EMA, sensor, and PPG paths. |
| Batch transport failure was not retained for retry in service memory | Data loss during transient Data Layer failures | Added ordered retry queues and normal-stop drain window. |
| Session start time overwritten by later batches | Incorrect duration/time alignment | `started_at_ms` is written only for sequence zero. |
| Offline filtering used future samples (`filtfilt`, centered rolling/interpolation) | Temporal leakage and inflated model performance | Replaced with causal filtering, trailing smoothing, and forward-only short-gap filling for prediction inputs. |
| Sleep features included `next_*` epochs | Future leakage | Removed future-epoch model inputs; completed-night postprocessing is documented separately. |
| Distant unlabeled windows treated as negative craving examples | Label noise and biased performance | A negative example now requires a nearby low-craving EMA. |
| Random row fallback mixed correlated windows | Inflated evaluation | Uses participant grouping first, session grouping second, then purged chronological holdout; otherwise fails and requests more data. |
| Universal engineering craving trigger could be mistaken for a validated model | Unsafe/unsupported prompts | Disabled by default; requires explicit engineering-only environment flag. |
| Unauthenticated in-memory API routes appeared generally available | Misuse/security confusion | Fail closed unless explicitly enabled for local engineering tests. |
| Phone release manifest omitted Internet permission | Release app could fail network/Firebase operations | Added to main manifest. |
| Android app-private data eligible for backup/transfer | Sensitive local-data exposure | Cloud backup and device-transfer backup disabled. |
| Firestore participant record duplicated email for new accounts | Direct identifier mixed with research namespace | New participant documents no longer write email. Existing historical fields are not silently deleted. |
| PPG-derived intervals risk being labeled HRV | Scientific terminology error | Documentation and feature names use PRV for PPG-derived variability; BPM variability remains explicitly non-clinical. |
| Disabled PPG permission remained declared and boot receiver was externally exported | Unnecessary sensitive permission surface and component exposure | Removed the PPG-only permission until enablement and marked the system-boot receiver non-exported. |

### Medium issues improved but requiring field validation

| Finding | Current mitigation | Remaining work |
|---|---|---|
| Final partial watch batch can be lost during forced process death | Normal stop flushes and waits up to 15 seconds | Add a disk-backed watch queue if protocol requires stronger crash persistence. |
| Sleep summary may finalize before late queued epochs | Stop waits for epoch stabilization; late unconfirmed batches refresh summary | Validate on real overnight disconnect/reconnect scenarios. |
| Export leaves sensitive temporary files | Old temporary ZIPs are removed; current temporary copy is deleted after share/save returns | Validate behavior on target Android versions; define handling for the user's saved copy. |
| Live biometric display may alter participant behavior | Engineering status removed; sensors remain visible | Study team should decide whether live HR/motion should be hidden or protocol-controlled. |
| Random prompts run only while Flutter process is active | Clearly documented | Implement OS background scheduling if the final protocol requires it. |
| Firestore rules are owner-only but broad | Prevents cross-UID access | Add field/schema validation, App Check, controlled enrollment, audit logs, and approved backend configuration before production research. |
| Release APK uses development/debug signing configuration | Suitable for local install only | Configure protected release signing and record certificate hashes for study deployment. |

### Open scientific/clinical blockers

1. No real EMA-labeled multi-participant dataset is present; craving-prediction validity is unknown.
2. Synthetic data verify software execution only and must never be reported as clinical/research performance.
3. There is no external/prospective validation, intervention-effect study, or accepted false-prompt burden threshold.
4. Current sleep output is estimated binary sleep/wake and has not been validated against EEG/PSG.
5. Raw PPG is disabled until Samsung SDK access, device capability, permission, and protocol/security requirements are satisfied.
6. The storage environment, BAA when applicable, access controls, retention, and institutional/IRB approvals must be established separately; software changes alone do not confer HIPAA compliance.
7. The exact EMA schedule, wording, behavioral target, participant population, and safety/escalation plan must match the approved protocol.

## Data-contract consistency review

### Watch → phone live sample

Current contract includes schema version, BPM, BPM age, accelerometer axes/magnitude, gyroscope axes/magnitude, step count, optional off-body state, screen state, PPG state, timestamp, recording mode, and sleep-session ID.

### Watch → phone batch

All aligned arrays use the accelerometer sampling clock and are length-validated. Unavailable values use explicit sentinels at transport and are converted to `null`/missing values before Firestore/analysis. The canonical batch remains under `participants/{uid}/sessions/{watchSessionId}/sensor_batches/{batchId}`; sleep-session mirrors are preserved for reproducibility.

### EMA

The required repeated label is one integer `craving_score` from 0 through 10. The record includes participant/session identifiers, prompt/open/submit timestamps, response delay, prompt source, response device, and future model-trigger metadata. Additional context forms are not silently treated as pre-prompt model inputs.

### Sleep

Raw overnight batches remain separate from provisional epochs and nightly summaries. The craving model receives eligible prior-night summary features only; future sleep records are not used.

### PPG

No PPG documents are generated while disabled. The future contract retains raw ADC values, per-channel status flags, timestamps, source, session/mode, and sampling rate.

## Automated verification completed

- ML tests: `11 passed`.
- Backend tests: `4 passed`.
- Python bytecode/source compilation: passed.
- Static audit: `61` checks passed, covering versions, package IDs, manifests, backup policy, permission minimization, watch UI cleanup, PPG flag, EMA range, causal ML guards, backend fail-closed guard, local Dart imports, source hygiene, watch/phone transport contracts, export safeguards, and required documentation.

## Checks unavailable in the audit container

- Flutter SDK and Dart analyzer were not installed.
- Android SDK/Gradle dependencies were not available for a complete phone/watch build.
- No physical phone/watch/Firebase account was connected.
- No raw PPG SDK AAR or EEG/PSG device/data were available.

Therefore Android/Flutter source is **not claimed compiled** by this audit. Run every item in `docs/RESEARCH_RELEASE_CHECKLIST.md` on the development system.

## Research-literature alignment

The evidence review supports the following choices without validating RecoverySense performance:

- Short smartwatch micro-EMA is defensible for frequent, low-burden momentary labels.
- Passive heart/activity/sleep plus brief craving EMA is aligned with emerging behavioral-addiction protocols.
- Thirty-second sleep epochs and separate cardiac/movement sleep models are aligned with wearable sleep research.
- PPG-derived PRV must not be assumed equivalent to ECG HRV.
- Participant/time separation, calibration, class-specific error reporting, implementation context, and human factors are consistent with TRIPOD+AI, DECIDE-AI, and mERA reporting expectations.

See `docs/RESEARCH_VALIDATION_MATRIX.md` for citations and limitations.

## Final disposition

**Approved for continued engineering, pilot data-quality testing, and protocol development after the documented local builds succeed.**

**Not approved by this software audit for clinical decision-making, automatic intervention deployment, diagnostic sleep claims, HIPAA compliance claims, or participant research deployment without the remaining technical, institutional, IRB, security, and empirical validation gates.**
