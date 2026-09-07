import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/presentation/dashboard_controller.dart';
import '../../emergency_coach/data/emergency_coach_providers.dart';
import '../../emergency_coach/domain/models/coach_models.dart';
import '../../settings/domain/user_preferences.dart';
import '../../settings/presentation/settings_providers.dart';
import '../domain/notification_rules.dart';
import '../data/notification_scheduler.dart';

final notificationSchedulerProvider = Provider<NotificationScheduler>((ref) {
  return NotificationScheduler();
});

const _rules = NotificationRules();

/// Recomputes and re-schedules deadline reminders whenever the dashboard
/// or the user's notification preference changes. Returns nothing
/// meaningful — it's a side-effecting provider read once per app
/// session (see `dashboard_screen.dart` for where it's triggered) rather
/// than something the UI displays directly.
final deadlineRemindersSyncProvider = FutureProvider<void>((ref) async {
  final prefs = await ref.watch(userPreferencesProvider.future);
  if (!prefs.notificationEnabled(NotificationKeys.deadlineReminder)) {
    await ref
        .read(notificationSchedulerProvider)
        .replaceDeadlineReminders(const []);
    return;
  }

  final dashboard = await ref.watch(dashboardDataProvider.future);
  if (dashboard == null) return;

  final gw = dashboard.deadlineGameweek;
  final planned = _rules.deadlineReminders(
    gameweekNumber: gw.number,
    deadline: gw.deadlineTime,
    now: DateTime.now().toUtc(),
  );

  await ref
      .read(notificationSchedulerProvider)
      .replaceDeadlineReminders(planned);
});

/// Fires an immediate local notification for each new critical
/// Emergency Coach issue, gated on the user's preference. "New" is not
/// tracked across sessions here (a genuine dedup store is a reasonable
/// follow-up) - this fires once per app session per current plan, which
/// is acceptable for a first pass since critical issues are rare and the
/// user is already looking at the dashboard when this resolves.
final emergencyCoachAlertSyncProvider = FutureProvider<void>((ref) async {
  final prefs = await ref.watch(userPreferencesProvider.future);
  if (!prefs.notificationEnabled(NotificationKeys.emergencyCoach)) return;

  final plan = await ref.watch(emergencyCoachPlanProvider.future);
  if (plan == null) return;

  final scheduler = ref.read(notificationSchedulerProvider);
  final now = DateTime.now();

  for (final issue in plan.issues) {
    if (issue.severity != CoachIssueSeverity.critical) continue;
    await scheduler.showNow(_rules.emergencyCoachAlert(
      playerName: issue.playerName,
      description: issue.description,
      now: now,
    ));
  }
});
