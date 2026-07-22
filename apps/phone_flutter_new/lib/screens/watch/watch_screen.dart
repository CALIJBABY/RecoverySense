import 'package:flutter/material.dart';

import '../../services/sensors/mock_sensor_service.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_card.dart';

class WatchScreen extends StatelessWidget {
  const WatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sensor = MockSensorService().latest();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wearable Interface'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SectionCard(
            title: 'Connection Status',
            child: const Text(
              'Wear OS connection placeholder. The next milestone is connecting the Galaxy Watch through the Wear OS Data Layer.',
            ),
          ),
          SectionCard(
            title: 'Current Mock Readings',
            child: Column(
              children: [
                MetricTile(
                  label: 'Heart Rate',
                  value: sensor.heartRate.toString(),
                  unit: 'bpm',
                ),
                const SizedBox(height: 12),
                MetricTile(
                  label: 'Accel X',
                  value: sensor.accelX.toStringAsFixed(2),
                  unit: 'g',
                ),
                const SizedBox(height: 12),
                MetricTile(
                  label: 'Accel Y',
                  value: sensor.accelY.toStringAsFixed(2),
                  unit: 'g',
                ),
                const SizedBox(height: 12),
                MetricTile(
                  label: 'Accel Z',
                  value: sensor.accelZ.toStringAsFixed(2),
                  unit: 'g',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
