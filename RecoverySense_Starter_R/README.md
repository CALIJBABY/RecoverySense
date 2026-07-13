# RecoverySense Starter Repo

RecoverySense is an AIoT prototype for collecting wearable sensor data and triggering phone-based EMA questions.

## Current MVP scope

Build only this first:

1. Phone app login screen and dashboard.
2. Wear OS screen showing heart rate and accelerometer values.
3. Watch-to-phone sensor payload format.
4. EMA question flow on the phone.
5. Basic rule-based trigger before machine learning.

## Folder layout

```text
apps/phone_flutter/      Cross-platform phone app starter code
apps/wear_android/       Wear OS Kotlin starter code
apps/watch_ios/          Future Apple Watch placeholder only
firebase/                Firestore rules and Firebase notes
backend/api/             Optional FastAPI backend for later
ml/                      Python feature extraction and baseline ML
scripts/                 Setup helper scripts
docs/                    Architecture and planning notes
```

## What to run first

Start with the phone app:

```bash
cd apps/phone_flutter
flutter pub get
flutter run
```

Then open the Wear OS project in Android Studio:

```text
apps/wear_android
```

Run it on a Wear OS emulator or Galaxy Watch 4.

## Important note

Firebase is represented by service stubs in the Flutter app. This lets the app run before you configure a real Firebase project. Replace the mock service with real Firebase Auth and Firestore after the UI flow works.
