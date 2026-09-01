import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/ema_prompt.dart';
import '../../services/firebase/ema_repository.dart';
import '../../services/ingestion/sensor_ingestion_service.dart';
import '../../widgets/app_bottom_navigation.dart';
import '../../widgets/ema_primary_button.dart';

class EmaScreen extends StatefulWidget {
  const EmaScreen({
    super.key,
    this.prompt = const EmaPrompt(),
  });

  final EmaPrompt prompt;

  @override
  State<EmaScreen> createState() => _EmaScreenState();
}

class _EmaScreenState extends State<EmaScreen> {
  final _repository = EmaRepository();
  late final int _openedAtMs;

  // Keep the thumb centered for a neutral visual starting point, but require a
  // deliberate interaction before the response can be saved. This prevents an
  // untouched default value from becoming a false research label.
  double _cravingScore = 5;
  bool _hasSelectedRating = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _openedAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
  }

  Future<void> _submit() async {
    if (!_hasSelectedRating || _saving) return;
    setState(() => _saving = true);
    try {
      await _repository.submitEma(
        cravingScore: _cravingScore.round(),
        sessionId: SensorIngestionService.instance.latestWatchSessionId,
        openedAtMs: _openedAtMs,
        prompt: widget.prompt,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Craving rating saved: ${_cravingScore.round()}/10')),
      );
      Navigator.pop(context);
    } catch (error, stackTrace) {
      debugPrint('EMA save failed: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not save your rating. Check your connection and try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? get _promptLabel {
    return switch (widget.prompt.source) {
      'scheduled_stratified' => 'Scheduled check-in',
      'random' => 'Research check-in',
      'model' => 'Check-in',
      'scheduled_test' => 'Test check-in',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final score = _cravingScore.round();
    final promptLabel = _promptLabel;
    return Scaffold(
      appBar: AppBar(title: const Text('Check-In')),
      bottomNavigationBar: const AppBottomNavigation(currentIndex: 2),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (promptLabel != null) ...[
                        Text(
                          promptLabel,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: AppTheme.textMuted,
                              ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      Text(
                        'How strong is your craving right now?',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.softGreen.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _hasSelectedRating ? '$score' : '—',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                                    color: AppTheme.primaryGreenDark,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            Text(
                              _hasSelectedRating ? 'out of 10' : 'Select a rating',
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Semantics(
                        label: _hasSelectedRating
                            ? 'Craving rating, $score out of 10'
                            : 'Craving rating not selected. Choose from 0 to 10.',
                        child: Slider(
                          min: 0,
                          max: 10,
                          divisions: 10,
                          value: _cravingScore,
                          label: '$score',
                          onChanged: _saving
                              ? null
                              : (value) => setState(() {
                                    _cravingScore = value;
                                    _hasSelectedRating = true;
                                  }),
                        ),
                      ),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('0 — None'),
                          Text('10 — Extreme'),
                        ],
                      ),
                      const SizedBox(height: 28),
                      EmaPrimaryButton(
                        label: 'Save rating',
                        busy: _saving,
                        onPressed: _hasSelectedRating ? _submit : null,
                      ),
                      if (!_hasSelectedRating) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Choose a rating before saving.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
