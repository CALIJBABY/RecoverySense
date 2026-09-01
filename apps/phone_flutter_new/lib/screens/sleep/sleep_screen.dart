import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/sleep_epoch.dart';
import '../../models/sleep_session.dart';
import '../../services/sleep/sleep_session_service.dart';
import '../../widgets/app_bottom_navigation.dart';
import '../../widgets/block_score_bar.dart';
import '../../widgets/section_card.dart';

class SleepScreen extends StatefulWidget {
  const SleepScreen({super.key});

  @override
  State<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends State<SleepScreen> {
  String? _editingSessionId;
  DateTime? _reportedOnset;
  DateTime? _reportedWake;
  double _sleepQuality = 3;
  double _restedScore = 3;
  int _awakenings = 0;
  bool _sleepQualityAnswered = false;
  bool _restedScoreAnswered = false;
  bool _awakeningsAnswered = false;
  bool? _watchRemoved;

  @override
  Widget build(BuildContext context) {
    final service = SleepSessionService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Sleep')),
      bottomNavigationBar: const AppBottomNavigation(currentIndex: 3),
      body: ValueListenableBuilder<SleepTrackingState>(
        valueListenable: service.state,
        builder: (context, state, _) {
          _syncConfirmationFields(state.currentSession);
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              _qualityOverviewCard(state.latestConfirmedSession),
              if (state.isRecording) _recordingCard(state),
              if (state.epochs.isNotEmpty) _timelineCard(state.epochs),
              if (state.needsConfirmation) _confirmationCard(state),
              if (state.currentSession == null) _startCard(state),
              if (state.error != null)
                const SectionCard(
                  title: 'Sleep Tracking',
                  child: Text(
                    'Sleep tracking is temporarily unavailable. Check the watch connection and try again.',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _qualityOverviewCard(SleepSessionRecord? session) {
    final summary = session?.summary;
    final efficiency = summary == null
        ? null
        : summary.estimatedSleepEfficiency.clamp(0.0, 1.0).toDouble();
    final percent = efficiency == null ? null : (efficiency * 100).round();

    return SectionCard(
      title: 'Sleep Quality',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  percent == null ? 'No score yet' : '$percent% efficiency',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (session?.sleepQuality != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.softGreen,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'You: ${session!.sleepQuality}/5',
                    style: const TextStyle(
                      color: AppTheme.primaryGreenDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          BlockScoreBar(value: efficiency),
          const SizedBox(height: 10),
          Text(
            summary == null
                ? 'Record and confirm a night to fill this bar.'
                : 'Filled from the watch-based sleep-efficiency estimate.',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
            ),
          ),
          if (summary != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _sleepStat(
                    'Duration',
                    '${(summary.estimatedTotalSleepMinutes / 60).toStringAsFixed(1)} h',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _sleepStat(
                    'Awakenings',
                    '${summary.estimatedAwakenings}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _sleepStat(
                    'Confidence',
                    '${(summary.confidence * 100).round()}%',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Sleep/wake estimate only — not medical sleep staging.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _sleepStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.softGreen.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _startCard(SleepTrackingState state) {
    return SectionCard(
      title: 'Overnight Recording',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Wear the watch snugly and start when you are ready.'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: state.busy ? null : _startRecording,
            child: Text(state.busy ? 'Starting...' : 'Start recording'),
          ),
        ],
      ),
    );
  }

  Widget _recordingCard(SleepTrackingState state) {
    final session = state.currentSession!;
    return SectionCard(
      title: 'Recording Active',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Started: ${_formatDateTime(session.recordingStart.toLocal())}'),
          const SizedBox(height: 8),
          const Text('Keep the watch on through the night.'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: state.busy ? null : _stopRecording,
            child: Text(state.busy ? 'Finishing...' : 'End recording'),
          ),
        ],
      ),
    );
  }


  Widget _timelineCard(List<SleepEpochEstimate> epochs) {
    final ordered = [...epochs]..sort((a, b) => a.start.compareTo(b.start));
    const maximumSegments = 120;
    final stride = ordered.length <= maximumSegments
        ? 1
        : (ordered.length / maximumSegments).ceil();
    final displayed = <SleepEpochEstimate>[];
    for (var index = 0; index < ordered.length; index += stride) {
      final chunk = ordered.sublist(
        index,
        index + stride < ordered.length ? index + stride : ordered.length,
      );
      displayed.add(
        chunk.reduce(
          (left, right) => left.sleepProbability >= right.sleepProbability
              ? left
              : right,
        ),
      );
    }

    return SectionCard(
      title: 'Sleep/Wake Timeline',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Darker blocks mean a higher sleep estimate.'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth / displayed.length;
              return Row(
                children: displayed.map((epoch) {
                  final valid = epoch.isSleep != null;
                  final intensity = epoch.sleepProbability.clamp(0.0, 1.0).toDouble();
                  final base = Theme.of(context).colorScheme.primary;
                  return Container(
                    width: width,
                    height: 32,
                    decoration: BoxDecoration(
                      color: valid
                          ? base.withValues(alpha: 0.15 + intensity * 0.75)
                          : Colors.transparent,
                      border: valid
                          ? null
                          : Border.all(
                              color: Theme.of(context).colorScheme.outline,
                              width: 0.7,
                            ),
                    ),
                  );
                }).toList(growable: false),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDateTime(ordered.first.start.toLocal())),
              Text(_formatDateTime(ordered.last.end.toLocal())),
            ],
          ),
        ],
      ),
    );
  }

  Widget _confirmationCard(SleepTrackingState state) {
    final session = state.currentSession!;
    final summary = session.summary;
    return Column(
      children: [
        if (summary != null) _summaryCard(summary, title: 'Estimated Sleep'),
        SectionCard(
          title: 'Morning Confirmation',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Review the estimate and add your morning rating.'),
              const SizedBox(height: 12),
              _dateTimeButton(
                label: 'Sleep onset',
                value: _reportedOnset,
                onChanged: (value) => setState(() => _reportedOnset = value),
              ),
              const SizedBox(height: 8),
              _dateTimeButton(
                label: 'Final wake time',
                value: _reportedWake,
                onChanged: (value) => setState(() => _reportedWake = value),
              ),
              const SizedBox(height: 12),
              Text(
                _sleepQualityAnswered
                    ? 'Sleep quality: ${_sleepQuality.round()} / 5'
                    : 'Sleep quality: select a rating',
              ),
              Slider(
                value: _sleepQuality,
                min: 1,
                max: 5,
                divisions: 4,
                label: _sleepQuality.round().toString(),
                onChangeStart: (_) => setState(() => _sleepQualityAnswered = true),
                onChanged: (value) => setState(() {
                  _sleepQuality = value;
                  _sleepQualityAnswered = true;
                }),
              ),
              Text(
                _restedScoreAnswered
                    ? 'How rested: ${_restedScore.round()} / 5'
                    : 'How rested: select a rating',
              ),
              Slider(
                value: _restedScore,
                min: 1,
                max: 5,
                divisions: 4,
                label: _restedScore.round().toString(),
                onChangeStart: (_) => setState(() => _restedScoreAnswered = true),
                onChanged: (value) => setState(() {
                  _restedScore = value;
                  _restedScoreAnswered = true;
                }),
              ),
              DropdownButtonFormField<int>(
                initialValue: _awakeningsAnswered ? _awakenings.clamp(0, 10).toInt() : null,
                decoration: const InputDecoration(
                  labelText: 'Remembered awakenings',
                  hintText: 'Select',
                ),
                items: List<DropdownMenuItem<int>>.generate(
                  11,
                  (index) => DropdownMenuItem<int>(
                    value: index,
                    child: Text(index == 10 ? '10+' : index.toString()),
                  ),
                ),
                onChanged: (value) => setState(() {
                  if (value == null) return;
                  _awakenings = value;
                  _awakeningsAnswered = true;
                }),
              ),
              const SizedBox(height: 12),
              const Text(
                'Was the watch removed during the night?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(value: false, label: Text('No')),
                  ButtonSegment<bool>(value: true, label: Text('Yes')),
                ],
                selected: _watchRemoved == null ? <bool>{} : <bool>{_watchRemoved!},
                emptySelectionAllowed: true,
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) return;
                  setState(() => _watchRemoved = selection.first);
                },
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: state.busy ? null : _confirmSession,
                child: Text(
                  state.busy ? 'Saving...' : 'Save sleep record',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(SleepSummary summary, {required String title}) {
    final efficiency =
        summary.estimatedSleepEfficiency.clamp(0.0, 1.0).toDouble();
    return SectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BlockScoreBar(value: efficiency),
          const SizedBox(height: 12),
          _summaryLine(
            'Estimated sleep',
            '${(summary.estimatedTotalSleepMinutes / 60).toStringAsFixed(1)} hours',
          ),
          _summaryLine(
            'Efficiency',
            '${(efficiency * 100).round()}%',
          ),
          _summaryLine(
            'Awakenings',
            '${summary.estimatedAwakenings}',
          ),
          _summaryLine(
            'Wake after sleep onset',
            '${summary.estimatedWasoMinutes.toStringAsFixed(0)} min',
          ),
          if (summary.estimatedSleepOnset != null)
            _summaryLine(
              'Estimated onset',
              _formatDateTime(summary.estimatedSleepOnset!.toLocal()),
            ),
          if (summary.estimatedWake != null)
            _summaryLine(
              'Estimated wake',
              _formatDateTime(summary.estimatedWake!.toLocal()),
            ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textMuted),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _dateTimeButton({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime> onChanged,
  }) {
    return OutlinedButton(
      onPressed: () async {
        final selected = await _pickDateTime(value ?? DateTime.now());
        if (selected != null) onChanged(selected.toUtc());
      },
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$label: ${value == null ? 'not set' : _formatDateTime(value.toLocal())}',
        ),
      ),
    );
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final local = initial.toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: local,
      firstDate: local.subtract(const Duration(days: 2)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(local),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _startRecording() async {
    try {
      await SleepSessionService.instance.startRecording();
    } catch (error, stackTrace) {
      debugPrint('Sleep recording start failed: $error\n$stackTrace');
      if (!mounted) return;
      _showSleepError();
    }
  }

  Future<void> _stopRecording() async {
    try {
      await SleepSessionService.instance.stopRecording();
    } catch (error, stackTrace) {
      debugPrint('Sleep recording stop failed: $error\n$stackTrace');
      if (!mounted) return;
      _showSleepError();
    }
  }

  Future<void> _confirmSession() async {
    final onset = _reportedOnset;
    final wake = _reportedWake;
    if (onset == null || wake == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set both sleep onset and wake time.')),
      );
      return;
    }
    if (!wake.isAfter(onset)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wake time must be after sleep onset.')),
      );
      return;
    }
    if (!_sleepQualityAnswered ||
        !_restedScoreAnswered ||
        !_awakeningsAnswered ||
        _watchRemoved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please answer each morning confirmation item before saving.'),
        ),
      );
      return;
    }
    try {
      await SleepSessionService.instance.confirmSession(
        reportedSleepOnset: onset,
        reportedWake: wake,
        sleepQuality: _sleepQuality.round(),
        restedScore: _restedScore.round(),
        reportedAwakenings: _awakenings,
        watchRemoved: _watchRemoved!,
      );
    } catch (error, stackTrace) {
      debugPrint('Sleep confirmation save failed: $error\n$stackTrace');
      if (!mounted) return;
      _showSleepError();
    }
  }

  void _showSleepError() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('We could not update sleep tracking. Check the watch connection and try again.'),
        ),
      );
  }

  void _syncConfirmationFields(SleepSessionRecord? session) {
    if (session == null || !session.needsConfirmation) {
      _editingSessionId = null;
      return;
    }
    if (_editingSessionId == session.id) return;
    _editingSessionId = session.id;
    _reportedOnset = session.reportedSleepOnset ??
        session.summary?.estimatedSleepOnset ??
        session.recordingStart;
    _reportedWake = session.reportedWake ??
        session.summary?.estimatedWake ??
        session.recordingEnd ??
        DateTime.now().toUtc();
    _sleepQuality = (session.sleepQuality ?? 3).toDouble();
    _restedScore = (session.restedScore ?? 3).toDouble();
    _awakenings = session.reportedAwakenings ?? 0;
    _sleepQualityAnswered = session.sleepQuality != null;
    _restedScoreAnswered = session.restedScore != null;
    _awakeningsAnswered = session.reportedAwakenings != null;
    _watchRemoved = session.watchRemoved;
  }

  static String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }
}
