import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'core/config/env.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_lifecycle_observer.dart';
import 'features/authentication/presentation/auth_providers.dart';
import 'features/authentication/presentation/sign_in_screen.dart';
import 'features/dashboard/presentation/dashboard_controller.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Env.isConfigured) {
    await sb.Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
  }

  runApp(ProviderScope(
    child: AppLifecycleRefresher(
      providersToRefresh: [dashboardDataProvider],
      child: const SquadIqApp(),
    ),
  ));
}

class SquadIqApp extends StatelessWidget {
  const SquadIqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SquadIQ',
      theme: AppTheme.matchday,
      home: Env.isConfigured ? const _AuthGate() : const _MissingConfigScreen(),
    );
  }
}

/// Routes between sign-in and the dashboard based on Supabase auth state.
/// This is intentionally the only place that branches on auth — feature
/// screens assume they're only ever shown to a signed-in user.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);
    final hasSession = authState.valueOrNull?.session != null ||
        ref.read(authRepositoryProvider).currentAuthUser != null;

    if (authState.isLoading && !hasSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return hasSession ? const DashboardScreen() : const SignInScreen();
  }
}

/// Shown instead of crashing when `--dart-define=SUPABASE_URL=...
/// --dart-define=SUPABASE_ANON_KEY=...` wasn't passed at build/run time.
/// Per plan section 17, these are never hardcoded into the repo, so a
/// missing config is an expected local-setup state, not a bug.
class _MissingConfigScreen extends StatelessWidget {
  const _MissingConfigScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Missing Supabase config.\n\n'
            'Run with:\n'
            '  flutter run \\\n'
            '    --dart-define=SUPABASE_URL=... \\\n'
            '    --dart-define=SUPABASE_ANON_KEY=...',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
