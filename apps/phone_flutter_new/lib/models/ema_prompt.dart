class EmaPrompt {
  final String source;
  final int? promptedAtMs;
  final double? triggerProbability;
  final String? modelVersion;
  final double? modelThreshold;
  final int? windowStartMs;
  final int? windowEndMs;
  final String? triggerReason;

  const EmaPrompt({
    this.source = 'manual',
    this.promptedAtMs,
    this.triggerProbability,
    this.modelVersion,
    this.modelThreshold,
    this.windowStartMs,
    this.windowEndMs,
    this.triggerReason,
  });
}
