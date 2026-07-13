import 'package:flutter/material.dart';

import '../../models/sensor_reading.dart';
import '../../services/mock_sensor_repository.dart';
import '../ema/ema_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.userEmail,
    required this.repository,
    required this.onLogout,
  });

  final String userEmail;
  final MockSensorRepository repository;
  final VoidCallback onLogout;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late SensorReading latest;
  String triggerStatus = 'No trigger checked yet.';

  @override
  void initState() {
    super.initState();
    latest = widget.repository.latestReading();
  }

  void _addReading() {
    setState(() {
      latest = widget.repository.addMockReading();
      final triggered = widget.repository.shouldTriggerEma(latest);
      triggerStatus = triggered
          ? 'EMA trigger: elevated HR or movement detected.'
          : 'No EMA trigger from latest reading.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RecoverySense'),
        actions: [
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Logged in as ${widget.userEmail}'),
          const SizedBox(height: 16),
          _MetricCard(title: 'Heart Rate', value: '${latest.heartRate.toStringAsFixed(0)} bpm'),
          _MetricCard(title: 'Accel X', value: latest.accelX.toStringAsFixed(3)),
          _MetricCard(title: 'Accel Y', value: latest.accelY.toStringAsFixed(3)),
          _MetricCard(title: 'Accel Z', value: latest.accelZ.toStringAsFixed(3)),
          const SizedBox(height: 16),
          Text(triggerStatus),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _addReading,
            icon: const Icon(Icons.sensors),
            label: const Text('Simulate Watch Reading'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pushNamed(EmaScreen.routeName),
            icon: const Icon(Icons.quiz),
            label: const Text('Open EMA Question'),
          ),
          const SizedBox(height: 16),
          Text('Sensor readings stored locally: ${widget.repository.readings.length}'),
          Text('EMA answers stored locally: ${widget.repository.emaAnswers.length}'),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
