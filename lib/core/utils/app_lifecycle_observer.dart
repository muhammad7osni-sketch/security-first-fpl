import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Observes app lifecycle state changes (foreground/background transitions).
///
/// Use case: when the user navigates to the official FPL website to make
/// changes, then returns to SquadIQ, we want to automatically refresh the
/// dashboard data to reflect any updates they made (e.g., new transfers,
/// captain change).
///
/// This observer watches for `AppLifecycleState.resumed` and triggers a
/// callback when the app returns to the foreground.
class AppLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResumed;

  AppLifecycleObserver({required this.onResumed});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      onResumed();
    }
  }
}

/// Widget that registers a lifecycle observer and cleans it up on disposal.
///
/// Usage:
/// ```dart
/// AppLifecycleListener(
///   onResumed: () => ref.invalidate(dashboardDataProvider),
///   child: YourWidget(),
/// )
/// ```
class AppLifecycleListener extends StatefulWidget {
  final VoidCallback onResumed;
  final Widget child;

  const AppLifecycleListener({
    super.key,
    required this.onResumed,
    required this.child,
  });

  @override
  State<AppLifecycleListener> createState() => _AppLifecycleListenerState();
}

class _AppLifecycleListenerState extends State<AppLifecycleListener> {
  late final AppLifecycleObserver _observer;

  @override
  void initState() {
    super.initState();
    _observer = AppLifecycleObserver(onResumed: widget.onResumed);
    WidgetsBinding.instance.addObserver(_observer);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_observer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Riverpod-aware lifecycle listener that automatically refreshes providers
/// when the app resumes.
///
/// Usage in main.dart:
/// ```dart
/// return ProviderScope(
///   child: AppLifecycleRefresher(
///     providersToRefresh: [dashboardDataProvider],
///     child: MaterialApp(...),
///   ),
/// );
/// ```
class AppLifecycleRefresher extends ConsumerStatefulWidget {
  final List<ProviderOrFamily> providersToRefresh;
  final Widget child;

  const AppLifecycleRefresher({
    super.key,
    required this.providersToRefresh,
    required this.child,
  });

  @override
  ConsumerState<AppLifecycleRefresher> createState() =>
      _AppLifecycleRefresherState();
}

class _AppLifecycleRefresherState extends ConsumerState<AppLifecycleRefresher> {
  late final AppLifecycleObserver _observer;

  @override
  void initState() {
    super.initState();
    _observer = AppLifecycleObserver(
      onResumed: () {
        for (final provider in widget.providersToRefresh) {
          ref.invalidate(provider);
        }
      },
    );
    WidgetsBinding.instance.addObserver(_observer);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_observer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
