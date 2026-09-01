class TemporalRiskWindow {
  const TemporalRiskWindow({
    required this.startHour,
    required this.endHour,
    required this.meanCraving,
    required this.elevatedFraction,
    required this.observationCount,
  });

  final int startHour;
  final int endHour;
  final double meanCraving;
  final double elevatedFraction;
  final int observationCount;

  String get label => '${_formatHour(startHour)}–${_formatHour(endHour % 24)}';

  static String _formatHour(int hour) {
    final normalized = hour % 24;
    if (normalized == 0) return '12 AM';
    if (normalized < 12) return '$normalized AM';
    if (normalized == 12) return '12 PM';
    return '${normalized - 12} PM';
  }
}

class TemporalRiskSummary {
  const TemporalRiskSummary({
    required this.totalEvents,
    required this.eligibleEvents,
    required this.sufficientData,
    required this.topWindows,
    this.selfReportedTimeBlocks = const <String>[],
  });

  final int totalEvents;
  final int eligibleEvents;
  final bool sufficientData;
  final List<TemporalRiskWindow> topWindows;
  final List<String> selfReportedTimeBlocks;
}
