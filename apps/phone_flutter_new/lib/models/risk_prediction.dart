class RiskContributor {
  const RiskContributor({
    required this.feature,
    required this.displayName,
    required this.contribution,
    this.value,
    this.unit,
    this.direction = 'increasing',
  });

  final String feature;
  final String displayName;
  final double contribution;
  final double? value;
  final String? unit;
  final String direction;

  factory RiskContributor.fromMap(Map<dynamic, dynamic> map) {
    final rawContribution = map['contribution'];
    final rawValue = map['value'];
    return RiskContributor(
      feature: map['feature']?.toString() ?? 'unknown_feature',
      displayName: map['display_name']?.toString() ??
          humanizeFeature(map['feature']?.toString() ?? 'unknown_feature'),
      contribution: rawContribution is num ? rawContribution.toDouble() : 0,
      value: rawValue is num ? rawValue.toDouble() : null,
      unit: map['unit']?.toString(),
      direction: map['direction']?.toString() ?? 'increasing',
    );
  }

  static String humanizeFeature(String feature) {
    if (feature.startsWith('time_of_day_')) return 'Time of day pattern';
    if (feature.startsWith('day_of_week_')) return 'Day of week pattern';
    if (feature.contains('hr_baseline') || feature.contains('hr_activation')) {
      return 'Heart rate relative to your baseline';
    }
    if (feature.contains('sleep')) return 'Recent sleep pattern';
    if (feature.contains('accel') || feature.contains('gyro') || feature.contains('motion')) {
      return 'Movement pattern';
    }
    if (feature.contains('step')) return 'Recent activity';
    if (feature.contains('previous_ema') || feature.contains('ema_')) {
      return 'Recent craving history';
    }
    if (feature.contains('boredom')) return 'Recent boredom';
    if (feature.contains('stress')) return 'Recent stress';
    if (feature.contains('anxiety')) return 'Recent anxiety';
    return feature.replaceAll('_', ' ');
  }
}

class RiskPrediction {
  const RiskPrediction({
    required this.probability,
    required this.timestamp,
    required this.modelVersion,
    required this.modelName,
    required this.interpretabilityModel,
    required this.interpretabilityMethod,
    required this.interpretabilityProbability,
    required this.topContributors,
    required this.predictionBasis,
    required this.inputModalities,
    required this.currentEmaDirectInput,
    required this.displayEligible,
    required this.demoOnly,
  });

  final double probability;
  final DateTime timestamp;
  final String modelVersion;
  final String modelName;
  final String interpretabilityModel;
  final String interpretabilityMethod;
  final double? interpretabilityProbability;
  final List<RiskContributor> topContributors;
  final String predictionBasis;
  final List<String> inputModalities;
  final bool currentEmaDirectInput;

  /// True only for a complete, non-demo prediction explicitly approved for
  /// participant display. Invalid or legacy partial records remain available
  /// in research storage but cannot masquerade as a current dashboard result.
  final bool displayEligible;
  final bool demoOnly;

  bool get selectedModelIsInterpretabilityModel =>
      modelName == interpretabilityModel;

  bool get isSensorBacked =>
      predictionBasis == 'sensor_window_plus_prior_context' &&
      !currentEmaDirectInput &&
      inputModalities.any(
        (value) => const <String>{
          'accelerometer',
          'gyroscope',
          'heart_rate',
          'steps',
        }.contains(value),
      );

  factory RiskPrediction.fromMap(Map<String, dynamic> map) {
    final rawProbability = map['probability'] ?? map['risk_probability'];
    final probabilityValid = rawProbability is num &&
        rawProbability.toDouble().isFinite &&
        rawProbability.toDouble() >= 0 &&
        rawProbability.toDouble() <= 1;
    final probability = probabilityValid ? rawProbability.toDouble() : 0.0;

    final rawInterpretabilityProbability = map['interpretability_probability'];
    final timestampMs = (map['timestamp_ms'] as num?)?.toInt() ??
        (map['created_at_ms'] as num?)?.toInt() ??
        0;
    final timestampValid = timestampMs > 0;

    final modelVersion = map['model_version']?.toString().trim() ?? '';
    final modelName = map['model_name']?.toString().trim() ?? '';
    final modelIdentityValid = modelVersion.isNotEmpty &&
        modelVersion != 'unknown' &&
        modelName.isNotEmpty &&
        modelName != 'unknown';
    final demoOnly = map['demo_only'] == true;
    final participantDisplayAllowed =
        map['participant_display_allowed'] == true;
    final schemaVersion = (map['schema_version'] as num?)?.toInt() ?? 0;
    final predictionBasis = map['prediction_basis']?.toString() ?? '';
    final currentEmaDirectInput = map['current_ema_direct_input'] == true;
    final rawInputModalities = map['input_modalities'];
    final inputModalities = rawInputModalities is Iterable
        ? rawInputModalities
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false)
        : const <String>[];
    final sensorBacked =
        schemaVersion >= 2 &&
            predictionBasis == 'sensor_window_plus_prior_context' &&
            !currentEmaDirectInput &&
            inputModalities.any(
              (value) => const <String>{
                'accelerometer',
                'gyroscope',
                'heart_rate',
                'steps',
              }.contains(value),
            );

    final rawContributors = map['top_contributors'];
    final rankedContributors = rawContributors is Iterable
        ? rawContributors
            .whereType<Map>()
            .map((item) => RiskContributor.fromMap(item))
            .where((item) =>
                item.direction == 'increasing' &&
                item.contribution.isFinite &&
                item.contribution > 0)
            .toList()
        : <RiskContributor>[];
    rankedContributors.sort(
      (left, right) => right.contribution.compareTo(left.contribution),
    );
    final contributors = rankedContributors.take(3).toList(growable: false);

    return RiskPrediction(
      probability: probability.clamp(0.0, 1.0).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        timestampValid ? timestampMs : 0,
        isUtc: true,
      ).toLocal(),
      modelVersion: modelVersion.isEmpty ? 'unknown' : modelVersion,
      modelName: modelName.isEmpty ? 'unknown' : modelName,
      interpretabilityModel: map['interpretability_model']?.toString() ?? 'decision_tree',
      interpretabilityMethod:
          map['interpretability_method']?.toString() ?? 'decision_tree_path_probability_delta',
      interpretabilityProbability: rawInterpretabilityProbability is num &&
              rawInterpretabilityProbability.toDouble().isFinite
          ? rawInterpretabilityProbability.toDouble().clamp(0.0, 1.0).toDouble()
          : null,
      topContributors: contributors,
      predictionBasis: predictionBasis,
      inputModalities: inputModalities,
      currentEmaDirectInput: currentEmaDirectInput,
      demoOnly: demoOnly,
      displayEligible: probabilityValid &&
          sensorBacked &&
          timestampValid &&
          modelIdentityValid &&
          participantDisplayAllowed &&
          !demoOnly,
    );
  }
}
