class WatchEmaEvent {
  const WatchEmaEvent({
    required this.uri,
    required this.eventId,
    required this.cravingScore,
    required this.timestampMs,
    required this.openedAtMs,
    required this.submittedAtMs,
    required this.source,
    this.watchSessionId,
    this.promptedAtMs,
  });

  final String uri;
  final String eventId;
  final int cravingScore;
  final int timestampMs;
  final int openedAtMs;
  final int submittedAtMs;
  final String source;
  final String? watchSessionId;
  final int? promptedAtMs;

  factory WatchEmaEvent.fromMap(Map<dynamic, dynamic> map) {
    int requiredInt(String key) {
      final value = map[key];
      if (value is num) return value.toInt();
      throw FormatException('Missing or invalid $key in watch EMA event.');
    }

    final score = requiredInt('cravingScore');
    if (score < 0 || score > 10) {
      throw const FormatException('Watch EMA score must be between 0 and 10.');
    }

    final rawSessionId = map['watchSessionId']?.toString();
    final rawPromptedAt = map['promptedAtMs'];
    return WatchEmaEvent(
      uri: map['uri']?.toString() ?? '',
      eventId: map['eventId']?.toString() ?? '',
      cravingScore: score,
      timestampMs: requiredInt('timestampMs'),
      openedAtMs: requiredInt('openedAtMs'),
      submittedAtMs: requiredInt('submittedAtMs'),
      source: map['source']?.toString() ?? 'watch_manual',
      watchSessionId:
          rawSessionId == null || rawSessionId.isEmpty ? null : rawSessionId,
      promptedAtMs: rawPromptedAt is num && rawPromptedAt.toInt() > 0
          ? rawPromptedAt.toInt()
          : null,
    );
  }
}
