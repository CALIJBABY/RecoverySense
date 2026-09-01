import 'heart_rate_quality.dart';

class WatchSensorSample {
  final int schemaVersion;
  final int? heartRate;
  final int? rawHeartRate;
  final int? heartRateAgeMs;
  final bool heartRateValid;
  final int heartRateQualityCode;
  final bool heartRateOutlier;
  final double accelX;
  final double accelY;
  final double accelZ;
  final double accelerationG;
  final double? gyroX;
  final double? gyroY;
  final double? gyroZ;
  final double? gyroMagnitude;
  final double? stepCount;
  final bool? offBody;
  final bool? screenInteractive;
  final String ppgState;
  final String recordingMode;
  final String? sleepSessionId;
  final DateTime timestamp;

  const WatchSensorSample({
    required this.schemaVersion,
    required this.heartRate,
    required this.rawHeartRate,
    required this.heartRateAgeMs,
    required this.heartRateValid,
    required this.heartRateQualityCode,
    required this.heartRateOutlier,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.accelerationG,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.gyroMagnitude,
    required this.stepCount,
    required this.offBody,
    required this.screenInteractive,
    required this.ppgState,
    required this.recordingMode,
    required this.sleepSessionId,
    required this.timestamp,
  });

  String get heartRateQualityReason =>
      HeartRateQuality.reason(heartRateQualityCode);

  factory WatchSensorSample.fromMap(Map<dynamic, dynamic> map) {
    final schemaVersion = _asInt(map['schemaVersion']) ?? 1;
    final analysisHeartRate = _asInt(map['heartRate']);
    final rawHeartRate = _asInt(map['rawHeartRate']) ?? analysisHeartRate;
    final rawOffBodyValue = _asInt(map['offBody']);
    final offBodyValue = rawOffBodyValue == null || rawOffBodyValue < 0
        ? rawOffBodyValue
        : schemaVersion <= 4
            ? (rawOffBodyValue == 1 ? 0 : 1)
            : rawOffBodyValue;
    final parsedValid = _asBool(map['heartRateValid']) ??
        (analysisHeartRate != null && analysisHeartRate > 0);
    final normalizedOffBody = offBodyValue != null && offBodyValue == 1;
    final valid = normalizedOffBody ? false : parsedValid;
    final parsedQualityCode = _asInt(map['heartRateQualityCode']) ??
        (valid ? HeartRateQuality.valid : HeartRateQuality.noReading);
    final qualityCode =
        normalizedOffBody ? HeartRateQuality.offBody : parsedQualityCode;
    return WatchSensorSample(
      schemaVersion: schemaVersion,
      heartRate: valid && analysisHeartRate != null && analysisHeartRate > 0
          ? analysisHeartRate
          : null,
      rawHeartRate:
          rawHeartRate != null && rawHeartRate > 0 ? rawHeartRate : null,
      heartRateAgeMs: _nullableNonNegativeInt(map['heartRateAgeMs']),
      heartRateValid: valid,
      heartRateQualityCode: qualityCode,
      heartRateOutlier: _asBool(map['heartRateOutlier']) ?? false,
      accelX: _asDouble(map['accelX']) ?? 0,
      accelY: _asDouble(map['accelY']) ?? 0,
      accelZ: _asDouble(map['accelZ']) ?? 0,
      accelerationG: _asDouble(map['accelerationG']) ?? 0,
      gyroX: _finiteDouble(map['gyroX']),
      gyroY: _finiteDouble(map['gyroY']),
      gyroZ: _finiteDouble(map['gyroZ']),
      gyroMagnitude: _finiteDouble(map['gyroMagnitude']),
      stepCount: _finiteDouble(map['stepCount']),
      offBody:
          offBodyValue == null || offBodyValue < 0 ? null : offBodyValue == 1,
      screenInteractive: _asBool(map['screenInteractive']),
      ppgState: map['ppgState']?.toString() ?? 'unknown',
      recordingMode: map['recordingMode']?.toString() ?? 'continuous',
      sleepSessionId: _nullableString(map['sleepSessionId']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        _asInt(map['timestamp']) ?? DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      ),
    );
  }

  static int? _nullableNonNegativeInt(dynamic value) {
    final parsed = _asInt(value);
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  static bool? _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().toLowerCase();
    if (text == 'true') return true;
    if (text == 'false') return false;
    return null;
  }

  static String? _nullableString(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static double? _finiteDouble(dynamic value) {
    final parsed = _asDouble(value);
    return parsed != null && parsed.isFinite ? parsed : null;
  }
}
