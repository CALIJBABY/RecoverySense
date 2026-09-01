# RecoverySense Raw PPG Readiness

**Current review:** RecoverySense v0.5.1 (2026-08-11)

## Current state

Raw photoplethysmography collection is intentionally disabled:

```text
apps/wear_android/wear_android/app/src/main/java/com/recoverysense/wear/ppg/PpgFeatureFlags.kt
ENABLED = false
```

With the flag disabled, the app continues to collect ordinary processed heart-rate BPM, accelerometer, gyroscope, steps, screen state, optional off-body state, sleep sessions, and EMA responses. It does not create fake or empty PPG batches.

## Components already present

- Samsung Health Sensor SDK reflection adapter
- Green, infrared, and red raw PPG data contract
- Per-channel status flags and original timestamps
- Wear Data Layer PPG batch path
- Phone decoding and Firestore storage
- Lossless PPG export to CSV/NDJSON
- Signal-quality checks, filtering, pulse detection, and pulse-rate-variability feature extraction
- Sleep/craving feature hooks

## Enablement gate

Do not enable raw PPG until all of the following are true:

1. The official Samsung Health Sensor SDK AAR has been obtained from Samsung.
2. The AAR is placed at `apps/wear_android/wear_android/app/libs/samsung-health-sensor-api.aar`.
3. Add `com.samsung.android.hardware.sensormanager.permission.READ_ADDITIONAL_HEALTH_DATA` to the active watch manifest. It is deliberately absent while PPG is disabled so the prototype does not declare an unused sensitive permission.
4. Health Platform developer mode is enabled on the development watch, or the package/signing certificate has been registered for the intended deployment.
5. Runtime permissions are granted.
6. `PPG_CONTINUOUS` capability is confirmed on the exact watch/firmware combination.
7. A short screen-on and screen-off acquisition test verifies timestamps, sample rate, channel status, gaps, clipping, and battery cost.
8. The research protocol/IRB and data-security plan cover raw optical waveform collection.

Only then change `PpgFeatureFlags.ENABLED` to `true`, add the manifest permission, rebuild, reinstall, and validate.

## Terminology

Features derived from PPG pulse intervals are labeled **pulse rate variability (PRV)**. They are not automatically labeled ECG-derived heart-rate variability (HRV). A 2025 clinical-population study specifically cautions that PPG-derived PRV and ECG-derived HRV are not interchangeable:

- Kantrowitz BA et al. *Pulse rate variability is not the same as heart rate variability: findings from a large, diverse clinical population study.* Frontiers in Physiology. 2025. PubMed: https://pubmed.ncbi.nlm.nih.gov/40809286/
