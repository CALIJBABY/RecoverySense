import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/watch_sensor_sample.dart';
import '../../services/watch/watch_connection_service.dart';
import '../../widgets/app_bottom_navigation.dart';
import '../../widgets/metric_tile.dart';
import '../../widgets/section_card.dart';

class WatchScreen extends StatelessWidget {
  const WatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Sensors')),
      bottomNavigationBar: const AppBottomNavigation(currentIndex: 1),
      body: StreamBuilder<WatchSensorSample>(
        stream: WatchConnectionService.instance.liveStream,
        builder: (context, snapshot) {
          final reading = snapshot.data;
          final connected = reading != null;
          final sleepMode = reading?.recordingMode == 'sleep';

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: connected ? AppTheme.softGreen : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.borderGreen),
                ),
                child: Row(
                  children: [
                    Icon(
                      connected
                          ? Icons.check_circle_rounded
                          : Icons.watch_off_outlined,
                      color: connected
                          ? AppTheme.primaryGreenDark
                          : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        connected
                            ? sleepMode
                                ? 'Connected · overnight mode'
                                : 'Connected · live stream'
                            : 'Waiting for watch data',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (connected)
                      Text(
                        _formatTime(reading.timestamp.toLocal()),
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              SectionCard(
                title: 'Current Measurements',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: MetricTile(
                            icon: Icons.favorite_rounded,
                            label: 'Heart rate',
                            value: reading?.heartRate?.toString() ?? '--',
                            unit: 'bpm',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MetricTile(
                            icon: Icons.motion_photos_on_rounded,
                            label: 'Motion',
                            value: reading?.accelerationG.toStringAsFixed(2) ?? '--',
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
                            icon: Icons.screen_rotation_alt_rounded,
                            label: 'Rotation',
                            value: reading?.gyroMagnitude?.toStringAsFixed(2) ?? '--',
                            unit: 'rad/s',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MetricTile(
                            icon: Icons.directions_walk_rounded,
                            label: 'Steps',
                            value: reading?.stepCount?.round().toString() ?? '--',
                            unit: 'total',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: 'Signal Quality',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.softGreen,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        reading?.heartRateValid == true
                            ? Icons.graphic_eq_rounded
                            : Icons.info_outline_rounded,
                        color: AppTheme.primaryGreenDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reading == null
                                ? 'No signal yet'
                                : reading.heartRateValid
                                    ? 'Heart-rate signal ready'
                                    : 'Heart-rate value withheld',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            reading?.heartRateQualityReason ??
                                'Open the watch app and keep the watch snug.',
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (snapshot.hasError)
                const SectionCard(
                  title: 'Connection',
                  child: Text('Watch data is temporarily unavailable.'),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
