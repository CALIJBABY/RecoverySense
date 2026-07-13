class EmaAnswer {
  const EmaAnswer({
    required this.timestamp,
    required this.question,
    required this.answer,
    required this.cravingScore,
  });

  final DateTime timestamp;
  final String question;
  final String answer;
  final int cravingScore;

  Map<String, Object> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'question': question,
      'answer': answer,
      'cravingScore': cravingScore,
    };
  }
}
