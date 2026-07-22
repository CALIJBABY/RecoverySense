# RecoverySense Architecture

```text
Wear OS Watch / Apple Watch
        ↓
Sensor collection
Heart rate, accelerometer, optional HRV/sleep/SpO2
        ↓
Phone app
Login, dashboard, EMA, local trigger logic
        ↓
Firebase or custom backend
Auth, database, cloud storage, notifications
        ↓
ML pipeline
Feature extraction, risk scoring, EMA trigger decision
```

## MVP architecture

```text
Galaxy Watch 4
  └── Kotlin Wear OS app
        ├── Heart-rate service
        ├── Accelerometer service
        └── Data Layer sender

Android/iOS Phone
  └── Flutter app
        ├── Login
        ├── Sensor dashboard
        ├── EMA questions
        ├── Trigger engine
        └── Firebase client
```

## Future iOS architecture

```text
Apple Watch
  └── Swift watchOS app
        ├── HealthKit
        ├── CoreMotion
        └── WatchConnectivity

IPhone
  └── Flutter app with native bridge
```
