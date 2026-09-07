/// One planned local notification: when to fire it and what to say.
/// Deliberately just data — `NotificationScheduler` is the only place
/// that touches the actual plugin, so this class stays trivially
/// testable without mocking device notification APIs.
class PlannedNotification {
  final String id;
  final DateTime fireAt;
  final String title;
  final String body;

  const PlannedNotification({
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
  });
}

/// Pure deadline-reminder scheduling logic (plan section 3's trigger
/// thresholds). Takes a deadline and "now", returns which reminder
/// notifications should still be scheduled — i.e. skips any threshold
/// that has already passed, so re-running this after the user opens the
/// app closer to the deadline never re-fires a stale reminder.
class NotificationRules {
  const NotificationRules();

  /// Thresholds before the deadline, matching the plan's own escalation
  /// idea (48h -> 6h -> 90min as the deadline approaches).
  static const _thresholds = [
    Duration(hours: 48),
    Duration(hours: 6),
    Duration(minutes: 90),
  ];

  List<PlannedNotification> deadlineReminders({
    required int gameweekNumber,
    required DateTime deadline,
    required DateTime now,
  }) {
    final planned = <PlannedNotification>[];

    for (final threshold in _thresholds) {
      final fireAt = deadline.subtract(threshold);
      if (fireAt.isBefore(now)) continue; // threshold already passed

      planned.add(PlannedNotification(
        id: 'deadline_gw${gameweekNumber}_${threshold.inMinutes}',
        fireAt: fireAt,
        title: 'GW$gameweekNumber deadline in ${_humanize(threshold)}',
        body: 'Check your squad before the deadline.',
      ));
    }

    return planned;
  }

  /// A single, immediate notification for a newly-detected critical
  /// Emergency Coach issue (plan section 3). Kept separate from the
  /// scheduled deadline reminders since it fires on detection, not on a
  /// countdown.
  PlannedNotification emergencyCoachAlert({
    required String playerName,
    required String description,
    required DateTime now,
  }) {
    return PlannedNotification(
      id: 'coach_${playerName}_${now.millisecondsSinceEpoch}',
      fireAt: now,
      title: 'Squad issue: $playerName',
      body: description,
    );
  }

  String _humanize(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h';
    return '${d.inMinutes}m';
  }
}
