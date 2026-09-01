# RecoverySense iOS and Apple Watch implementation - 0.5.3.4 parity

## Architecture

RecoverySense keeps one current Flutter phone application instead of creating a
separate Swift phone UI:

```text
iPhone
  Current Flutter/Dart application
    Home, Live, Check-in, Sleep, History, Settings, Firebase, export, models

Native iPhone layer
  Swift
    Flutter channels + WatchConnectivity + durable bounded replay

Apple Watch
  Swift + SwiftUI
    HealthKit + Core Motion + WatchConnectivity
```

This keeps Android and iPhone participant screens, model provenance, sleep
workflow, EMA storage, and research export behavior in one shared Dart codebase.

## Current shared Flutter features

The iPhone uses the same current phone code as Android, including:

- five-icon participant navigation;
- separate Live Sensors and Sleep screens;
- the ten-block estimated sleep-efficiency visualization;
- deliberate 0-10 craving check-ins;
- the approved sensor-window model probability;
- the selected model name;
- up to three positive local companion-tree contributors;
- history, settings, and participant-scoped research export.

A selected Random Forest, SVM, or boosting model can provide the probability.
The three contributor boxes remain a parallel decision-tree explanation unless
the selected model itself is the decision tree. They are predictive
associations, not causal claims.

## Schema and sensor parity

| Area | Android / Galaxy Watch | iPhone / Apple Watch |
|---|---|---|
| Phone UI | Flutter/Dart | Same Flutter/Dart |
| Native bridge | Kotlin + Wear Data Layer | Swift + WatchConnectivity |
| Watch UI | Jetpack Compose | SwiftUI |
| Batch schema | 5 | 5 |
| Sampling target | 10 Hz | 10 Hz requested |
| Batch target | 30 seconds | 30 seconds |
| Heart rate | Android sensor APIs | HealthKit live workout |
| HR quality | contact/accuracy/stale/plausibility | stale/plausibility plus raw provenance; no per-sample Apple contact code |
| Accelerometer | m/s2 | Core Motion g converted to m/s2 |
| Gyroscope | rad/s | rad/s |
| Steps | raw platform counter + derived daily UI | local-day `CMPedometer` count |
| Off-body | optional sensor | unavailable through this public path |
| Raw PPG | Samsung path disabled | no matching public raw optical API; disabled |
| Reliable transfer | Wear Data Items until ACK | queued user info + watch/iPhone stores until ACK |

Fields unavailable on Apple hardware/APIs are marked unavailable. The port does
not invent Android-style accuracy or off-body values.

## Daily steps

`MotionSensorService.swift` starts `CMPedometer` at the participant's local
midnight. It first queries the interval from midnight to now so an app restart
restores today's total, then subscribes to updates from the same start time. A
local-day check restarts the pedometer after midnight. The watch UI labels this
value **Steps Today**.

## Heart-rate quality

The Apple Watch path preserves both raw and analysis-ready BPM. It rejects
missing, stale (>90 seconds), and broadly implausible readings outside 30-220
BPM. A rolling median/MAD rule marks temporal outliers without deleting them.
HealthKit does not expose Android-style per-sample contact/accuracy states, so
those fields remain unknown rather than being fabricated.

## Bounded WatchConnectivity ingestion

WatchConnectivity may deliver queued data while Flutter is not yet active. The
old iPhone bridge replayed every pending sensor/EMA payload at once, which could
increase launch memory pressure. The current bridge persists all payloads but
emits only one eligible item to Flutter at a time. Dart stores and acknowledges
that item before requesting the next one.

## Research export crash investigation and repair

The crash report did not include an iOS stack trace, so no single cause can be
proven from the archived source alone. The old code nevertheless contained
three concrete iOS risks:

1. `sharePositionOrigin` could be null or unusable. Older `share_plus` versions
   document that iPad can crash or become unresponsive without a valid anchor.
2. Large Firestore exports were compressed on the Flutter UI isolate.
3. The temporary ZIP was deleted immediately after the share future completed,
   which could race an iOS share extension that was still reading the file.

The updated implementation:

- always passes a non-zero share origin with a centered fallback;
- compresses the ZIP in `Isolate.run`;
- shares an `XFile` with MIME type `application/zip`;
- does not delete the temporary ZIP immediately;
- removes stale work directories and ZIPs before the next export.

`share_plus` remains on the repository-compatible 11.1.x line. Do not upgrade
only this package without checking the project's Flutter/Dart/Gradle versions.

## Firebase setup

Firebase requires a separate Apple app registration. Register:

```text
com.recoverysense.phone
```

Download `GoogleService-Info.plist`, add it to the Runner target, and regenerate
FlutterFire options on the Mac:

```zsh
dart pub global activate flutterfire_cli
flutterfire configure \
  --project=recoverysense \
  --platforms=ios,android \
  --ios-bundle-id=com.recoverysense.phone
```

The archive intentionally contains no real Firebase Apple configuration or
signing material.

## Build procedure

```zsh
cd apps/phone_flutter_new
flutter clean
flutter pub get
open ios/Runner.xcworkspace
```

In Xcode:

1. Assign one Development Team to `Runner` and `RecoverySenseWatch`.
2. Confirm bundle IDs `com.recoverysense.phone` and
   `com.recoverysense.phone.watchkitapp`.
3. Confirm the iPhone Firebase plist is part of Runner.
4. Run Runner on the paired iPhone.
5. Grant Health and Motion permissions on the watch.
6. Test screen-off collection, midnight step rollover, offline backlog replay,
   EMA save/ACK, sleep start/stop, and research export.

## Validation included in this package

- Swift parser checks for all watch and bridge source.
- plist/entitlement structural checks.
- Xcode source-reference and target checks.
- schema-5 Android/Dart/iOS contract test.
- daily-step, one-at-a-time replay, and export-safety static checks.
- current Python ML/backend tests and repository audits where available.

## Remaining validation

This environment is not macOS and cannot run Xcode, Apple signing,
or paired hardware. The source is therefore not claimed to be Xcode-compiled or
physically validated. Final device verification remains required before any
research deployment.
