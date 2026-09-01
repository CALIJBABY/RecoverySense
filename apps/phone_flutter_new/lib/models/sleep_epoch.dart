class SleepEpochEstimate {
  final String sleepSessionId;
  final String batchId;
  final DateTime start;
  final DateTime end;
  final double sleepProbability;
  final bool? isSleep;
  final double movementStdG;
  final double meanGravityDeviationG;
  final double? meanGyroscopeRadS;
  final double? meanHeartRate;
  final int stepEvents;
  final double? offBodyFraction;
  final double dataCoverage;

  const SleepEpochEstimate({
    required this.sleepSessionId,
    required this.batchId,
    required this.start,
    required this.end,
    required this.sleepProbability,
    required this.isSleep,
    required this.movementStdG,
    required this.meanGravityDeviationG,
    required this.meanGyroscopeRadS,
    required this.meanHeartRate,
    required this.stepEvents,
    required this.offBodyFraction,
    required this.dataCoverage,
  });

  Map<String, Object?> toFirestore() => <String, Object?>{
        'sleep_session_id': sleepSessionId,
        'batch_id': batchId,
        'epoch_start_ms': start.millisecondsSinceEpoch,
        'epoch_end_ms': end.millisecondsSinceEpoch,
        'sleep_probability': sleepProbability,
        'is_sleep': isSleep,
        'movement_std_g': movementStdG,
        'mean_gravity_deviation_g': meanGravityDeviationG,
        'mean_gyroscope_rad_s': meanGyroscopeRadS,
        'mean_heart_rate': meanHeartRate,
        'step_events': stepEvents,
        'off_body_fraction': offBodyFraction,
        'data_coverage': dataCoverage,
        'estimator_version': 'rules-v1',
      };

  factory SleepEpochEstimate.fromMap(Map<String, dynamic> map) {
    return SleepEpochEstimate(
      sleepSessionId: map['sleep_session_id']?.toString() ?? '',
      batchId: map['batch_id']?.toString() ?? '',
      start: DateTime.fromMillisecondsSinceEpoch(
        _asInt(map['epoch_start_ms']) ?? 0,
        isUtc: true,
      ),
      end: DateTime.fromMillisecondsSinceEpoch(
        _asInt(map['epoch_end_ms']) ?? 0,
        isUtc: true,
      ),
      sleepProbability: _asDouble(map['sleep_probability']) ?? 0,
      isSleep: map['is_sleep'] is bool ? map['is_sleep'] as bool : null,
      movementStdG: _asDouble(map['movement_std_g']) ?? 0,
      meanGravityDeviationG:
          _asDouble(map['mean_gravity_deviation_g']) ?? 0,
      meanGyroscopeRadS: _asDouble(map['mean_gyroscope_rad_s']),
      meanHeartRate: _asDouble(map['mean_heart_rate']),
      stepEvents: _asInt(map['step_events']) ?? 0,
      offBodyFraction: _asDouble(map['off_body_fraction']),
      dataCoverage: _asDouble(map['data_coverage']) ?? 0,
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
