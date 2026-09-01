class WatchSensorBatch {
  final String uri;
  final String batchId;
  final String watchSessionId;
  final int sequence;
  final int samplingRateHz;
  final int schemaVersion;
  final String recordingMode;
  final String? sleepSessionId;
  final DateTime createdAt;
  final List<int> timestampsMs;
  final List<int> heartRates;
  final List<int> heartRateTimestampsMs;
  final List<int> heartRateAgeMs;
  final List<int> heartRateAccuracy;
  final List<double> accelX;
  final List<double> accelY;
  final List<double> accelZ;
  final List<double> accelerationG;
  final List<int> accelAccuracy;
  final List<double> gyroX;
  final List<double> gyroY;
  final List<double> gyroZ;
  final List<double> gyroMagnitude;
  final List<int> gyroTimestampsMs;
  final List<int> gyroAccuracy;
  final List<double> stepCounts;
  final List<int> stepDetected;
  final List<int> offBody;
  final List<int> screenInteractive;
  final bool heartRateAvailable;
  final bool accelerometerAvailable;
  final bool gyroscopeAvailable;
  final bool stepCounterAvailable;
  final bool stepDetectorAvailable;
  final bool offBodyAvailable;
  final bool ppgAvailable;
  final String ppgState;

  const WatchSensorBatch({
    required this.uri,
    required this.batchId,
    required this.watchSessionId,
    required this.sequence,
    required this.samplingRateHz,
    required this.schemaVersion,
    required this.recordingMode,
    required this.sleepSessionId,
    required this.createdAt,
    required this.timestampsMs,
    required this.heartRates,
    required this.heartRateTimestampsMs,
    required this.heartRateAgeMs,
    required this.heartRateAccuracy,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.accelerationG,
    required this.accelAccuracy,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.gyroMagnitude,
    required this.gyroTimestampsMs,
    required this.gyroAccuracy,
    required this.stepCounts,
    required this.stepDetected,
    required this.offBody,
    required this.screenInteractive,
    required this.heartRateAvailable,
    required this.accelerometerAvailable,
    required this.gyroscopeAvailable,
    required this.stepCounterAvailable,
    required this.stepDetectorAvailable,
    required this.offBodyAvailable,
    required this.ppgAvailable,
    required this.ppgState,
  });

  int get sampleCount => timestampsMs.length;

  bool get isSleepBatch =>
      recordingMode == 'sleep' && sleepSessionId != null;

  factory WatchSensorBatch.fromMap(Map<dynamic, dynamic> map) {
    final timestamps = _intList(map['timestamps']);
    if (timestamps.isEmpty) {
      throw const FormatException('Sensor batch contains no timestamps.');
    }
    final size = timestamps.length;

    final heartRates = _intListOrDefault(map['heartRates'], size, -1);
    final heartRateTimestamps =
        _intListOrDefault(map['heartRateTimestamps'], size, -1);
    final heartRateAgeMs =
        _intListOrDefault(map['heartRateAgeMs'], size, -1);
    final heartRateAccuracy =
        _intListOrDefault(map['heartRateAccuracy'], size, 0);
    final accelX = _requiredDoubleList(map['accelX'], size, 'accelX');
    final accelY = _requiredDoubleList(map['accelY'], size, 'accelY');
    final accelZ = _requiredDoubleList(map['accelZ'], size, 'accelZ');
    final accelerationG =
        _requiredDoubleList(map['accelerationG'], size, 'accelerationG');
    final accelAccuracy = _intListOrDefault(map['accelAccuracy'], size, 0);
    final gyroX = _doubleListOrDefault(map['gyroX'], size, double.nan);
    final gyroY = _doubleListOrDefault(map['gyroY'], size, double.nan);
    final gyroZ = _doubleListOrDefault(map['gyroZ'], size, double.nan);
    final gyroMagnitude =
        _doubleListOrDefault(map['gyroMagnitude'], size, double.nan);
    final gyroTimestamps =
        _intListOrDefault(map['gyroTimestamps'], size, -1);
    final gyroAccuracy = _intListOrDefault(map['gyroAccuracy'], size, 0);
    final stepCounts =
        _doubleListOrDefault(map['stepCounts'], size, double.nan);
    final stepDetected = _intListOrDefault(map['stepDetected'], size, 0);
    final offBody = _intListOrDefault(map['offBody'], size, -1);
    final screenInteractive =
        _intListOrDefault(map['screenInteractive'], size, -1);

    return WatchSensorBatch(
      uri: map['uri']?.toString() ?? '',
      batchId: map['batchId']?.toString() ?? '',
      watchSessionId: map['watchSessionId']?.toString() ?? 'unknown',
      sequence: _asInt(map['sequence']) ?? 0,
      samplingRateHz: _asInt(map['samplingRateHz']) ?? 10,
      schemaVersion: _asInt(map['schemaVersion']) ?? 1,
      recordingMode: map['recordingMode']?.toString() ?? 'continuous',
      sleepSessionId: _nullableString(map['sleepSessionId']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        _asInt(map['createdAt']) ?? DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      ),
      timestampsMs: timestamps,
      heartRates: heartRates,
      heartRateTimestampsMs: heartRateTimestamps,
      heartRateAgeMs: heartRateAgeMs,
      heartRateAccuracy: heartRateAccuracy,
      accelX: accelX,
      accelY: accelY,
      accelZ: accelZ,
      accelerationG: accelerationG,
      accelAccuracy: accelAccuracy,
      gyroX: gyroX,
      gyroY: gyroY,
      gyroZ: gyroZ,
      gyroMagnitude: gyroMagnitude,
      gyroTimestampsMs: gyroTimestamps,
      gyroAccuracy: gyroAccuracy,
      stepCounts: stepCounts,
      stepDetected: stepDetected,
      offBody: offBody,
      screenInteractive: screenInteractive,
      heartRateAvailable: _asBool(map['heartRateAvailable'], fallback: true),
      accelerometerAvailable:
          _asBool(map['accelerometerAvailable'], fallback: true),
      gyroscopeAvailable:
          _asBool(map['gyroscopeAvailable'], fallback: false),
      stepCounterAvailable:
          _asBool(map['stepCounterAvailable'], fallback: false),
      stepDetectorAvailable:
          _asBool(map['stepDetectorAvailable'], fallback: false),
      offBodyAvailable: _asBool(map['offBodyAvailable'], fallback: false),
      ppgAvailable: _asBool(map['ppgAvailable'], fallback: false),
      ppgState: map['ppgState']?.toString() ?? 'unknown',
    );
  }

  Map<String, bool> get sensorCapabilities => <String, bool>{
        'heart_rate': heartRateAvailable,
        'accelerometer': accelerometerAvailable,
        'gyroscope': gyroscopeAvailable,
        'step_counter': stepCounterAvailable,
        'step_detector': stepDetectorAvailable,
        'off_body': offBodyAvailable,
      };

  Map<String, Object?> get qualitySummary {
    final validHeartRates = heartRates.where((value) => value > 0).length;
    final validGyroscope = gyroMagnitude.where((value) => value.isFinite).length;
    final knownOffBody = offBody.where((value) => value >= 0).toList();
    final knownScreen = screenInteractive.where((value) => value >= 0).toList();
    final knownHeartRateAge =
        heartRateAgeMs.where((value) => value >= 0).toList();
    final offBodyCount = knownOffBody.where((value) => value == 1).length;

    return <String, Object?>{
      'valid_heart_rate_fraction': validHeartRates / sampleCount,
      'valid_gyroscope_fraction': validGyroscope / sampleCount,
      'off_body_fraction': knownOffBody.isEmpty
          ? null
          : offBodyCount / knownOffBody.length,
      'screen_off_fraction': knownScreen.isEmpty
          ? null
          : knownScreen.where((value) => value == 0).length / knownScreen.length,
      'mean_heart_rate_age_ms':
          knownHeartRateAge.isEmpty ? null : _meanInt(knownHeartRateAge),
      'step_event_count': stepDetected.fold<int>(0, (sum, value) => sum + value),
      'heart_rate_accuracy_mean': _meanInt(heartRateAccuracy),
      'accelerometer_accuracy_mean': _meanInt(accelAccuracy),
      'gyroscope_accuracy_mean': _meanInt(gyroAccuracy),
    };
  }

  List<Map<String, Object?>> toFirestoreSamples() {
    return List<Map<String, Object?>>.generate(sampleCount, (index) {
      final heartRate = heartRates[index];
      final offBodyValue = offBody[index];
      return <String, Object?>{
        'timestamp_ms': timestampsMs[index],
        'heart_rate': heartRate > 0 ? heartRate : null,
        'heart_rate_timestamp_ms': heartRateTimestampsMs[index] > 0
            ? heartRateTimestampsMs[index]
            : null,
        'heart_rate_age_ms':
            heartRateAgeMs[index] >= 0 ? heartRateAgeMs[index] : null,
        'heart_rate_accuracy': heartRateAccuracy[index],
        'accel_x_ms2': _finiteOrNull(accelX[index]),
        'accel_y_ms2': _finiteOrNull(accelY[index]),
        'accel_z_ms2': _finiteOrNull(accelZ[index]),
        'acceleration_g': _finiteOrNull(accelerationG[index]),
        'accelerometer_accuracy': accelAccuracy[index],
        'gyro_x_rad_s': _finiteOrNull(gyroX[index]),
        'gyro_y_rad_s': _finiteOrNull(gyroY[index]),
        'gyro_z_rad_s': _finiteOrNull(gyroZ[index]),
        'gyro_magnitude_rad_s': _finiteOrNull(gyroMagnitude[index]),
        'gyro_timestamp_ms': gyroTimestampsMs[index] > 0
            ? gyroTimestampsMs[index]
            : null,
        'gyroscope_accuracy': gyroAccuracy[index],
        'step_count': _finiteOrNull(stepCounts[index]),
        'step_detected': stepDetected[index],
        'off_body': offBodyValue < 0 ? null : offBodyValue == 1,
        'screen_interactive': screenInteractive[index] < 0
            ? null
            : screenInteractive[index] == 1,
      };
    }, growable: false);
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

  static bool _asBool(dynamic value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().toLowerCase();
    if (text == 'true') return true;
    if (text == 'false') return false;
    return fallback;
  }

  static List<int> _intList(dynamic value) {
    if (value is! List) return const <int>[];
    return value.map(_asInt).whereType<int>().toList(growable: false);
  }

  static List<int> _intListOrDefault(
    dynamic value,
    int size,
    int defaultValue,
  ) {
    final parsed = _intList(value);
    if (parsed.length == size) return parsed;
    return List<int>.filled(size, defaultValue, growable: false);
  }

  static List<double> _doubleList(dynamic value) {
    if (value is! List) return const <double>[];
    return value.map((dynamic item) {
      if (item is num) return item.toDouble();
      return double.tryParse(item?.toString() ?? '');
    }).whereType<double>().toList(growable: false);
  }

  static List<double> _doubleListOrDefault(
    dynamic value,
    int size,
    double defaultValue,
  ) {
    final parsed = _doubleList(value);
    if (parsed.length == size) return parsed;
    return List<double>.filled(size, defaultValue, growable: false);
  }

  static List<double> _requiredDoubleList(
    dynamic value,
    int size,
    String field,
  ) {
    final parsed = _doubleList(value);
    if (parsed.length != size) {
      throw FormatException('Sensor batch field $field is missing or misaligned.');
    }
    return parsed;
  }

  static double? _finiteOrNull(double value) => value.isFinite ? value : null;

  static double _meanInt(List<int> values) {
    if (values.isEmpty) return 0;
    return values.fold<int>(0, (sum, value) => sum + value) / values.length;
  }
}
