import '../../../core/error/result.dart';
import '../../../data_providers/fantasy_data_provider.dart';
import '../../../data_providers/models/player.dart';
import '../../statistics_engine/data/statistics_repository.dart';
import '../domain/transfer_candidate.dart';

/// Suggests replacements for a specific outgoing squad player.
///
/// Two-stage filtering, deliberately: FPL has ~600 players, and scoring
/// one via the Statistics Engine means an `element-summary` history
/// call (plan section 21's rate-limit caution). Stage 1 filters on free
/// facts already in the bootstrap payload (position, price,
/// availability, raw form) to cut the pool to a small shortlist. Stage 2
/// only then builds engine inputs and runs
/// [StatisticsEngine.calculateTransferScore] for that shortlist plus the
/// outgoing player.
class TransfersRepository {
  final FantasyDataProvider _fantasyDataProvider;
  final StatisticsRepository _statisticsRepository;

  static const _preFilterShortlistSize = 12;

  TransfersRepository(this._fantasyDataProvider, this._statisticsRepository);

  Future<Result<List<TransferCandidate>>> suggestReplacements({
    required Player playerOut,
    required int bankTenths,
    int gameweekHorizon = 3,
    int maxCandidates = 5,
  }) async {
    final playersResult = await _fantasyDataProvider.getPlayers();
    final allPlayers = playersResult.valueOrNull;
    if (allPlayers == null) return Result.err(playersResult.failureOrNull!);

    final clubsResult = await _fantasyDataProvider.getClubs();
    final clubs = clubsResult.valueOrNull;
    if (clubs == null) return Result.err(clubsResult.failureOrNull!);
    final clubsById = {for (final c in clubs) c.id: c};

    final maxAffordableCost = bankTenths + playerOut.nowCostTenths;

    final preFiltered = allPlayers.where((p) {
      if (p.id == playerOut.id) return false;
      if (p.position != playerOut.position) return false;
      if (p.status != 'a') return false;
      if (p.nowCostTenths > maxAffordableCost) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.form.compareTo(a.form));

    final shortlist = preFiltered.take(_preFilterShortlistSize).toList();
    if (shortlist.isEmpty) {
      return Result.ok([]);
    }

    final idsToScore = [playerOut.id, ...shortlist.map((p) => p.id)];
    final inputsResult =
        await _statisticsRepository.buildEngineInputs(idsToScore);
    final inputs = inputsResult.valueOrNull;
    if (inputs == null) return Result.err(inputsResult.failureOrNull!);

    final outInput = inputs[playerOut.id];
    if (outInput == null) {
      return Result.err(const AppFailure(
        AppFailureType.unexpectedResponseShape,
        'Could not build engine input for the outgoing player',
      ));
    }

    final engine = _statisticsRepository.engine;
    final candidates = <TransferCandidate>[];

    for (final candidate in shortlist) {
      final inInput = inputs[candidate.id];
      if (inInput == null) continue;

      final transferScore = engine.calculateTransferScore(
        playerOut: outInput,
        playerIn: inInput,
        gameweekHorizon: gameweekHorizon,
        isPointsHit:
            false, // free-hit assumption; UI can label hit cost separately
      );

      double gain = 0;
      for (var i = 0; i < gameweekHorizon; i++) {
        gain += engine.calculateExpectedPoints(inInput, fixtureIndex: i) -
            engine.calculateExpectedPoints(outInput, fixtureIndex: i);
      }

      final club = clubsById[candidate.clubId];
      if (club == null) continue;

      candidates.add(TransferCandidate(
        player: candidate,
        club: club,
        transferScore: transferScore,
        expectedPointsGain: double.parse(gain.toStringAsFixed(2)),
        priceDeltaTenths: candidate.nowCostTenths - playerOut.nowCostTenths,
      ));
    }

    candidates.sort((a, b) => b.transferScore.compareTo(a.transferScore));
    return Result.ok(candidates.take(maxCandidates).toList());
  }
}
