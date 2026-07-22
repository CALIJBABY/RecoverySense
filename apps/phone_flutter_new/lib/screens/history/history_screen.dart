import 'package:flutter/material.dart';

import '../../widgets/section_card.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      'Mock EMA completed: craving score 3',
      'Mock heart rate sample: 76 bpm',
      'Mock accelerometer sample saved',
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SectionCard(
            title: 'Recent Activity',
            child: Column(
              children: items
                  .map(
                    (item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(item),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
