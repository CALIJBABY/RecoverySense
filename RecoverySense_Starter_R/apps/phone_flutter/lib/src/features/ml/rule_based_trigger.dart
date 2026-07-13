class RuleBasedTrigger {
  bool shouldTriggerEma({
    required double heartRate,
    required double accelMagnitude,
    double? baselineHeartRate,
  }) {
    final baseline = baselineHeartRate ?? 75.0;
    final elevatedHr = heartRate > baseline + 25.0;
    final lowMovement = accelMagnitude < 0.25;
    return elevatedHr && lowMovement;
  }
}
