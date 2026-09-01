class WatchPpgBatch {
  final String uri;
  final String batchId;
  final String watchSessionId;
  final int sequence;
  final int samplingRateHz;
  final int schemaVersion;
  final String recordingMode;
  final String? sleepSessionId;
  final String source;
  final DateTime createdAt;
  final List<int> timestampsMs;
  final List<int> green;
  final List<int> infrared;
  final List<int> red;
  final List<int> greenStatus;
  final List<int> infraredStatus;
  final List<int> redStatus;

  const WatchPpgBatch({
    required this.uri,
    required this.batchId,
    required this.watchSessionId,
    required this.sequence,
    required this.samplingRateHz,
    required this.schemaVersion,
    required this.recordingMode,
    required this.sleepSessionId,
    required this.source,
    required this.createdAt,
    required this.timestampsMs,
    required this.green,
    required this.infrared,
    required this.red,
    required this.greenStatus,
    required this.infraredStatus,
    required this.redStatus,
  });

  int get sampleCount => timestampsMs.length;
  bool get isSleepBatch =>
      recordingMode == 'sleep' && sleepSessionId != null;

  factory WatchPpgBatch.fromMap(Map<dynamic, dynamic> map) {
    final timestamps = _intList(map['timestamps']);
    if (timestamps.isEmpty) {
      throw const FormatException('PPG batch contains no timestamps.');
    }
    final size = timestamps.length;
    return WatchPpgBatch(
      uri: map['uri']?.toString() ?? '',
      batchId: map['batchId']?.toString() ?? '',
      watchSessionId: map['watchSessionId']?.toString() ?? 'unknown',
      sequence: _asInt(map['sequence']) ?? 0,
      samplingRateHz: _asInt(map['samplingRateHz']) ?? 25,
      schemaVersion: _asInt(map['schemaVersion']) ?? 1,
      recordingMode: map['recordingMode']?.toString() ?? 'continuous',
      sleepSessionId: _nullableString(map['sleepSessionId']),
      source: map['source']?.toString() ?? 'unknown',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        _asInt(map['createdAt']) ?? DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      ),
      timestampsMs: timestamps,
      green: _requiredIntList(map['green'], size, 'green'),
      infrared: _requiredIntList(map['infrared'], size, 'infrared'),
      red: _requiredIntList(map['red'], size, 'red'),
      greenStatus: _intListOrDefault(map['greenStatus'], size, -1),
      infraredStatus: _intListOrDefault(map['infraredStatus'], size, -1),
      redStatus: _intListOrDefault(map['redStatus'], size, -1),
    );
  }

  Map<String, Object?> get qualitySummary {
    final validGreen = _validFraction(green, greenStatus);
    final validInfrared = _validFraction(infrared, infraredStatus);
    final validRed = _validFraction(red, redStatus);
    final expectedDurationMs = sampleCount <= 1
        ? 0.0
        : (sampleCount - 1) * 1000.0 / samplingRateHz;
    final observedDurationMs = sampleCount <= 1
        ? 0.0
        : (timestampsMs.last - timestampsMs.first).toDouble();
    final timingCoverage = expectedDurationMs <= 0
        ? 1.0
        : (observedDurationMs / expectedDurationMs).clamp(0.0, 2.0);
    return <String, Object?>{
      'green_valid_fraction': validGreen,
      'infrared_valid_fraction': validInfrared,
      'red_valid_fraction': validRed,
      'all_channels_valid_fraction': _allValidFraction(),
      'timing_coverage_ratio': timingCoverage,
      'nominal_sampling_rate_hz': samplingRateHz,
      'sample_count': sampleCount,
    };
  }

  List<Map<String, Object?>> toFirestoreSamples() {
    return List<Map<String, Object?>>.generate(sampleCount, (index) {
      return <String, Object?>{
        'timestamp_ms': timestampsMs[index],
        'green_adc': _validValue(green[index]),
        'infrared_adc': _validValue(infrared[index]),
        'red_adc': _validValue(red[index]),
        'green_status': greenStatus[index],
        'infrared_status': infraredStatus[index],
        'red_status': redStatus[index],
      };
    }, growable: false);
  }

  double _allValidFraction() {
    if (sampleCount == 0) return 0;
    var valid = 0;
    for (var index = 0; index < sampleCount; index += 1) {
      if (_isValid(green[index], greenStatus[index]) &&
          _isValid(infrared[index], infraredStatus[index]) &&
          _isValid(red[index], redStatus[index])) {
        valid += 1;
      }
    }
    return valid / sampleCount;
  }

  static double _validFraction(List<int> values, List<int> status) {
    if (values.isEmpty) return 0;
    var valid = 0;
    for (var index = 0; index < values.length; index += 1) {
      if (_isValid(values[index], status[index])) valid += 1;
    }
    return valid / values.length;
  }

  // Samsung PPG_CONTINUOUS status 0 is normal; -1 means the channel was
  // interrupted by a higher-priority sensor operation. Raw values and status
  // are still retained so preprocessing decisions remain reproducible.
  static bool _isValid(int value, int status) =>
      value != -2147483648 && status == 0;

  static int? _validValue(int value) =>
      value == -2147483648 ? null : value;

  static String? _nullableString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
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

  static List<int> _requiredIntList(dynamic value, int size, String field) {
    final parsed = _intList(value);
    if (parsed.length != size) {
      throw FormatException('PPG batch field $field is missing or misaligned.');
    }
    return parsed;
  }
}
