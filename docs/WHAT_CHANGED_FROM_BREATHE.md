> **Historical planning/prototype document.** It does not describe the current version 0.5.1 implementation. See `docs/CURRENT_DOCUMENTATION_INDEX.md`.

# What Changed From the Original BREATHE Code

## Kept conceptually

- Watch collects physiological and motion sensor data.
- Phone receives wearable data.
- Data is batched with timestamps.
- Risk/trigger logic causes a questionnaire or user-facing prompt.
- Shared constants/messages are kept in one place.

## Removed as obsolete

- Old Android Gradle plugin and SDK 23 configuration.
- Old Android Wear APIs and old Google Play Services versions.
- BreathePlatform server URLs and asthma-specific API paths.
- Dust sensor, AirBeam, and spirometer-specific code for the MVP.
- Hardcoded API keys, private keys, and certificate files.
- Old encryption implementation with fixed IV.
- Generated folders such as `.gradle/`, `build/`, `.idea/`, and `captures/`.
- Asthma-specific dragon UI and pediatric asthma risk screens.
- Calendar service and unrelated Android broadcast receiver logic.

## Replaced with modern structure

- Phone app becomes Flutter for Android/iOS shared UI.
- Android watch app becomes a modern Wear OS Kotlin module.
- Apple Watch support is separated into a Swift/watchOS skeleton.
- Backend starts with Firebase but leaves room for a custom FastAPI backend.
- ML moves into a standalone Python folder with feature extraction and model training.
- EMA questions are addiction/recovery focused instead of asthma focused.

## New RecoverySense focus

- Login.
- Wearable heart-rate and accelerometer display.
- Watch-to-phone sensor transfer.
- EMA prompts triggered by heart rate, HRV features, accelerometer activity, or ML risk score.
- Future model support: logistic regression, random forest, XGBoost, TensorFlow Lite, Core ML.
