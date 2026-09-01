import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/router/app_router.dart';
import '../../models/ema_prompt.dart';
import '../../models/watch_sensor_sample.dart';
import '../../services/ema/ema_prompt_service.dart';
import '../../services/ingestion/sensor_ingestion_service.dart';
import '../../services/watch/watch_connection_service.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  StreamSubscription<EmaPrompt>? _promptSubscription;

  @override
  void initState() {
    super.initState();
    _promptSubscription = EmaPromptService.instance.promptStream.listen(
      (prompt) {
        if (!mounted) return;
        Navigator.pushNamed(
          context,
          AppRoutes.ema,
          arguments: prompt,
        );
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
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
        ],
      ),
      body: StreamBuilder<WatchSensorSample>(
        stream: WatchConnectionService.instance.liveStream,
        builder: (context, snapshot) {
          final reading = snapshot.data;
          final connected = reading != null;
          final ingestion = SensorIngestionService.instance;

          return ListView(
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
                            value: reading?.heartRate?.toString() ?? '--',
                            unit: 'bpm',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MetricTile(
                            label: 'Acceleration',
                            value:
                                reading?.accelerationG.toStringAsFixed(2) ?? '--',
                            unit: 'g',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: MetricTile(
                            label: 'Rotation',
                            value:
                                reading?.gyroMagnitude?.toStringAsFixed(2) ?? '--',
                            unit: 'rad/s',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MetricTile(
                            label: 'Steps',
                            value: reading?.stepCount?.round().toString() ?? '--',
                            unit: 'total',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      connected
                          ? 'Receiving live measurements from the Galaxy Watch.'
                          : 'Waiting for the Wear OS sensor stream.',
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: 'Data Logging',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Uploaded batches this run: ${ingestion.uploadedBatchCount}'),
                    const SizedBox(height: 6),
                    Text(
                      ingestion.latestWatchSessionId == null
                          ? 'Session: waiting for first 30-second batch'
                          : 'Session: ${ingestion.latestWatchSessionId}',
                    ),
                    if (ingestion.lastError != null) ...[
                      const SizedBox(height: 8),
                      Text('Last upload error: ${ingestion.lastError}'),
                    ],
                  ],
                ),
              ),
              SectionCard(
                title: 'Watch Connection',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(connected ? 'Status: Connected' : 'Status: Waiting'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.watch),
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
                    const Text(
                      'Record craving, stress, mood, anxiety, boredom, activity, '
                      'social context, and possible triggers.',
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.ema),
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
              if (snapshot.hasError)
                SectionCard(
                  title: 'Watch Connection Error',
                  child: Text(snapshot.error.toString()),
                ),
            ],
          );
        },
      ),
    );
  }
}
