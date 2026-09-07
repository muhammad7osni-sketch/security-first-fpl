import 'package:flutter_test/flutter_test.dart';
import 'package:squadiq/features/notifications/domain/notification_rules.dart';

void main() {
  const rules = NotificationRules();

  group('deadlineReminders', () {
    test('all three thresholds are planned when the deadline is far away', () {
      final now = DateTime.utc(2026, 1, 1, 0, 0);
      final deadline = now.add(const Duration(days: 5));

      final planned = rules.deadlineReminders(
        gameweekNumber: 10,
        deadline: deadline,
        now: now,
      );

      expect(planned.length, 3);
    });

    test('thresholds that have already passed are skipped', () {
      final deadline = DateTime.utc(2026, 1, 10, 12, 0);
      // "now" is only 3 hours before deadline - the 48h and 6h
      // thresholds are already in the past, only 90min remains.
      final now = deadline.subtract(const Duration(hours: 3));

      final planned = rules.deadlineReminders(
        gameweekNumber: 10,
        deadline: deadline,
        now: now,
      );

      expect(planned.length, 1);
      expect(planned.single.fireAt.isAfter(now), isTrue);
    });

    test('no reminders are planned once the deadline itself has passed', () {
      final deadline = DateTime.utc(2026, 1, 10, 12, 0);
      final now = deadline.add(const Duration(minutes: 5));

      final planned = rules.deadlineReminders(
        gameweekNumber: 10,
        deadline: deadline,
        now: now,
      );

      expect(planned, isEmpty);
    });

    test('every planned notification fires strictly before the deadline', () {
      final now = DateTime.utc(2026, 1, 1);
      final deadline = now.add(const Duration(days: 3));

      final planned = rules.deadlineReminders(
        gameweekNumber: 7,
        deadline: deadline,
        now: now,
      );

      for (final p in planned) {
        expect(p.fireAt.isBefore(deadline), isTrue);
      }
    });

    test('notification ids are unique per gameweek and threshold', () {
      final now = DateTime.utc(2026, 1, 1);
      final deadline = now.add(const Duration(days: 5));

      final gw10 = rules.deadlineReminders(gameweekNumber: 10, deadline: deadline, now: now);
      final gw11 = rules.deadlineReminders(gameweekNumber: 11, deadline: deadline, now: now);

      final allIds = [...gw10, ...gw11].map((p) => p.id).toSet();
      expect(allIds.length, gw10.length + gw11.length);
    });
  });

  group('emergencyCoachAlert', () {
    test('fires immediately (fireAt equals the given now)', () {
      final now = DateTime.utc(2026, 1, 1, 9, 0);
      final notification = rules.emergencyCoachAlert(
        playerName: 'Test Player',
        description: 'Ruled out for the season',
        now: now,
      );

      expect(notification.fireAt, now);
      expect(notification.title, contains('Test Player'));
      expect(notification.body, 'Ruled out for the season');
    });
  });
}
