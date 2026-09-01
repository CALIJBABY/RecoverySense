import 'package:flutter/material.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/baseline_assessment.dart';
import '../../services/firebase/baseline_assessment_repository.dart';
import '../../widgets/ema_primary_button.dart';

class BaselineAssessmentScreen extends StatefulWidget {
  const BaselineAssessmentScreen({super.key});

  @override
  State<BaselineAssessmentScreen> createState() => _BaselineAssessmentScreenState();
}

class _BaselineAssessmentScreenState extends State<BaselineAssessmentScreen> {
  final _repository = BaselineAssessmentRepository();
  final _pageController = PageController();

  int _page = 0;
  bool _saving = false;
  String? _targetBehavior;
  String? _goal;
  double _daysEngagedPast30 = 0;
  double _typicalCraving = 5;
  double _typicalEpisodeMinutes = 30;
  bool _daysEngagedAnswered = false;
  bool _typicalCravingAnswered = false;
  bool _episodeDurationAnswered = false;
  final Set<String> _riskTimes = <String>{};
  final Set<String> _riskDays = <String>{};
  final Set<String> _triggers = <String>{};
  final Set<String> _motives = <String>{};
  String? _scheduleRegularity;
  TimeOfDay _bedtime = const TimeOfDay(hour: 23, minute: 0);
  TimeOfDay _wakeTime = const TimeOfDay(hour: 7, minute: 0);
  bool _bedtimeConfirmed = false;
  bool _wakeTimeConfirmed = false;
  String? _activityLevel;
  double _confidenceToResist = 5;
  double _typicalStress = 5;
  bool _confidenceAnswered = false;
  bool _stressAnswered = false;

  static const _behaviors = <String, String>{
    'gambling': 'Gambling / betting',
    'gaming': 'Gaming',
    'shopping': 'Shopping / spending',
    'social_media': 'Social media / phone use',
    'sexual_behavior': 'Sexual / pornography-related behavior',
    'other': 'Other behavioral urge',
  };

  static const _goals = <String, String>{
    'abstinence': 'Avoid the behavior',
    'reduction': 'Reduce the behavior',
    'awareness': 'Understand my patterns',
    'unsure': 'Still deciding',
  };

  static const _timeBlocks = <String, String>{
    'overnight_00_06': '12 AM–6 AM',
    'morning_06_12': '6 AM–12 PM',
    'afternoon_12_18': '12 PM–6 PM',
    'evening_18_24': '6 PM–12 AM',
    'unsure': 'Not sure yet',
  };

  static const _days = <String, String>{
    'monday': 'Mon',
    'tuesday': 'Tue',
    'wednesday': 'Wed',
    'thursday': 'Thu',
    'friday': 'Fri',
    'saturday': 'Sat',
    'sunday': 'Sun',
    'no_pattern': 'No clear pattern',
  };

  static const _triggerOptions = <String, String>{
    'stress': 'Stress / tension',
    'boredom': 'Boredom',
    'negative_mood': 'Low or negative mood',
    'positive_excitement': 'Excitement / celebration',
    'social_cues': 'Social situations',
    'digital_cues': 'Notifications / ads / online cues',
    'money_cues': 'Money / financial cues',
    'being_alone': 'Being alone',
    'fatigue': 'Fatigue / poor sleep',
    'location_routine': 'A place or routine',
    'unsure': 'Not sure yet',
  };

  static const _motiveOptions = <String, String>{
    'coping_escape': 'Coping / escape',
    'enhancement_excitement': 'Excitement / reward',
    'social': 'Social reasons',
    'financial': 'Financial gain',
    'habit_automatic': 'Habit / automatic pull',
    'boredom_relief': 'Relieve boredom',
    'unsure': 'Not sure yet',
  };

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    final error = _validationMessageForPage(_page);
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (_page == 4) {
      await _submit();
      return;
    }
    setState(() => _page += 1);
    await _pageController.animateToPage(
      _page,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _back() async {
    if (_page == 0 || _saving) return;
    setState(() => _page -= 1);
    await _pageController.animateToPage(
      _page,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  String? _validationMessageForPage(int page) {
    if (page == 0 && (_targetBehavior == null || _goal == null)) {
      return 'Choose the behavior you want to track and your current goal.';
    }
    if (page == 0 &&
        (!_daysEngagedAnswered || !_typicalCravingAnswered || !_episodeDurationAnswered)) {
      return 'Please answer each baseline rating on this page before continuing.';
    }
    if (page == 1 && (_riskTimes.isEmpty || _riskDays.isEmpty)) {
      return 'Choose at least one time period and one day pattern, or select “not sure.”';
    }
    if (page == 2 && (_triggers.isEmpty || _motives.isEmpty)) {
      return 'Choose at least one trigger and one motive, or select “not sure.”';
    }
    if (page == 3 &&
        (_scheduleRegularity == null ||
            _activityLevel == null ||
            !_bedtimeConfirmed ||
            !_wakeTimeConfirmed)) {
      return 'Choose your schedule and activity level, then confirm both sleep times.';
    }
    if (page == 4 && (!_confidenceAnswered || !_stressAnswered)) {
      return 'Please answer both final baseline ratings before finishing.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    final assessment = BaselineAssessment(
      targetBehavior: _targetBehavior!,
      goal: _goal!,
      daysEngagedPast30: _daysEngagedPast30.round(),
      typicalCravingScore: _typicalCraving.round(),
      typicalEpisodeMinutes: _typicalEpisodeMinutes.round(),
      highRiskTimeBlocks: _riskTimes.toList()..sort(),
      highRiskDays: _riskDays.toList()..sort(),
      commonTriggers: _triggers.toList()..sort(),
      motives: _motives.toList()..sort(),
      scheduleRegularity: _scheduleRegularity!,
      typicalBedtimeMinute: _bedtime.hour * 60 + _bedtime.minute,
      typicalWakeMinute: _wakeTime.hour * 60 + _wakeTime.minute,
      activityLevel: _activityLevel!,
      confidenceToResistScore: _confidenceToResist.round(),
      typicalStressScore: _typicalStress.round(),
    );

    try {
      await _repository.submitInitialAssessment(assessment);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.dashboard,
        (route) => false,
      );
    } catch (error, stackTrace) {
      debugPrint('Baseline assessment save failed: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('We could not save your baseline. Check your connection and try again.'),
        ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Baseline Assessment'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: (_page + 1) / 5,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(99),
                    backgroundColor: AppTheme.softGreen,
                    color: AppTheme.primaryGreen,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Step ${_page + 1} of 5',
                    style: const TextStyle(color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _behaviorPage(),
                  _timingPage(),
                  _cuesPage(),
                  _routinePage(),
                  _reviewPage(),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Row(
                children: [
                  if (_page > 0) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _back,
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: EmaPrimaryButton(
                      label: _page == 4 ? 'Finish baseline' : 'Continue',
                      busy: _saving,
                      onPressed: _next,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageShell({required String title, required String subtitle, required List<Widget> children}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, height: 1.35)),
        const SizedBox(height: 22),
        ...children,
      ],
    );
  }

  Widget _behaviorPage() => _pageShell(
        title: 'What are you tracking?',
        subtitle:
            'This one-time baseline gives RecoverySense context. It does not diagnose you and it does not determine model weights by itself; repeated sensor data and EMA labels are what allow the model to learn associations.',
        children: [
          _dropdown(
            label: 'Behavior of concern',
            value: _targetBehavior,
            options: _behaviors,
            onChanged: (value) => setState(() => _targetBehavior = value),
          ),
          const SizedBox(height: 16),
          _dropdown(
            label: 'Current goal',
            value: _goal,
            options: _goals,
            onChanged: (value) => setState(() => _goal = value),
          ),
          const SizedBox(height: 22),
          _sliderQuestion(
            label: 'Days you engaged in the behavior during the past 30 days',
            valueText: '${_daysEngagedPast30.round()} days',
            value: _daysEngagedPast30,
            min: 0,
            max: 30,
            divisions: 30,
            answered: _daysEngagedAnswered,
            onInteractionStarted: () => setState(() => _daysEngagedAnswered = true),
            onChanged: (value) => setState(() {
              _daysEngagedPast30 = value;
              _daysEngagedAnswered = true;
            }),
          ),
          _sliderQuestion(
            label: 'Typical urge/craving intensity',
            valueText: '${_typicalCraving.round()} / 10',
            value: _typicalCraving,
            min: 0,
            max: 10,
            divisions: 10,
            answered: _typicalCravingAnswered,
            onInteractionStarted: () => setState(() => _typicalCravingAnswered = true),
            onChanged: (value) => setState(() {
              _typicalCraving = value;
              _typicalCravingAnswered = true;
            }),
          ),
          _sliderQuestion(
            label: 'Typical duration of an episode',
            valueText: '${_typicalEpisodeMinutes.round()} min',
            value: _typicalEpisodeMinutes,
            min: 0,
            max: 240,
            divisions: 16,
            answered: _episodeDurationAnswered,
            onInteractionStarted: () => setState(() => _episodeDurationAnswered = true),
            onChanged: (value) => setState(() {
              _typicalEpisodeMinutes = value;
              _episodeDurationAnswered = true;
            }),
          ),
        ],
      );

  Widget _timingPage() => _pageShell(
        title: 'When does risk usually feel higher?',
        subtitle:
            'These are your own starting estimates. RecoverySense will keep them separate from later data-derived time-of-day patterns.',
        children: [
          _multiChoice('Times of day', _timeBlocks, _riskTimes),
          const SizedBox(height: 20),
          _multiChoice('Days of week', _days, _riskDays),
        ],
      );

  Widget _cuesPage() => _pageShell(
        title: 'What tends to come before the urge?',
        subtitle:
            'Choose all that commonly apply. These categories are stored as baseline context so later analyses can compare them with repeated EMA and sensor patterns.',
        children: [
          _multiChoice('Common triggers or cues', _triggerOptions, _triggers),
          const SizedBox(height: 20),
          _multiChoice('Common motives', _motiveOptions, _motives),
        ],
      );

  Widget _routinePage() => _pageShell(
        title: 'Routine and sleep context',
        subtitle:
            'Clock time can mean different things for shift workers or irregular schedules, so RecoverySense stores routine context instead of assuming everyone follows the same day.',
        children: [
          _dropdown(
            label: 'Typical schedule',
            value: _scheduleRegularity,
            options: const <String, String>{
              'regular': 'Mostly regular',
              'variable': 'Variable / changes often',
              'shift': 'Shift or overnight work',
            },
            onChanged: (value) => setState(() => _scheduleRegularity = value),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _timeButton('Typical bedtime', _bedtime, _bedtimeConfirmed, (value) => setState(() { _bedtime = value; _bedtimeConfirmed = true; }))),
              const SizedBox(width: 12),
              Expanded(child: _timeButton('Typical wake time', _wakeTime, _wakeTimeConfirmed, (value) => setState(() { _wakeTime = value; _wakeTimeConfirmed = true; }))),
            ],
          ),
          const SizedBox(height: 18),
          _dropdown(
            label: 'Typical activity level',
            value: _activityLevel,
            options: const <String, String>{
              'low': 'Mostly sedentary',
              'moderate': 'Moderately active',
              'high': 'Highly active',
            },
            onChanged: (value) => setState(() => _activityLevel = value),
          ),
        ],
      );

  Widget _reviewPage() => _pageShell(
        title: 'Final baseline context',
        subtitle:
            'These last ratings help describe your starting context. They are not clinical scores and they should not be interpreted as causes of craving.',
        children: [
          _sliderQuestion(
            label: 'How confident are you that you can resist an urge when you want to?',
            valueText: '${_confidenceToResist.round()} / 10',
            value: _confidenceToResist,
            min: 0,
            max: 10,
            divisions: 10,
            answered: _confidenceAnswered,
            onInteractionStarted: () => setState(() => _confidenceAnswered = true),
            onChanged: (value) => setState(() {
              _confidenceToResist = value;
              _confidenceAnswered = true;
            }),
          ),
          _sliderQuestion(
            label: 'On a typical day, how much stress do you experience?',
            valueText: '${_typicalStress.round()} / 10',
            value: _typicalStress,
            min: 0,
            max: 10,
            divisions: 10,
            answered: _stressAnswered,
            onInteractionStarted: () => setState(() => _stressAnswered = true),
            onChanged: (value) => setState(() {
              _typicalStress = value;
              _stressAnswered = true;
            }),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.softGreen.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'After you finish, the long baseline will not appear again for this assessment version. Your regular EMA remains the short 0–10 craving question.',
              style: TextStyle(height: 1.35),
            ),
          ),
        ],
      );

  Widget _dropdown({
    required String label,
    required String? value,
    required Map<String, String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
          .toList(growable: false),
      onChanged: onChanged,
    );
  }

  Widget _sliderQuestion({
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required bool answered,
    required VoidCallback onInteractionStarted,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            answered ? valueText : 'Tap or drag to answer',
            style: TextStyle(
              color: answered ? AppTheme.primaryGreen : AppTheme.textMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChangeStart: (_) => onInteractionStarted(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _multiChoice(String label, Map<String, String> options, Set<String> selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.entries.map((entry) {
            final isSelected = selected.contains(entry.key);
            return FilterChip(
              label: Text(entry.value),
              selected: isSelected,
              selectedColor: AppTheme.softGreen,
              checkmarkColor: AppTheme.primaryGreen,
              onSelected: (value) {
                setState(() {
                  if (entry.key == 'unsure' || entry.key == 'no_pattern') {
                    selected.clear();
                    if (value) selected.add(entry.key);
                    return;
                  }
                  selected.remove('unsure');
                  selected.remove('no_pattern');
                  value ? selected.add(entry.key) : selected.remove(entry.key);
                });
              },
            );
          }).toList(growable: false),
        ),
      ],
    );
  }

  Widget _timeButton(
    String label,
    TimeOfDay value,
    bool confirmed,
    ValueChanged<TimeOfDay> onChanged,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: value);
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(confirmed ? value.format(context) : 'Select time', style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
