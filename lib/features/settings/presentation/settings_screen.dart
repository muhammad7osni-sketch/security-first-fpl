// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_providers.dart';
import '../../shop/presentation/shop_screen.dart';
import '../domain/user_preferences.dart';
import 'settings_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  UserPreferences? _local;
  bool _isSaving = false;

  Future<void> _update(UserPreferences updated) async {
    setState(() {
      _local = updated;
      _isSaving = true;
    });

    final appUser = await ref.read(currentAppUserProvider.future);
    if (appUser == null) return;

    final repo = ref.read(settingsRepositoryProvider);
    await repo.save(appUser.id, updated);

    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final asyncPrefs = ref.watch(userPreferencesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: asyncPrefs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (loaded) {
          final prefs = _local ?? loaded;

          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Notifications',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              _NotificationSwitch(
                title: 'Deadline reminders',
                subtitle: 'Alerts before your gameweek deadline',
                notificationKey: NotificationKeys.deadlineReminder,
                prefs: prefs,
                onChanged: _update,
              ),
              _NotificationSwitch(
                title: 'Injury / availability alerts',
                subtitle: 'When a squad player is flagged by FPL',
                notificationKey: NotificationKeys.injuryAlert,
                prefs: prefs,
                onChanged: _update,
              ),
              _NotificationSwitch(
                title: 'Price change alerts',
                subtitle: 'When a squad player rises or falls in price',
                notificationKey: NotificationKeys.priceChange,
                prefs: prefs,
                onChanged: _update,
              ),
              _NotificationSwitch(
                title: 'Emergency Coach alerts',
                subtitle: 'When new squad issues are detected',
                notificationKey: NotificationKeys.emergencyCoach,
                prefs: prefs,
                onChanged: _update,
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('AI Assistant',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              RadioListTile<String>(
                title: const Text('Concise'),
                value: 'concise',
                groupValue: prefs.aiTone,
                onChanged: (v) => _update(prefs.copyWith(aiTone: v)),
              ),
              RadioListTile<String>(
                title: const Text('Detailed'),
                value: 'detailed',
                groupValue: prefs.aiTone,
                onChanged: (v) => _update(prefs.copyWith(aiTone: v)),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.shopping_bag_outlined),
                title: const Text('Shop'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ShopScreen()),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () => ref.read(authRepositoryProvider).signOut(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final String notificationKey;
  final UserPreferences prefs;
  final ValueChanged<UserPreferences> onChanged;

  const _NotificationSwitch({
    required this.title,
    required this.subtitle,
    required this.notificationKey,
    required this.prefs,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: prefs.notificationEnabled(notificationKey),
      onChanged: (value) => onChanged(prefs.copyWith(
        notificationSettings: {
          ...prefs.notificationSettings,
          notificationKey: value
        },
      )),
    );
  }
}
