import 'dart:math';

import '../models/ema_answer.dart';
import '../models/sensor_reading.dart';

class MockSensorRepository {
  final List<SensorReading> _readings = <SensorReading>[];
  final List<EmaAnswer> _emaAnswers = <EmaAnswer>[];
  final Random _random = Random(7);

  List<SensorReading> get readings => List.unmodifiable(_readings);
  List<EmaAnswer> get emaAnswers => List.unmodifiable(_emaAnswers);

  SensorReading latestReading() {
    if (_readings.isEmpty) {
      addMockReading();
    }
    return _readings.last;
  }

  SensorReading addMockReading() {
    final reading = SensorReading(
      timestamp: DateTime.now(),
      heartRate: 72 + _random.nextInt(35).toDouble(),
      accelX: _random.nextDouble() * 2 - 1,
      accelY: _random.nextDouble() * 2 - 1,
      accelZ: _random.nextDouble() * 2 - 1,
    );
    _readings.add(reading);
    return reading;
  }

  bool shouldTriggerEma(SensorReading reading) {
    return reading.heartRate >= 95 || reading.accelMagnitude >= 1.8;
  }

  void saveEmaAnswer(EmaAnswer answer) {
    _emaAnswers.add(answer);
  }
}
