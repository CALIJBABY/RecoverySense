import 'package:flutter/material.dart';

import '../../core/router/app_router.dart';
import '../../services/sensors/mock_sensor_service.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sensor = MockSensorService().latest();

    return Scaffold(
      appBar: AppBar(
        title: const Text('RecoverySense'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SectionCard(
            title: 'Live Sensor Snapshot',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'Heart Rate',
                        value: sensor.heartRate.toString(),
                        unit: 'bpm',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricTile(
                        label: 'Accel Magnitude',
                        value: sensor.accelMagnitude.toStringAsFixed(2),
                        unit: 'g',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Mock values are shown until the Wear OS sensor stream is connected.',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Watch Connection',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Status: Disconnected'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.watch),
                  child: const Text('Open Watch Interface'),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Ecological Momentary Assessment',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Trigger or complete a brief craving check-in.'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.ema),
                  child: const Text('Begin EMA'),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Data History',
            child: ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, AppRoutes.history),
              child: const Text('View History'),
            ),
          ),
        ],
      ),
    );
  }
}
