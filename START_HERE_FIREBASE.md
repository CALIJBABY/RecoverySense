# Start here: connecting Firebase

Your Flutter phone app is here:

```text
apps/phone_flutter
```

In VS Code, open the whole repository folder, then open the terminal and run:

```bash
cd apps/phone_flutter
flutter pub get
flutter run
```

Once that works, go back to the Firebase console and continue the Flutter setup.

When Firebase asks for the app/package ID, use:

```text
edu.uci.recoverysense.phone
```

Then run:

```bash
firebase login
dart pub global activate flutterfire_cli
flutterfire configure --project recoverysense
```
