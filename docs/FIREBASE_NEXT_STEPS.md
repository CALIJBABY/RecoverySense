> **Historical planning/prototype document.** It does not describe the current version 0.5.1 implementation. See `docs/CURRENT_DOCUMENTATION_INDEX.md`.

# Firebase Next Steps

After the mock UI works, add Firebase.

## 1. Create Firebase project

Use Firebase Console and create Android/iOS apps later.

## 2. Add packages to Flutter

```bash
flutter pub add firebase_core firebase_auth cloud_firestore
```

## 3. Replace mock services

Replace:

```text
MockAuthService
MockSensorRepository
```

with:

```text
FirebaseAuthService
FirestoreSensorRepository
```

## 4. Collections

Suggested collections:

```text
users/{uid}
participants/{participantId}/sensor_readings/{readingId}
participants/{participantId}/ema_answers/{answerId}
```
