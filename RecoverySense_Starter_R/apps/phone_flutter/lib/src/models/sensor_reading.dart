class SensorReading {
  const SensorReading({
    required this.timestamp,
    required this.heartRate,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
  });

  final DateTime timestamp;
  final double heartRate;
  final double accelX;
  final double accelY;
  final double accelZ;

  double get accelMagnitude =>
      (accelX * accelX + accelY * accelY + accelZ * accelZ);

  Map<String, Object> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'heartRate': heartRate,
      'accelX': accelX,
      'accelY': accelY,
      'accelZ': accelZ,
      'accelMagnitudeSquared': accelMagnitude,
    };
  }
}
