import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/result.dart';
import '../domain/user_preferences.dart';

class SettingsRepository {
  final sb.SupabaseClient _client;

  SettingsRepository(this._client);

  Future<Result<UserPreferences>> load(String userId) async {
    try {
      final row = await _client
          .from('user_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return Result.ok(const UserPreferences());
      return Result.ok(UserPreferences.fromSupabaseRow(row));
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }

  Future<Result<UserPreferences>> save(
      String userId, UserPreferences prefs) async {
    try {
      await _client
          .from('user_preferences')
          .upsert(prefs.toUpsertRow(userId), onConflict: 'user_id');
      return Result.ok(prefs);
    } catch (e) {
      return Result.err(AppFailure(AppFailureType.unknown, e.toString()));
    }
  }
}
