import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ema_prompt.dart';
import '../../models/risk_prediction.dart';
import '../../models/temporal_risk_summary.dart';
import '../../services/ema/ema_prompt_service.dart';
import '../../services/firebase/baseline_assessment_repository.dart';
import '../../services/firebase/participant_insights_repository.dart';
import '../../services/insights/temporal_risk_service.dart';
import '../../widgets/app_bottom_navigation.dart';
import '../../widgets/craving_gauge.dart';
import '../../widgets/ema_primary_button.dart';
import '../../widgets/section_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _insights = ParticipantInsightsRepository();
  final _baseline = BaselineAssessmentRepository();
  late final Stream<LatestEmaRating?> _latestEmaStream;
  late final Stream<RiskPrediction?> _riskPredictionStream;
  late final Stream<Map<String, dynamic>?> _baselineStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _emaHistoryStream;
  StreamSubscription<EmaPrompt>? _promptSubscription;

  @override
  void initState() {
    super.initState();
    _latestEmaStream = _insights.latestEmaStream();
    _riskPredictionStream = _insights.latestRiskPredictionStream();
    _baselineStream = _baseline.watchCurrentAssessment();
    _emaHistoryStream = _insights.emaHistoryStream();
    EmaPromptService.instance.ensureStudyScheduleStarted();
    _promptSubscription = EmaPromptService.instance.promptStream.listen(
      (prompt) {
        if (!mounted) return;
        Navigator.pushNamed(context, AppRoutes.ema, arguments: prompt);
      },
    );
  }

  @override
  void dispose() {
    _promptSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RecoverySense'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNavigation(currentIndex: 0),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          _cravingRiskCard(),
          _higherRiskTimesCard(),
        ],
      ),
    );
  }

  Widget _cravingRiskCard() {
    return SectionCard(
      title: 'Craving Risk Now',
      child: StreamBuilder<RiskPrediction?>(
        stream: _riskPredictionStream,
        builder: (context, snapshot) {
          final prediction = snapshot.data;
          final usable = prediction != null &&
              prediction.displayEligible &&
              DateTime.now().difference(prediction.timestamp).abs() <=
                  const Duration(minutes: 90);
          final currentPrediction = usable ? prediction! : null;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CravingGauge(
                probability: currentPrediction?.probability,
                timestamp: currentPrediction?.timestamp,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Top patterns',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (currentPrediction != null) ...[
                    Tooltip(
                      message: currentPrediction.selectedModelIsInterpretabilityModel
                          ? 'Ranked from the selected decision tree.'
                          : 'Ranked from a companion decision tree trained on the same features; these are not exact ${_modelLabel(currentPrediction.modelName)} weights.',
                      child: const Padding(
                        padding: EdgeInsets.only(right: 7),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.softGreen,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        _modelLabel(currentPrediction.modelName),
                        style: const TextStyle(
                          color: AppTheme.primaryGreenDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              _factorBoxes(currentPrediction),
              const SizedBox(height: 12),
              Text(
                currentPrediction != null
                    ? 'These boxes refresh with every new approved prediction.'
                    : 'Wear the watch and complete check-ins while the model learns.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.softGreen.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.sensors_rounded,
                      size: 19,
                      color: AppTheme.primaryGreenDark,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'This score uses recent watch data and available context. Check-ins train and validate the model; the latest rating is not copied here.',
                        style: TextStyle(fontSize: 12, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              EmaPrimaryButton(
                label: 'Check in now',
                onPressed: () => Navigator.pushNamed(context, AppRoutes.ema),
              ),
              const SizedBox(height: 9),
              _latestCheckInLine(),
            ],
          );
        },
      ),
    );
  }

  Widget _factorBoxes(RiskPrediction? prediction) {
    final contributors = prediction?.topContributors ?? const <RiskContributor>[];
    return Row(
      children: List<Widget>.generate(3, (index) {
        final contributor =
            index < contributors.length ? contributors[index] : null;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == 2 ? 0 : 8),
            child: _factorBox(index + 1, contributor),
          ),
        );
      }),
    );
  }

  Widget _factorBox(int rank, RiskContributor? contributor) {
    final icon = contributor == null
        ? Icons.hourglass_top_rounded
        : _featureIcon(contributor.feature);
    return Container(
      height: 138,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
      decoration: BoxDecoration(
        color: contributor == null
            ? AppTheme.softGreen.withValues(alpha: 0.45)
            : AppTheme.softGreen,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 25,
                height: 25,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(icon, size: 20, color: AppTheme.primaryGreenDark),
            ],
          ),
          const Spacer(),
          Text(
            contributor?.displayName ?? 'Still learning',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              height: 1.15,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (contributor != null) ...[
            const SizedBox(height: 4),
            Text(
              '+${(contributor.contribution * 100).round()} pts',
              style: const TextStyle(
                color: AppTheme.primaryGreenDark,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _latestCheckInLine() {
    return StreamBuilder<LatestEmaRating?>(
      stream: _latestEmaStream,
      builder: (context, snapshot) {
        final rating = snapshot.data;
        final text = rating == null
            ? 'No craving check-in recorded yet.'
            : 'Last check-in: ${rating.score}/10 · ${_relativeTime(rating.timestamp)}';
        return Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
        );
      },
    );
  }

  Widget _higherRiskTimesCard() {
    return SectionCard(
      title: 'Higher-Risk Times',
      child: StreamBuilder<Map<String, dynamic>?>(
        stream: _baselineStream,
        builder: (context, baselineSnapshot) {
          final baselineData = baselineSnapshot.data;
          final selfReported =
              (baselineData?['self_reported_high_risk_time_blocks'] as Iterable?)
                      ?.map((item) => item.toString())
                      .toList(growable: false) ??
                  const <String>[];

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _emaHistoryStream,
            builder: (context, emaSnapshot) {
              final summary = TemporalRiskService.summarize(
                emaSnapshot.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                selfReportedTimeBlocks: selfReported,
              );
              return _temporalRiskBody(summary);
            },
          );
        },
      ),
    );
  }

  Widget _temporalRiskBody(TemporalRiskSummary summary) {
    if (!summary.sufficientData) {
      final selfReportedLabels = summary.selfReportedTimeBlocks
          .where((value) => value != 'unsure')
          .map(_baselineTimeLabel)
          .toList(growable: false);
      final progress =
          (summary.eligibleEvents / TemporalRiskService.minimumEligibleEvents)
              .clamp(0.0, 1.0)
              .toDouble();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: AppTheme.primaryGreenDark,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${summary.eligibleEvents}/${TemporalRiskService.minimumEligibleEvents} timed check-ins',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress,
            minHeight: 9,
            borderRadius: BorderRadius.circular(99),
            backgroundColor: AppTheme.softGreen,
            color: AppTheme.primaryGreen,
          ),
          if (selfReportedLabels.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: selfReportedLabels
                  .map(
                    (label) => Chip(
                      label: Text(label),
                      backgroundColor: AppTheme.softGreen,
                      side: BorderSide.none,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'This section uses scheduled and random check-ins only.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      );
    }

    return Column(
      children: [
        for (var index = 0; index < summary.topWindows.length; index++) ...[
          _timeWindowRow(index + 1, summary.topWindows[index]),
          if (index < summary.topWindows.length - 1)
            const Divider(height: 20),
        ],
        const SizedBox(height: 10),
        Text(
          '${summary.eligibleEvents} independently timed check-ins',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _timeWindowRow(int rank, TemporalRiskWindow window) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppTheme.softGreen,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$rank',
            style: const TextStyle(
              color: AppTheme.primaryGreenDark,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                window.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Average ${window.meanCraving.toStringAsFixed(1)}/10 · ${window.observationCount} check-ins',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Text(
          '${(window.elevatedFraction * 100).round()}%',
          style: const TextStyle(
            color: AppTheme.primaryGreenDark,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  static IconData _featureIcon(String feature) {
    final value = feature.toLowerCase();
    if (value.contains('heart') || value.contains('hr_')) {
      return Icons.favorite_rounded;
    }
    if (value.contains('sleep')) return Icons.bedtime_rounded;
    if (value.contains('step') || value.contains('activity')) {
      return Icons.directions_walk_rounded;
    }
    if (value.contains('accel') ||
        value.contains('gyro') ||
        value.contains('motion')) {
      return Icons.motion_photos_on_rounded;
    }
    if (value.contains('time') || value.contains('day_of_week')) {
      return Icons.schedule_rounded;
    }
    if (value.contains('ema') || value.contains('craving')) {
      return Icons.insights_rounded;
    }
    return Icons.auto_graph_rounded;
  }

  static String _modelLabel(String modelName) => switch (modelName) {
        'random_forest' => 'Random forest',
        'decision_tree' => 'Decision tree',
        'gradient_boosting' => 'Boosting',
        'logistic_regression' => 'Logistic model',
        'support_vector_machine' => 'SVM',
        _ => modelName.replaceAll('_', ' '),
      };

  static String _relativeTime(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.isNegative || difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} h ago';
    return '${difference.inDays} d ago';
  }

  static String _baselineTimeLabel(String value) => switch (value) {
        'overnight_00_06' => '12 AM–6 AM',
        'morning_06_12' => '6 AM–12 PM',
        'afternoon_12_18' => '12 PM–6 PM',
        'evening_18_24' => '6 PM–12 AM',
        _ => value.replaceAll('_', ' '),
      };
}
