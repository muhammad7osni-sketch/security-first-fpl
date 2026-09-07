import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/notification_rules.dart';

/// The only place in the app that touches `flutter_local_notifications`
/// directly. Everything else works with [PlannedNotification] (plain
/// data from [NotificationRules]), so swapping the underlying plugin
/// later never touches scheduling logic or its tests.
///
/// Deliberately local-only: these fire from data already on the device
/// (the gameweek deadline, fetched normally). Real push notifications
/// (server-initiated — e.g. "a squad player's injury status just
/// changed" detected server-side) would need `firebase_messaging` wired
/// to a backend trigger, which is a separate, not-yet-built piece — see
/// the README's notifications status note.
class NotificationScheduler {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    _initialized = true;
  }

  /// Cancels any previously-scheduled deadline reminders and schedules
  /// the given [notifications] fresh. Called with a full, current list
  /// each time (plan section 11's single-source-of-truth pattern applies
  /// here too) rather than incrementally diffed — deadline reminders are
  /// cheap to recompute and this avoids the two ever drifting apart.
  Future<void> replaceDeadlineReminders(List<PlannedNotification> notifications) async {
    await init();
    await _plugin.cancelAll();

    for (final n in notifications) {
      await _plugin.zonedSchedule(
        n.id.hashCode,
        n.title,
        n.body,
        tz.TZDateTime.from(n.fireAt, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'deadline_reminders',
            'Deadline reminders',
            importance: Importance.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// Fires immediately - used for a newly-detected critical Emergency
  /// Coach issue rather than a scheduled countdown.
  Future<void> showNow(PlannedNotification notification) async {
    await init();
    await _plugin.show(
      notification.id.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'coach_alerts',
          'Emergency Coach alerts',
          importance: Importance.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
