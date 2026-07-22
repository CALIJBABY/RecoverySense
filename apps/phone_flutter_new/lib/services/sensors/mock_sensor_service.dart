import '../../models/sensor_snapshot.dart';

class MockSensorService {
  SensorSnapshot latest() {
    return SensorSnapshot(
      heartRate: 76,
      accelX: 0.12,
      accelY: -0.04,
      accelZ: 0.98,
      timestamp: DateTime.now(),
    );
  }
}
