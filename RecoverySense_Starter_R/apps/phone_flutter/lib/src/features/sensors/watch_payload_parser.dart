import '../../models/sensor_reading.dart';

class WatchPayloadParser {
  SensorReading fromJson(Map<String, dynamic> json) {
    return SensorReading(
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      heartRate: (json['heartRate'] as num?)?.toDouble() ?? 0,
      accelX: (json['accelX'] as num?)?.toDouble() ?? 0,
      accelY: (json['accelY'] as num?)?.toDouble() ?? 0,
      accelZ: (json['accelZ'] as num?)?.toDouble() ?? 0,
    );
  }
}
