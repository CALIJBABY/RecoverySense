import 'package:flutter/material.dart';

import '../../models/ema_answer.dart';
import '../../services/mock_sensor_repository.dart';

class EmaScreen extends StatefulWidget {
  const EmaScreen({super.key, required this.repository});

  static const routeName = '/ema';

  final MockSensorRepository repository;

  @override
  State<EmaScreen> createState() => _EmaScreenState();
}

class _EmaScreenState extends State<EmaScreen> {
  int cravingScore = 5;
  String selectedContext = 'Stress';

  final contexts = const [
    'Stress',
    'Boredom',
    'Social trigger',
    'Location trigger',
    'Fatigue',
    'Other',
  ];

  void _save() {
    widget.repository.saveEmaAnswer(
      EmaAnswer(
        timestamp: DateTime.now(),
        question: 'What are your cravings right now?',
        answer: selectedContext,
        cravingScore: cravingScore,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('EMA answer saved locally.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EMA Check-In')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'What are your cravings right now?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Text('Craving intensity: $cravingScore / 10'),
            Slider(
              value: cravingScore.toDouble(),
              min: 0,
              max: 10,
              divisions: 10,
              label: cravingScore.toString(),
              onChanged: (value) => setState(() => cravingScore = value.round()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedContext,
              decoration: const InputDecoration(labelText: 'Most likely trigger'),
              items: contexts
                  .map((context) => DropdownMenuItem(value: context, child: Text(context)))
                  .toList(),
              onChanged: (value) => setState(() => selectedContext = value ?? selectedContext),
            ),
            const Spacer(),
            FilledButton(onPressed: _save, child: const Text('Save EMA Answer')),
          ],
        ),
      ),
    );
  }
}
