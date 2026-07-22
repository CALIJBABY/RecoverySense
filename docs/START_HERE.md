# Start Here

Do these in order.

## Day 1

Run the Flutter phone app.

```bash
cd apps/phone_flutter
flutter pub get
flutter run
```

Goal: see Login -> Dashboard -> EMA.

## Day 2

Open `apps/wear_android` in Android Studio.

Goal: run the Wear OS screen on emulator/watch.

## Day 3

Press `Send` on the watch app.

Goal: confirm the watch app can format and send a sensor payload. Phone receiver is the next task.

## What is intentionally fake right now

- Phone login is mock login.
- Phone sensor data is simulated.
- Wear heart rate is simulated.
- Firebase is not connected yet.

This is intentional. The first milestone is to make the screens and flow easy to understand.
