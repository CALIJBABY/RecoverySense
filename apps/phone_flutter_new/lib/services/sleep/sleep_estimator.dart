import 'dart:math' as math;

import '../../models/sleep_epoch.dart';
import '../../models/sleep_session.dart';
import '../../models/watch_sensor_batch.dart';

/// Transparent first-stage sleep/wake estimator.
///
/// This is intentionally not presented as a clinical sleep-stage model. It
/// converts each 30-second watch batch into an estimated sleep probability,
/// then applies temporal smoothing and minimum-duration rules when producing a
/// nightly summary. The same raw data can later train the Python sleep model.
class SleepEstimator {
  const SleepEstimator();

  SleepEpochEstimate estimateBatch(WatchSensorBatch batch) {
    final sessionId = batch.sleepSessionId;
    if (!batch.isSleepBatch || sessionId == null) {
      throw ArgumentError('A sleep-tagged watch batch is required.');
    }

    final acceleration = batch.accelerationG.where((v) => v.isFinite).toList();
    final gyro = batch.gyroMagnitude.where((v) => v.isFinite).toList();
    final heartRate = batch.heartRates
        .where((v) => v >= 30 && v <= 220)
        .map((v) => v.toDouble())
        .toList();
    final knownOffBody = batch.offBody.where((v) => v >= 0).toList();
    final offBodyFraction = knownOffBody.isEmpty
        ? null
        : knownOffBody.where((v) => v == 1).length / knownOffBody.length;

    final movementStd = _std(acceleration);
    final gravityDeviation = acceleration.isEmpty
        ? 1.0
        : acceleration.map((v) => (v - 1).abs()).reduce((a, b) => a + b) /
            acceleration.length;
    final meanGyro = gyro.isEmpty ? null : _mean(gyro);
    final meanHeartRate = heartRate.isEmpty ? null : _mean(heartRate);
    final stepEvents = batch.stepDetected.fold<int>(0, (sum, v) => sum + v);
    final expected = math.max(1, batch.samplingRateHz * 30);
    final coverage = math.min(1.0, acceleration.length / expected);

    final localStart = DateTime.fromMillisecondsSinceEpoch(
      batch.timestampsMs.first,
      isUtc: true,
    ).toLocal();

    double probability = 0.0;
    if ((offBodyFraction ?? 0) >= 0.5 || coverage < 0.5) {
      probability = 0.0;
    } else {
      probability += _descendingScore(movementStd, 0.025, 0.09, 0.34);
      probability += _descendingScore(gravityDeviation, 0.025, 0.12, 0.20);
      probability += meanGyro == null
          ? 0.04
          : _descendingScore(meanGyro, 0.04, 0.20, 0.16);
      probability += stepEvents == 0 ? 0.10 : 0.0;
      probability += meanHeartRate == null
          ? 0.03
          : _heartRateSleepScore(meanHeartRate);
      probability += (localStart.hour >= 20 || localStart.hour < 10) ? 0.10 : 0.0;
      probability *= coverage;
    }
    probability = probability.clamp(0.0, 1.0).toDouble();

    final isValid = coverage >= 0.5 && (offBodyFraction ?? 0) < 0.5;
    return SleepEpochEstimate(
      sleepSessionId: sessionId,
      batchId: batch.batchId,
      start: DateTime.fromMillisecondsSinceEpoch(
        batch.timestampsMs.first,
        isUtc: true,
      ),
      end: DateTime.fromMillisecondsSinceEpoch(
        batch.timestampsMs.last,
        isUtc: true,
      ),
      sleepProbability: probability,
      isSleep: isValid ? probability >= 0.60 : null,
      movementStdG: movementStd,
      meanGravityDeviationG: gravityDeviation,
      meanGyroscopeRadS: meanGyro,
      meanHeartRate: meanHeartRate,
      stepEvents: stepEvents,
      offBodyFraction: offBodyFraction,
      dataCoverage: coverage,
    );
  }

  SleepSummary summarize(
    List<SleepEpochEstimate> input, {
    required DateTime recordingStart,
    required DateTime recordingEnd,
  }) {
    final epochs = [...input]..sort((a, b) => a.start.compareTo(b.start));
    if (epochs.isEmpty) {
      return SleepSummary(
        recordingStart: recordingStart,
        recordingEnd: recordingEnd,
        estimatedSleepOnset: null,
        estimatedWake: null,
        timeInBedMinutes:
            math.max(0, recordingEnd.difference(recordingStart).inSeconds / 60),
        estimatedTotalSleepMinutes: 0,
        estimatedWasoMinutes: 0,
        estimatedSleepEfficiency: 0,
        estimatedAwakenings: 0,
        overnightMeanHeartRate: null,
        overnightMovementStdG: null,
        confidence: 0,
        validEpochs: 0,
        totalEpochs: 0,
      );
    }

    final raw = epochs.map((e) => e.isSleep).toList();
    final smoothed = _majoritySmooth(raw, radius: 2);
    final onsetIndex = _firstSustainedSleep(smoothed, required: 10, window: 12);
    final lastSleepIndex = onsetIndex == null
        ? null
        : _lastSleepIndex(smoothed, startAt: onsetIndex);

    int sleepEpochs = 0;
    int wakeEpochs = 0;
    int awakenings = 0;
    if (onsetIndex != null && lastSleepIndex != null) {
      var inWakeRun = false;
      var wakeRunLength = 0;
      for (var i = onsetIndex; i <= lastSleepIndex; i += 1) {
        final value = smoothed[i];
        if (value == true) {
          sleepEpochs += 1;
          if (inWakeRun && wakeRunLength >= 2) awakenings += 1;
          inWakeRun = false;
          wakeRunLength = 0;
        } else if (value == false) {
          wakeEpochs += 1;
          inWakeRun = true;
          wakeRunLength += 1;
        }
      }
    }

    final epochMinutes = 0.5;
    final totalSleep = sleepEpochs * epochMinutes;
    final waso = wakeEpochs * epochMinutes;
    final timeInBed = math.max(
      0.0,
      recordingEnd.difference(recordingStart).inSeconds / 60.0,
    );
    final efficiency = timeInBed <= 0 ? 0.0 : totalSleep / timeInBed;

    final valid = epochs.where((e) => e.isSleep != null).toList();
    final heartRates = valid
        .map((e) => e.meanHeartRate)
        .whereType<double>()
        .where((v) => v.isFinite)
        .toList();
    final movement = valid
        .map((e) => e.movementStdG)
        .where((v) => v.isFinite)
        .toList();
    final confidenceValues = valid
        .map((e) => ((e.sleepProbability - 0.5).abs() * 2).clamp(0.0, 1.0).toDouble())
        .toList();
    final coverage = epochs.isEmpty ? 0.0 : valid.length / epochs.length;
    final confidence = confidenceValues.isEmpty
        ? 0.0
        : (_mean(confidenceValues) * coverage).clamp(0.0, 1.0).toDouble();

    return SleepSummary(
      recordingStart: recordingStart,
      recordingEnd: recordingEnd,
      estimatedSleepOnset:
          onsetIndex == null ? null : epochs[onsetIndex].start,
      estimatedWake:
          lastSleepIndex == null ? null : epochs[lastSleepIndex].end,
      timeInBedMinutes: timeInBed,
      estimatedTotalSleepMinutes: totalSleep,
      estimatedWasoMinutes: waso,
      estimatedSleepEfficiency: efficiency.clamp(0.0, 1.0).toDouble(),
      estimatedAwakenings: awakenings,
      overnightMeanHeartRate:
          heartRates.isEmpty ? null : _mean(heartRates),
      overnightMovementStdG:
          movement.isEmpty ? null : _mean(movement),
      confidence: confidence,
      validEpochs: valid.length,
      totalEpochs: epochs.length,
    );
  }

  static double _descendingScore(
    double value,
    double best,
    double worst,
    double maximum,
  ) {
    if (!value.isFinite || value >= worst) return 0;
    if (value <= best) return maximum;
    final fraction = 1 - ((value - best) / (worst - best));
    return maximum * fraction.clamp(0.0, 1.0).toDouble();
  }

  static double _heartRateSleepScore(double bpm) {
    if (bpm >= 40 && bpm <= 75) return 0.10;
    if (bpm > 75 && bpm <= 90) return 0.10 * (90 - bpm) / 15;
    if (bpm >= 30 && bpm < 40) return 0.05;
    return 0;
  }

  static List<bool?> _majoritySmooth(
    List<bool?> values, {
    required int radius,
  }) {
    return List<bool?>.generate(values.length, (index) {
      if (values[index] == null) return null;
      var sleeping = 0;
      var awake = 0;
      final start = math.max(0, index - radius);
      final end = math.min(values.length - 1, index + radius);
      for (var i = start; i <= end; i += 1) {
        if (values[i] == true) sleeping += 1;
        if (values[i] == false) awake += 1;
      }
      if (sleeping == awake) return values[index];
      return sleeping > awake;
    });
  }

  static int? _firstSustainedSleep(
    List<bool?> values, {
    required int required,
    required int window,
  }) {
    if (values.length < required) return null;
    for (var start = 0; start <= values.length - required; start += 1) {
      final end = math.min(values.length, start + window);
      final sleeping = values.sublist(start, end).where((v) => v == true).length;
      if (sleeping >= required) return start;
    }
    return null;
  }

  static int? _lastSleepIndex(List<bool?> values, {required int startAt}) {
    for (var i = values.length - 1; i >= startAt; i -= 1) {
      if (values[i] == true) return i;
    }
    return null;
  }

  static double _mean(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static double _std(List<double> values) {
    if (values.length < 2) return 0;
    final mean = _mean(values);
    final variance = values
            .map((v) => (v - mean) * (v - mean))
            .reduce((a, b) => a + b) /
        (values.length - 1);
    return math.sqrt(variance);
  }
}
