/// Mirrors `user_preferences` (schema.sql). `notificationSettings` is a
/// free-form map of toggle-key -> enabled, matching the table's jsonb
/// column — kept generic so adding a new notification category later is
/// a UI-only change, not a schema migration.
class UserPreferences {
  final Map<String, bool> notificationSettings;
  final List<int> lockedPlayers;
  final String aiTone;

  const UserPreferences({
    this.notificationSettings = const {},
    this.lockedPlayers = const [],
    this.aiTone = 'concise',
  });

  bool notificationEnabled(String key, {bool defaultValue = true}) =>
      notificationSettings[key] ?? defaultValue;

  UserPreferences copyWith({
    Map<String, bool>? notificationSettings,
    List<int>? lockedPlayers,
    String? aiTone,
  }) {
    return UserPreferences(
      notificationSettings: notificationSettings ?? this.notificationSettings,
      lockedPlayers: lockedPlayers ?? this.lockedPlayers,
      aiTone: aiTone ?? this.aiTone,
    );
  }

  factory UserPreferences.fromSupabaseRow(Map<String, dynamic> row) {
    final rawSettings = row['notification_settings'] as Map<String, dynamic>? ?? {};
    return UserPreferences(
      notificationSettings: rawSettings.map((k, v) => MapEntry(k, v as bool)),
      lockedPlayers: (row['locked_players'] as List?)?.cast<int>() ?? const [],
      aiTone: row['ai_tone'] as String? ?? 'concise',
    );
  }

  Map<String, dynamic> toUpsertRow(String userId) => {
        'user_id': userId,
        'notification_settings': notificationSettings,
        'locked_players': lockedPlayers,
        'ai_tone': aiTone,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

/// Notification categories the Settings screen exposes toggles for.
/// Keys match what a future notification-scheduling service would read
/// from `notification_settings` — see the pending item in the README
/// about `firebase_messaging` not being wired up yet.
class NotificationKeys {
  static const deadlineReminder = 'deadline_reminder';
  static const injuryAlert = 'injury_alert';
  static const priceChange = 'price_change';
  static const emergencyCoach = 'emergency_coach';
}
