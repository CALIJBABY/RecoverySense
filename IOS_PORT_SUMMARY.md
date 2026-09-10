# RecoverySense iOS parity summary - 0.5.3.4

This package updates the previously created iPhone/Apple Watch port to the
current RecoverySense Android application state.

```text
Android phone: Flutter/Dart + Kotlin bridge
Galaxy Watch:  Kotlin/Jetpack Compose

iPhone:        same current Flutter/Dart UI + Swift bridge
Apple Watch:   Swift/SwiftUI + HealthKit/Core Motion
```

## Current parity included

- Current shared Flutter phone UI, including Home, Live, Check-in, Sleep, and
  History navigation.
- Current sensor-backed risk display and three positive companion-tree factors.
- Current schema-5 heart-rate quality fields.
- Current 0-10 EMA with participant-local timing metadata.
- Current 10 Hz / 30-second sensor-batch contract.
- Apple Watch stacked sensor-card UI using `#4F9B17` and white text.
- Apple Watch Steps Today value counted from local midnight and restored after
  app/service restarts by querying the pedometer from the start of the day.
- Continuous and sleep recording modes.
- Durable WatchConnectivity queues and one-at-a-time iPhone-to-Flutter replay.
- Raw optical PPG remains explicitly unavailable through the public Apple APIs
  used by this project.

## Research export stability fix

The prior shared Flutter export path could fail on Apple devices for three
reasons addressed here:

1. iPad share sheets require a usable popover origin.
2. ZIP compression could monopolize the UI isolate for a large sensor history.
3. The temporary ZIP was deleted immediately after the share future returned,
   while an iOS share extension could still be reading it.

The current package provides a non-zero share origin, compresses in a Dart
isolate, supplies the ZIP MIME type, and leaves the temporary ZIP until the
next export's stale-file cleanup.

## Local requirements not embedded in this archive

- A Mac with Xcode and 
- Apple Development Team/signing for both targets.
- A Firebase iOS app registration for `com.recoverysense.phone`.
- A real `GoogleService-Info.plist` and regenerated `firebase_options.dart`.
- A paired physical iPhone/Apple Watch for HealthKit and WatchConnectivity
  testing.

Read `docs/IOS_IMPLEMENTATION.md` and run `scripts/verify_ios_contract.py`.

## 0.5.3.5 shared research-export stability

The iPhone and Android phone now use the same bounded-memory Flutter export flow: small pages for heavy sensor documents, disk-spooled dynamic CSV rows, periodic sink flushing, off-UI-isolate ZIP creation, ZIP verification, ZIP MIME metadata, a valid Apple popover origin, and deferred stale-file cleanup. The change does not alter WatchConnectivity, HealthKit, watch sensing, EMA, sleep, or model semantics.
