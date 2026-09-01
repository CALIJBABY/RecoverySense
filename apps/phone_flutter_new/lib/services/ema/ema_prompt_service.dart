import 'dart:async';
import 'dart:math';

import '../../models/ema_prompt.dart';

/// App-active EMA prompt scheduler.
///
/// The v0.5 research schedule uses at most one randomized prompt in each of
/// three broad local-time strata (morning, afternoon, evening) while this app
/// process remains alive. This improves time-of-day coverage without the former
/// high-frequency interval schedule. It is still an app-process timer, not a
/// guaranteed background notification scheduler, and the in-memory delivered
/// stratum state resets if the process restarts.
class EmaPromptService {
  EmaPromptService._();

  static final EmaPromptService instance = EmaPromptService._();

  static const _windows = <(int, int)>[
    (9, 12),
    (13, 17),
    (18, 22),
  ];

  final StreamController<EmaPrompt> _controller =
      StreamController<EmaPrompt>.broadcast();
  final Random _random = Random();
  Timer? _timer;

  bool randomPromptsEnabled = false;
  DateTime? nextPromptAt;
  int? _lastDeliveredDayKey;
  int? _lastDeliveredWindowIndex;

  Stream<EmaPrompt> get promptStream => _controller.stream;

  /// Start the study check-in schedule once the signed-in participant reaches
  /// the dashboard. Repeated calls are safe.
  void ensureStudyScheduleStarted() {
    if (randomPromptsEnabled && _timer != null) return;
    randomPromptsEnabled = true;
    _timer?.cancel();
    _timer = null;
    nextPromptAt = null;
    _scheduleNextStratifiedPrompt();
  }

  void setRandomPromptsEnabled(bool enabled) {
    randomPromptsEnabled = enabled;
    _timer?.cancel();
    _timer = null;
    nextPromptAt = null;
    if (enabled) _scheduleNextStratifiedPrompt();
  }

  void triggerTestPrompt() {
    _controller.add(
      EmaPrompt(
        source: 'scheduled_test',
        promptedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        triggerReason: 'User requested a test EMA prompt from settings.',
      ),
    );
  }

  void emitModelPrompt({
    required double probability,
    required String modelVersion,
    required double threshold,
    required int windowStartMs,
    required int windowEndMs,
  }) {
    _controller.add(
      EmaPrompt(
        source: 'model',
        promptedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        triggerProbability: probability,
        modelVersion: modelVersion,
        modelThreshold: threshold,
        windowStartMs: windowStartMs,
        windowEndMs: windowEndMs,
        triggerReason: 'On-device craving probability exceeded threshold.',
      ),
    );
  }

  void _scheduleNextStratifiedPrompt() {
    if (!randomPromptsEnabled) return;
    final now = DateTime.now();
    final target = _nextTarget(now);
    nextPromptAt = target.$1;
    final delay = target.$1.difference(now);
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!randomPromptsEnabled) return;
      final firedAt = DateTime.now();
      _lastDeliveredDayKey = _dayKey(firedAt);
      _lastDeliveredWindowIndex = target.$2;
      _controller.add(
        EmaPrompt(
          source: 'scheduled_stratified',
          promptedAtMs: firedAt.toUtc().millisecondsSinceEpoch,
          triggerReason: 'Randomized time-stratified research EMA prompt.',
        ),
      );
      _scheduleNextStratifiedPrompt();
    });
  }

  (DateTime, int) _nextTarget(DateTime now) {
    // Broad local-time strata; randomized within each window. These are study
    // engineering windows, not clinical risk thresholds.
    final todayKey = _dayKey(now);
    final deliveredIndex = _lastDeliveredDayKey == todayKey
        ? _lastDeliveredWindowIndex
        : null;

    for (var index = 0; index < _windows.length; index++) {
      if (deliveredIndex != null && index <= deliveredIndex) continue;
      final (startHour, endHour) = _windows[index];
      final start = DateTime(now.year, now.month, now.day, startHour);
      final end = DateTime(now.year, now.month, now.day, endHour);
      if (now.isBefore(end)) {
        final earliest = now.isAfter(start)
            ? now.add(const Duration(minutes: 10))
            : start;
        if (earliest.isBefore(end)) {
          return (_randomBetween(earliest, end), index);
        }
      }
    }

    final tomorrow = now.add(const Duration(days: 1));
    final start = DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      _windows.first.$1,
    );
    final end = DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      _windows.first.$2,
    );
    return (_randomBetween(start, end), 0);
  }

  static int _dayKey(DateTime value) =>
      value.year * 10000 + value.month * 100 + value.day;

  DateTime _randomBetween(DateTime start, DateTime end) {
    final range = end.difference(start).inMinutes;
    if (range <= 1) return start;
    return start.add(Duration(minutes: _random.nextInt(range)));
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _controller.close();
  }
}
