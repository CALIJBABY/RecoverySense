class SensorSnapshot {
  final int heartRate;
  final double accelX;
  final double accelY;
  final double accelZ;
  final DateTime timestamp;

  const SensorSnapshot({
    required this.heartRate,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.timestamp,
  });

  double get accelMagnitude {
    return (accelX.abs() + accelY.abs() + accelZ.abs()) / 3;
  }
}
