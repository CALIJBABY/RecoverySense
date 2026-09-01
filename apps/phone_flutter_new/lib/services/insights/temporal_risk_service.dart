import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/temporal_risk_summary.dart';

class TemporalRiskService {
  TemporalRiskService._();

  static const int minimumEligibleEvents = 30;
  static const int minimumEventsPerWindow = 5;
  static const int elevatedCravingThreshold = 7;
  static const int windowHours = 2;

  /// Sources chosen independently of an observed/model-predicted high-risk state.
  /// Model-triggered and self-initiated/manual prompts are excluded from the
  /// primary time-of-day estimate to reduce ascertainment bias.
  static const Set<String> _eligibleSources = <String>{
    'random',
    'scheduled',
    'scheduled_stratified',
    'watch_scheduled',
  };

  static TemporalRiskSummary summarize(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> documents, {
    List<String> selfReportedTimeBlocks = const <String>[],
  }) {
    final buckets = <int, List<int>>{};
    var total = 0;
    var eligible = 0;

    for (final document in documents) {
      final data = document.data();
      final score = (data['craving_score'] as num?)?.toInt();
      if (score == null || score < 0 || score > 10) continue;
      total += 1;

      final source = data['source']?.toString() ?? '';
      if (!_eligibleSources.contains(source)) continue;

      // v0.5+ records the local minute at the moment the EMA was submitted.
      // Using this field avoids reinterpreting UTC timestamps in a later
      // timezone or after daylight-saving changes.
      final localMinute = (data['local_minute_of_day'] as num?)?.toInt();
      if (localMinute == null || localMinute < 0 || localMinute >= 1440) continue;

      eligible += 1;
      final hour = localMinute ~/ 60;
      final bucketStart = (hour ~/ windowHours) * windowHours;
      buckets.putIfAbsent(bucketStart, () => <int>[]).add(score);
    }

    final windows = <TemporalRiskWindow>[];
    for (final entry in buckets.entries) {
      if (entry.value.length < minimumEventsPerWindow) continue;
      final mean = entry.value.reduce((a, b) => a + b) / entry.value.length;
      final elevated = entry.value.where((score) => score >= elevatedCravingThreshold).length /
          entry.value.length;
      windows.add(
        TemporalRiskWindow(
          startHour: entry.key,
          endHour: entry.key + windowHours,
          meanCraving: mean,
          elevatedFraction: elevated,
          observationCount: entry.value.length,
        ),
      );
    }

    windows.sort((a, b) {
      final meanComparison = b.meanCraving.compareTo(a.meanCraving);
      if (meanComparison != 0) return meanComparison;
      return b.elevatedFraction.compareTo(a.elevatedFraction);
    });

    final sufficient = eligible >= minimumEligibleEvents && windows.isNotEmpty;
    return TemporalRiskSummary(
      totalEvents: total,
      eligibleEvents: eligible,
      sufficientData: sufficient,
      topWindows: sufficient ? windows.take(3).toList(growable: false) : const <TemporalRiskWindow>[],
      selfReportedTimeBlocks: selfReportedTimeBlocks,
    );
  }
}
