# Firebase Later

Firebase is intentionally not connected yet. First make sure the app runs.

When ready, add:

```powershell
dart pub global activate flutterfire_cli
flutterfire configure
flutter pub add firebase_core firebase_auth cloud_firestore
```

Then initialize Firebase in `lib/main.dart` and replace mock login with Firebase Auth.
