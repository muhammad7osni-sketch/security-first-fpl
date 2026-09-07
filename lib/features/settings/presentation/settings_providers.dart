import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_providers.dart';
import '../domain/user_preferences.dart';
import '../data/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(supabaseClientProvider));
});

final userPreferencesProvider = FutureProvider<UserPreferences>((ref) async {
  final appUser = await ref.watch(currentAppUserProvider.future);
  if (appUser == null) return const UserPreferences();

  final repo = ref.watch(settingsRepositoryProvider);
  final result = await repo.load(appUser.id);
  return result.when(ok: (v) => v, err: (_) => const UserPreferences());
});
