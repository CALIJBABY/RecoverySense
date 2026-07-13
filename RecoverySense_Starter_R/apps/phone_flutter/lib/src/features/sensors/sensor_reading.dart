class SensorReading {
  final DateTime timestamp;
  final double? heartRate;
  final double? accelX;
  final double? accelY;
  final double? accelZ;

  const SensorReading({
    required this.timestamp,
    this.heartRate,
    this.accelX,
    this.accelY,
    this.accelZ,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'heartRate': heartRate,
        'accelX': accelX,
        'accelY': accelY,
        'accelZ': accelZ,
      };
}
