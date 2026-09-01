class BaselineAssessment {
  const BaselineAssessment({
    required this.targetBehavior,
    required this.goal,
    required this.daysEngagedPast30,
    required this.typicalCravingScore,
    required this.typicalEpisodeMinutes,
    required this.highRiskTimeBlocks,
    required this.highRiskDays,
    required this.commonTriggers,
    required this.motives,
    required this.scheduleRegularity,
    required this.typicalBedtimeMinute,
    required this.typicalWakeMinute,
    required this.activityLevel,
    required this.confidenceToResistScore,
    required this.typicalStressScore,
  });

  final String targetBehavior;
  final String goal;
  final int daysEngagedPast30;
  final int typicalCravingScore;
  final int typicalEpisodeMinutes;
  final List<String> highRiskTimeBlocks;
  final List<String> highRiskDays;
  final List<String> commonTriggers;
  final List<String> motives;
  final String scheduleRegularity;
  final int typicalBedtimeMinute;
  final int typicalWakeMinute;
  final String activityLevel;
  final int confidenceToResistScore;
  final int typicalStressScore;

  Map<String, Object?> toFirestore() => <String, Object?>{
        'target_behavior': targetBehavior,
        'goal': goal,
        'days_engaged_past_30': daysEngagedPast30,
        'typical_craving_score': typicalCravingScore,
        'typical_episode_minutes': typicalEpisodeMinutes,
        'self_reported_high_risk_time_blocks': highRiskTimeBlocks,
        'self_reported_high_risk_days': highRiskDays,
        'common_triggers': commonTriggers,
        'motives': motives,
        'schedule_regularity': scheduleRegularity,
        'typical_bedtime_minute_of_day': typicalBedtimeMinute,
        'typical_wake_minute_of_day': typicalWakeMinute,
        'activity_level': activityLevel,
        'confidence_to_resist_score': confidenceToResistScore,
        'typical_stress_score': typicalStressScore,
        'assessment_version': 1,
        'schema_version': 1,
      };
}
