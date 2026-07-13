# Connect this Flutter app to Firebase

Run these commands from this folder:

```bash
cd apps/phone_flutter
flutter pub get
```

Install Firebase CLI if needed:

```bash
npm install -g firebase-tools
firebase login
```

Install FlutterFire CLI:

```bash
dart pub global activate flutterfire_cli
```

Then connect to your Firebase project:

```bash
flutterfire configure --project recoverysense
```

Pick these platforms first:

- Android
- iOS only if you are on a Mac or plan to support iPhone soon
- Web optional

For Android package name use:

```text
edu.uci.recoverysense.phone
```

FlutterFire should generate:

```text
lib/firebase_options.dart
android/app/google-services.json
```

After that, add Firebase packages:

```bash
flutter pub add firebase_core firebase_auth cloud_firestore
```

Then update `lib/main.dart` to initialize Firebase.
