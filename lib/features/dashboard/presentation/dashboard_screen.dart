import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/status_colors.dart';
import '../../../core/widgets/stat_number.dart';
import '../../../core/widgets/status_accent_card.dart';
import '../../../data_providers/models/fixture.dart';
import '../../ai_assistant/presentation/ai_chat_screen.dart';
import '../../emergency_coach/data/emergency_coach_providers.dart';
import '../../emergency_coach/presentation/emergency_coach_screen.dart';
import '../../fixtures/presentation/fixtures_screen.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../players/presentation/players_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../statistics_engine/data/statistics_providers.dart';
import '../../statistics_engine/domain/models/engine_outputs.dart';
import '../../transfers/presentation/transfers_screen.dart';
import '../../wallet/presentation/wallet_screen.dart';
import '../domain/dashboard_data.dart';
import 'dashboard_controller.dart';
import 'link_fpl_account_screen.dart';

/// The Home / Dashboard screen (plan section 2): one screen showing
/// current squad, deadline countdown, and the most important AI alert -
/// no extra navigation required to see "how am I doing right now."
///
/// Visual language: see `core/theme/app_theme.dart` for the full design
/// system ("Matchday" - dark floodlit base, scoreboard numerals, status
/// colors via `context.status`). This screen is the flagship example of
/// applying it: `StatNumber` for the headline figures, `StatusAccentCard`
/// for anything carrying a status meaning, `context.status.*` instead of
/// any hardcoded `Colors.x`.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(dashboardDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SquadIQ'),
        actions: [
          // Quick link to open FPL My Team page
          
          IconButton(
            icon: const Icon(Icons.event_note_outlined),
            tooltip: 'Fixtures',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FixturesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Transfers',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TransfersScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.groups_outlined),
            tooltip: 'Players',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlayersScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Ask SquadIQ',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiChatScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.monetization_on_outlined),
            tooltip: 'Wallet',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WalletScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(dashboardDataProvider.future),
        child: asyncData.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => _ErrorState(error: error),
          data: (data) {
            if (data == null) return const LinkFplAccountScreen();
            return _DashboardBody(data: data);
          },
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.cloud_off, size: 48),
        const SizedBox(height: 12),
        Text(
          "Couldn't load your dashboard right now.",
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        // Deliberately shows the real failure, not a generic message -
        // plan section 4's guardrail applies just as much to plain UI
        // as to the AI chat.
        Text(error.toString()),
      ],
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  final DashboardData data;
  const _DashboardBody({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deadline = data.deadlineGameweek;
    final untilDeadline = deadline.timeUntilDeadline();
    final alerts = data.availabilityAlerts;
    final scoreAsync = ref.watch(startingXiScoreProvider);

    // Side-effecting watches: schedule/refresh local notifications
    // whenever the dashboard (re)loads. These providers return void and
    // are never rendered from - watching them here just keeps them
    // alive and re-evaluated on the same lifecycle as the dashboard
    // itself, without a separate app-wide bootstrap step.
    ref.watch(deadlineRemindersSyncProvider);
    ref.watch(emergencyCoachAlertSyncProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _DeadlineCard(
          gameweekNumber: deadline.number,
          timeUntilDeadline: untilDeadline,
        ),
        const SizedBox(height: 16),
        _ManagerSummaryCard(data: data),
        const SizedBox(height: 16),
        const _EmergencyCoachSummaryCard(),
        const SizedBox(height: 16),
        if (alerts.isNotEmpty) ...[
          _AlertsCard(alerts: alerts),
          const SizedBox(height: 16),
        ],
        scoreAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (scores) {
            if (scores == null) return const SizedBox.shrink();
            return Column(
              children: [
                _TeamRatingCard(teamCard: scores.$2),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
        _SquadFixtureTicker(
          squad: data.squad,
          playerScores: {
            for (final c in (scoreAsync.valueOrNull?.$1 ?? const []))
              c.playerId: c,
          },
        ),
      ],
    );
  }
}

class _EmergencyCoachSummaryCard extends ConsumerWidget {
  const _EmergencyCoachSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPlan = ref.watch(emergencyCoachPlanProvider);

    return asyncPlan.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (plan) {
        if (plan == null || plan.isAllClear) return const SizedBox.shrink();

        final status = context.status;
        final color = plan.hasCriticalIssues ? status.critical : status.warning;
        return StatusAccentCard(
          accentColor: color,
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(
              plan.hasCriticalIssues
                  ? Icons.error
                  : Icons.warning_amber_rounded,
              color: color,
            ),
            title: Text('${plan.issues.length} issue(s) in your squad'),
            subtitle: const Text('Tap for the full Emergency Coach report'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EmergencyCoachScreen()),
            ),
          ),
        );
      },
    );
  }
}

class _TeamRatingCard extends StatelessWidget {
  final TeamScoreCard teamCard;
  const _TeamRatingCard({required this.teamCard});

  @override
  Widget build(BuildContext context) {
    final ratingColor = _ratingColor(context, teamCard.rating);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            StatNumber(
              value: teamCard.rating.toStringAsFixed(0),
              label: 'RATING',
              valueColor: ratingColor,
              valueStyle: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Team Rating — ${_stanceLabel(teamCard.stance)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    teamCard.reasons.join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _ratingColor(BuildContext context, double rating) {
    final status = context.status;
    if (rating >= 65) return status.good;
    if (rating >= 45) return status.warning;
    return status.critical;
  }

  String _stanceLabel(GameweekStance stance) {
    switch (stance) {
      case GameweekStance.attacking:
        return 'Attacking';
      case GameweekStance.balanced:
        return 'Balanced';
      case GameweekStance.defensive:
        return 'Defensive';
      case GameweekStance.differentialOpportunity:
        return 'Differential opportunity';
    }
  }
}

class _DeadlineCard extends StatelessWidget {
  final int gameweekNumber;
  final Duration timeUntilDeadline;

  const _DeadlineCard({
    required this.gameweekNumber,
    required this.timeUntilDeadline,
  });

  @override
  Widget build(BuildContext context) {
    final isPast = timeUntilDeadline.isNegative;
    final hours = timeUntilDeadline.inHours.abs();
    final minutes = timeUntilDeadline.inMinutes.abs() % 60;
    final status = context.status;

    final accent = isPast
        ? Theme.of(context).colorScheme.outline
        : (hours < 6
            ? status.critical
            : (hours < 48 ? status.warning : status.good));

    return StatusAccentCard(
      accentColor: accent,
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isPast
                  ? 'Gameweek $gameweekNumber deadline has passed'
                  : 'GW$gameweekNumber deadline in ${hours}h ${minutes}m',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagerSummaryCard extends StatelessWidget {
  final DashboardData data;
  const _ManagerSummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final manager = data.manager;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Stat(label: 'TEAM', value: manager.teamName),
            _Stat(label: 'POINTS', value: '${manager.overallPoints}'),
            _Stat(
              label: 'RANK',
              value: manager.overallRank == 0
                  ? '—'
                  : manager.overallRank.toString(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return StatNumber(
      value: value,
      label: label,
      valueStyle: Theme.of(context).textTheme.headlineSmall,
    );
  }
}

class _AlertsCard extends StatelessWidget {
  final List<DashboardSquadPlayer> alerts;
  const _AlertsCard({required this.alerts});

  @override
  Widget build(BuildContext context) {
    final critical = context.status.critical;
    return StatusAccentCard(
      accentColor: critical,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: critical),
              const SizedBox(width: 8),
              Text(
                'Availability alerts',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final alert in alerts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${alert.player.webName} — ${_statusLabel(alert.player.status)}'
                '${alert.player.news != null ? ': ${alert.player.news}' : ''}',
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(String code) {
    switch (code) {
      case 'd':
        return 'Doubtful';
      case 'i':
        return 'Injured';
      case 's':
        return 'Suspended';
      case 'u':
        return 'Unavailable';
      default:
        return code;
    }
  }
}

class _SquadFixtureTicker extends StatelessWidget {
  final List<DashboardSquadPlayer> squad;
  final Map<int, PlayerScoreCard> playerScores;
  const _SquadFixtureTicker(
      {required this.squad, this.playerScores = const {}});

  @override
  Widget build(BuildContext context) {
    final starters = squad.where((p) => p.isStarting).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Next fixture',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox.shrink(),
              ],
            ),
            const SizedBox(height: 8),
            for (final entry in starters)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    if (entry.isCaptain)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.stars,
                            size: 16, color: context.status.featured),
                      ),
                    Expanded(child: Text(entry.player.webName)),
                    if (playerScores[entry.player.id] != null) ...[
                      _RatingBadge(score: playerScores[entry.player.id]!),
                      const SizedBox(width: 6),
                    ],
                    _DifficultyChip(
                        fixture: entry.nextFixture, clubId: entry.club.id),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  final PlayerScoreCard score;
  const _RatingBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: score.rating.reasons.join('\n'),
      child: Text(
        'R${score.rating.value.toStringAsFixed(0)}',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  final Fixture? fixture;
  final int clubId;
  const _DifficultyChip({required this.fixture, required this.clubId});

  @override
  Widget build(BuildContext context) {
    final f = fixture;
    if (f == null) {
      return const Chip(label: Text('—'));
    }
    final isHome = f.homeClubId == clubId;
    final difficulty = isHome ? f.homeDifficulty : f.awayDifficulty;
    final status = context.status;

    final color = switch (difficulty) {
      <= 2 => status.good,
      3 => status.warning,
      _ => status.critical,
    };

    return Chip(
      label: Text('$difficulty'),
      backgroundColor: color.withValues(alpha: 0.18),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
    );
  }
}
