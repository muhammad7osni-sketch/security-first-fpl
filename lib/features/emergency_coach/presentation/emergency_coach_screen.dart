import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/status_colors.dart';
import '../../../core/widgets/status_accent_card.dart';
import '../data/emergency_coach_providers.dart';
import '../domain/models/coach_models.dart';

/// Full Emergency Coach view (plan section 3): every detected issue with
/// its severity, and every proposed action. The user applies actions
/// manually in the official FPL app - this screen never submits
/// anything on their behalf (plan section 0).
class EmergencyCoachScreen extends ConsumerWidget {
  const EmergencyCoachScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPlan = ref.watch(emergencyCoachPlanProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Coach')),
      body: asyncPlan.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not build a plan right now: $error'),
        ),
        data: (plan) {
          if (plan == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Link your FPL account from the dashboard first.'),
            );
          }
          if (plan.isAllClear) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: context.status.good, size: 48),
                  const SizedBox(height: 12),
                  const Text('No issues detected in your current squad.'),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${plan.issues.length} issue(s) found',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              for (final issue in plan.issues) _IssueTile(issue: issue),
              if (plan.actions.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Suggested actions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                for (final action in plan.actions) _ActionTile(action: action),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _IssueTile extends StatelessWidget {
  final CoachIssue issue;
  const _IssueTile({required this.issue});

  @override
  Widget build(BuildContext context) {
    final status = context.status;
    final color = switch (issue.severity) {
      CoachIssueSeverity.critical => status.critical,
      CoachIssueSeverity.warning => status.warning,
      CoachIssueSeverity.info => status.info,
    };
    final icon = switch (issue.severity) {
      CoachIssueSeverity.critical => Icons.error,
      CoachIssueSeverity.warning => Icons.warning_amber_rounded,
      CoachIssueSeverity.info => Icons.info_outline,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StatusAccentCard(
        accentColor: color,
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(issue.playerName),
          subtitle: Text(issue.description),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final CoachAction action;
  const _ActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.lightbulb_outline),
          title: Text(action.description),
        ),
      ),
    );
  }
}
