# RecoverySense Wear OS App

First Wear OS Kotlin app for RecoverySense.

It displays:
- Heart rate
- Accelerometer magnitude
- Status

It also sends a basic snapshot through the Wear OS Data Layer path:

`/recoverysense/sensors`

Put this folder at:

`RecoverySenseRunnableStarter/RecoverySenseRunnableStarter/apps/wear_android`

Run from PowerShell:

```powershell
cd C:\Users\user\Downloads\RecoverySenseRunnableStarter\RecoverySenseRunnableStarter\apps\wear_android
.\gradlew.bat assembleDebug
```

Or open `apps/wear_android` in Android Studio and run it on a Wear OS emulator.
