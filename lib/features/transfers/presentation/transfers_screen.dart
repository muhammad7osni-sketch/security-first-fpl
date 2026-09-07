import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/utils/fpl_launcher.dart';
import '../../dashboard/domain/dashboard_data.dart';
import '../../dashboard/presentation/dashboard_controller.dart';
import '../domain/transfer_candidate.dart';
import '../data/transfers_providers.dart';

/// Transfers screen (plan section 10's Transfer Score, applied). The
/// user picks one of their own 15 to replace; suggestions are ranked by
/// the Statistics Engine's transfer score over a 3-gameweek horizon.
/// Nothing here submits a transfer - the user still makes the change in
/// the official FPL app (plan section 0).
class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});

  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  DashboardSquadPlayer? _selectedOut;
  List<TransferCandidate>? _candidates;
  bool _isLoading = false;
  String? _error;

  Future<void> _loadCandidates(
      DashboardSquadPlayer outPlayer, int bankTenths) async {
    setState(() {
      _selectedOut = outPlayer;
      _isLoading = true;
      _error = null;
      _candidates = null;
    });

    final repo = ref.read(transfersRepositoryProvider);
    final result = await repo.suggestReplacements(
      playerOut: outPlayer.player,
      bankTenths: bankTenths,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      result.when(
        ok: (candidates) => _candidates = candidates,
        err: (AppFailure failure) => _error = failure.message,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncDashboard = ref.watch(dashboardDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Transfers')),
      body: asyncDashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (dashboard) {
          if (dashboard == null) {
            return const Center(child: Text('Link your FPL account first.'));
          }

          return Row(
            children: [
              SizedBox(
                width: 160,
                child: ListView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Your squad',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    for (final p in dashboard.squad)
                      ListTile(
                        dense: true,
                        selected: _selectedOut?.player.id == p.player.id,
                        title: Text(p.player.webName,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '£${p.player.priceMillions.toStringAsFixed(1)}m'),
                        onTap: () => _loadCandidates(
                            p, dashboard.manager.bankTenths.round()),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _selectedOut == null
                    ? const Center(
                        child: Text('Pick a player to see replacement options'))
                    : _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                            ? Center(child: Text(_error!))
                            : _CandidateList(
                                outPlayerName: _selectedOut!.player.webName,
                                candidates: _candidates ?? const [],
                              ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CandidateList extends ConsumerWidget {
  final String outPlayerName;
  final List<TransferCandidate> candidates;
  const _CandidateList({required this.outPlayerName, required this.candidates});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (candidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
            'No affordable same-position replacement found for $outPlayerName.'),
      );
    }

    return Column(
      children: [
        // Header with "Apply on FPL" button
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Replacement suggestions for $outPlayerName',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: () => _showApplyDialog(context, ref),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Apply on FPL'),
              ),
            ],
          ),
        ),
        // Candidates list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final c = candidates[index];
              final priceLabel = c.priceDeltaTenths == 0
                  ? 'Same price'
                  : c.priceDeltaTenths > 0
                      ? '+£${(c.priceDeltaTenths / 10).toStringAsFixed(1)}m'
                      : '-£${(-c.priceDeltaTenths / 10).toStringAsFixed(1)}m';

              return Card(
                child: ListTile(
                  title: Text('${c.player.webName} (${c.club.shortName})'),
                  subtitle: Text(
                    'Transfer score ${c.transferScore.toStringAsFixed(1)} · '
                    '+${c.expectedPointsGain.toStringAsFixed(1)} pts over the horizon · $priceLabel',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: () => FplLauncher.openPlayer(c.player.id),
                    tooltip: 'View on FPL',
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showApplyDialog(BuildContext context, WidgetRef ref) async {
    final topCandidate = candidates.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply Transfer on FPL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SquadIQ will open the official FPL transfers page in your browser.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Top recommendation:',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '❌ OUT: $outPlayerName',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '✅ IN: ${topCandidate.player.webName} (${topCandidate.club.shortName})',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Expected gain: +${topCandidate.expectedPointsGain.toStringAsFixed(1)} pts',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'You\'ll make the final decision on the FPL website.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open FPL'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success = await FplLauncher.openTransfers();
      if (!success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open FPL website')),
        );
      } else {
        // Trigger refresh when user returns (handled by lifecycle detector)
        ref.invalidate(dashboardDataProvider);
      }
    }
  }
}
