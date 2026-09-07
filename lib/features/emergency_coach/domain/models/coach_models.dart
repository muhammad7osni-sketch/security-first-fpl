enum CoachIssueType {
  injured,
  suspended,
  unavailable,
  doubtful,
  blankFixture,
  suboptimalCaptain,
  benchOutperformsStarter,
}

enum CoachIssueSeverity { critical, warning, info }

/// One detected problem with the user's current squad, produced by
/// [EmergencyCoachEngine] from Statistics Engine facts alone. Per plan
/// section 3/11: this is deterministic detection, not an AI judgment —
/// the AI layer's only job downstream is to phrase this in natural
/// language, never to decide whether it's actually a problem.
class CoachIssue {
  final CoachIssueType type;
  final int playerId;
  final String playerName;
  final CoachIssueSeverity severity;
  final String description;

  const CoachIssue({
    required this.type,
    required this.playerId,
    required this.playerName,
    required this.severity,
    required this.description,
  });
}

enum CoachActionType { benchPlayer, promoteFromBench, swapCaptain, considerChip }

/// One concrete, actionable suggestion tied to specific players — never
/// vague advice. The user applies these manually in the official FPL
/// app (plan section 0: no auto-apply, no write access to FPL).
class CoachAction {
  final CoachActionType type;
  final String description;
  final List<int> affectedPlayerIds;

  const CoachAction({
    required this.type,
    required this.description,
    required this.affectedPlayerIds,
  });
}

/// The full output shown to the user and persisted to
/// `emergency_coach_events` (schema.sql) for audit (plan section 13).
class EmergencyCoachPlan {
  final List<CoachIssue> issues;
  final List<CoachAction> actions;
  final DateTime generatedAt;

  const EmergencyCoachPlan({
    required this.issues,
    required this.actions,
    required this.generatedAt,
  });

  bool get hasCriticalIssues =>
      issues.any((i) => i.severity == CoachIssueSeverity.critical);

  bool get isAllClear => issues.isEmpty;
}
