class SleepSummary {
  final DateTime recordingStart;
  final DateTime recordingEnd;
  final DateTime? estimatedSleepOnset;
  final DateTime? estimatedWake;
  final double timeInBedMinutes;
  final double estimatedTotalSleepMinutes;
  final double estimatedWasoMinutes;
  final double estimatedSleepEfficiency;
  final int estimatedAwakenings;
  final double? overnightMeanHeartRate;
  final double? overnightMovementStdG;
  final double confidence;
  final int validEpochs;
  final int totalEpochs;

  const SleepSummary({
    required this.recordingStart,
    required this.recordingEnd,
    required this.estimatedSleepOnset,
    required this.estimatedWake,
    required this.timeInBedMinutes,
    required this.estimatedTotalSleepMinutes,
    required this.estimatedWasoMinutes,
    required this.estimatedSleepEfficiency,
    required this.estimatedAwakenings,
    required this.overnightMeanHeartRate,
    required this.overnightMovementStdG,
    required this.confidence,
    required this.validEpochs,
    required this.totalEpochs,
  });

  Map<String, Object?> toFirestore() => <String, Object?>{
        'recording_start_ms': recordingStart.millisecondsSinceEpoch,
        'recording_end_ms': recordingEnd.millisecondsSinceEpoch,
        'predicted_sleep_onset_ms': estimatedSleepOnset?.millisecondsSinceEpoch,
        'predicted_wake_ms': estimatedWake?.millisecondsSinceEpoch,
        'estimated_time_in_bed_minutes': timeInBedMinutes,
        'estimated_total_sleep_minutes': estimatedTotalSleepMinutes,
        'estimated_waso_minutes': estimatedWasoMinutes,
        'estimated_sleep_efficiency': estimatedSleepEfficiency,
        'estimated_awakenings': estimatedAwakenings,
        'overnight_mean_hr': overnightMeanHeartRate,
        'overnight_movement_std_g': overnightMovementStdG,
        'sleep_estimate_confidence': confidence,
        'valid_epoch_count': validEpochs,
        'total_epoch_count': totalEpochs,
        'sleep_estimator_version': 'rules-v1',
      };

  factory SleepSummary.fromMap(Map<String, dynamic> map) {
    final startMs = _asInt(map['recording_start_ms']) ?? 0;
    final endMs = _asInt(map['recording_end_ms']) ?? startMs;
    return SleepSummary(
      recordingStart:
          DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true),
      recordingEnd: DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true),
      estimatedSleepOnset: _date(map['predicted_sleep_onset_ms']),
      estimatedWake: _date(map['predicted_wake_ms']),
      timeInBedMinutes: _asDouble(map['estimated_time_in_bed_minutes']) ?? 0,
      estimatedTotalSleepMinutes:
          _asDouble(map['estimated_total_sleep_minutes']) ?? 0,
      estimatedWasoMinutes: _asDouble(map['estimated_waso_minutes']) ?? 0,
      estimatedSleepEfficiency:
          _asDouble(map['estimated_sleep_efficiency']) ?? 0,
      estimatedAwakenings: _asInt(map['estimated_awakenings']) ?? 0,
      overnightMeanHeartRate: _asDouble(map['overnight_mean_hr']),
      overnightMovementStdG: _asDouble(map['overnight_movement_std_g']),
      confidence: _asDouble(map['sleep_estimate_confidence']) ?? 0,
      validEpochs: _asInt(map['valid_epoch_count']) ?? 0,
      totalEpochs: _asInt(map['total_epoch_count']) ?? 0,
    );
  }

  static DateTime? _date(dynamic value) {
    final ms = _asInt(value);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
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

class SleepSessionRecord {
  final String id;
  final String participantId;
  final String status;
  final DateTime recordingStart;
  final DateTime? recordingEnd;
  final DateTime? reportedSleepOnset;
  final DateTime? reportedWake;
  final int? sleepQuality;
  final int? restedScore;
  final int? reportedAwakenings;
  final bool? watchRemoved;
  final SleepSummary? summary;

  const SleepSessionRecord({
    required this.id,
    required this.participantId,
    required this.status,
    required this.recordingStart,
    required this.recordingEnd,
    required this.reportedSleepOnset,
    required this.reportedWake,
    required this.sleepQuality,
    required this.restedScore,
    required this.reportedAwakenings,
    required this.watchRemoved,
    required this.summary,
  });

  bool get isRecording => status == 'recording';
  bool get needsConfirmation => status == 'awaiting_confirmation';

  factory SleepSessionRecord.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    return SleepSessionRecord(
      id: id,
      participantId: map['participant_id']?.toString() ?? '',
      status: map['status']?.toString() ?? 'unknown',
      recordingStart: _date(map['recording_start_ms']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      recordingEnd: _date(map['recording_end_ms']),
      reportedSleepOnset: _date(map['reported_sleep_onset_ms']),
      reportedWake: _date(map['reported_wake_ms']),
      sleepQuality: _asInt(map['sleep_quality']),
      restedScore: _asInt(map['rested_score']),
      reportedAwakenings: _asInt(map['reported_awakenings']),
      watchRemoved: map['watch_removed'] is bool
          ? map['watch_removed'] as bool
          : null,
      summary: map.containsKey('estimated_total_sleep_minutes')
          ? SleepSummary.fromMap(map)
          : null,
    );
  }

  static DateTime? _date(dynamic value) {
    final ms = _asInt(value);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
