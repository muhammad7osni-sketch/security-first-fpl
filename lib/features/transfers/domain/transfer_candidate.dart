import '../../../data_providers/models/club.dart';
import '../../../data_providers/models/player.dart';

/// One ranked replacement suggestion for a specific outgoing player,
/// produced by [StatisticsEngine.calculateTransferScore] via
/// `TransfersRepository`. `transferScore` and `expectedPointsGain` are
/// both direct engine outputs — this class never recomputes or
/// re-weights them (plan section 11).
class TransferCandidate {
  final Player player;
  final Club club;
  final double transferScore;
  final double expectedPointsGain;
  final int priceDeltaTenths; // positive = candidate costs more than the outgoing player

  const TransferCandidate({
    required this.player,
    required this.club,
    required this.transferScore,
    required this.expectedPointsGain,
    required this.priceDeltaTenths,
  });
}
