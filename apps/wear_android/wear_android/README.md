# RecoverySense Wear OS Recorder — Active Project

Open this exact folder in Android Studio:

```text
apps/wear_android/wear_android
```

Package/application ID:

```text
com.recoverysense.wear
```

The obsolete sibling watch prototype was removed in v0.5.1 so there is only one buildable Wear OS project path.

## Participant-facing UI

The normal watch UI has two rounded participant pages:

- **Sensors:** heart-rate BPM, acceleration magnitude, gyroscope magnitude, and steps.
- **Check-in:** one deliberate 0–10 craving/urge micro-EMA with save feedback.

Bottom controls use the same lighter `#4F9B17` green and 14 dp rounded shape as the phone refresh.

The former engineering status line showing recorder mode, HR age, screen state, and PPG state has been removed from the participant UI. Those diagnostics remain in internal service state, batch metadata, Firestore, and exports.

## Background collection

A foreground health service owns continuous daytime and sleep collection so sensing can continue when the display turns off. Current streams:

- Raw watch BPM plus analysis-ready heart-rate BPM, freshness/accuracy, validity/reason, and temporal-outlier provenance
- Accelerometer at the application target rate
- Gyroscope
- Steps and optional off-body state
- Screen state for verification
- Raw green/infrared/red PPG only after Samsung enablement

## Heart-rate quality

Version 0.5.2 corrects low-latency off-body semantics and gates analysis-ready BPM using Android no-contact/unreliable status, explicit off-body state, 90-second freshness, and a broad 30–220 BPM engineering plausibility boundary. Low-accuracy status remains usable but labeled. A rolling median/MAD temporal outlier detector is a soft flag by default. See `docs/HEART_RATE_QUALITY_LAYER.md` for the exact contract and physical validation plan.

## Raw PPG

PPG is disabled in `PpgFeatureFlags.kt`. The app must compile and operate without the proprietary Samsung AAR and must not generate fake PPG samples. Follow `docs/PPG_READINESS.md` before enabling it.

## Build

```powershell
.\gradlew.bat clean assembleDebug
```

Physical-device validation is required for screen-off BPM continuity, permissions, battery, transport retry, sleep sessions, and watch EMA.
