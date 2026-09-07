import '../../../core/error/result.dart';
import '../../../data_providers/fantasy_data_provider.dart';
import '../../../data_providers/models/fixture.dart';
import '../../../data_providers/models/player.dart';
import '../domain/models/engine_inputs.dart';
import '../domain/models/engine_outputs.dart';
import '../domain/statistics_engine.dart';

/// Bridges the read-only [FantasyDataProvider] to the pure
/// [StatisticsEngine]: fetches raw facts, shapes them into
/// [PlayerEngineInput], and returns the engine's outputs. This class
/// does no scoring itself — see [StatisticsEngine]'s doc comment for why
/// that separation is enforced (plan section 11).
class StatisticsRepository {
  final FantasyDataProvider _fantasyDataProvider;
  final StatisticsEngine _engine;
  static const _recentGwWindow = 6;
  static const _fixtureHorizon = 5;

  StatisticsRepository(
    this._fantasyDataProvider, {
    StatisticsEngine engine = const StatisticsEngine(),
  }) : _engine = engine;

  /// Builds score cards for an arbitrary list of player IDs (e.g. a
  /// user's 15-man squad, or a shortlist of transfer targets).
  Future<Result<List<PlayerScoreCard>>> scorePlayerIds(
    List<int> playerIds,
  ) async {
    final playersResult = await _fantasyDataProvider.getPlayers();
    final players = playersResult.valueOrNull;
    if (players == null) return Result.err(playersResult.failureOrNull!);

    final fixturesResult = await _fantasyDataProvider.getFixtures();
    final fixtures = fixturesResult.valueOrNull ?? const <Fixture>[];

    final playersById = {for (final p in players) p.id: p};
    final cards = <PlayerScoreCard>[];

    for (final id in playerIds) {
      final player = playersById[id];
      if (player == null) continue;

      final input = await _buildInput(player, players, fixtures);
      cards.add(_engine.buildScoreCard(input));
    }

    return Result.ok(cards);
  }

  /// Convenience for the dashboard/emergency-coach use case: score every
  /// starting-XI player and return both individual cards and the
  /// aggregate [TeamScoreCard].
  Future<Result<(List<PlayerScoreCard>, TeamScoreCard)>> scoreStartingXi(
    List<int> startingPlayerIds,
  ) async {
    final cardsResult = await scorePlayerIds(startingPlayerIds);
    final cards = cardsResult.valueOrNull;
    if (cards == null) return Result.err(cardsResult.failureOrNull!);

    final team = _engine.buildTeamScoreCard(cards);
    return Result.ok((cards, team));
  }

  /// Exposes raw [PlayerEngineInput] construction for features that need
  /// engine methods other than the score-card bundle — e.g. Transfers
  /// needs [StatisticsEngine.calculateTransferScore], which takes two
  /// inputs directly rather than two pre-built cards.
  Future<Result<Map<int, PlayerEngineInput>>> buildEngineInputs(
    List<int> playerIds,
  ) async {
    final playersResult = await _fantasyDataProvider.getPlayers();
    final players = playersResult.valueOrNull;
    if (players == null) return Result.err(playersResult.failureOrNull!);

    final fixturesResult = await _fantasyDataProvider.getFixtures();
    final fixtures = fixturesResult.valueOrNull ?? const <Fixture>[];

    final playersById = {for (final p in players) p.id: p};
    final inputs = <int, PlayerEngineInput>{};

    for (final id in playerIds) {
      final player = playersById[id];
      if (player == null) continue;
      inputs[id] = await _buildInput(player, players, fixtures);
    }

    return Result.ok(inputs);
  }

  /// The engine instance backing this repository — exposed so callers
  /// building their own [PlayerEngineInput]s (e.g. Transfers comparing
  /// an out/in pair) can invoke engine methods without constructing a
  /// second [StatisticsEngine] elsewhere.
  StatisticsEngine get engine => _engine;

  Future<PlayerEngineInput> _buildInput(
    Player player,
    List<Player> allPlayers,
    List<Fixture> allFixtures,
  ) async {
    final historyResult = await _fantasyDataProvider.getPlayerHistory(player.id);
    final history = historyResult.valueOrNull ?? const [];
    final recentHistory = history.length > _recentGwWindow
        ? history.sublist(history.length - _recentGwWindow)
        : history;

    final recentMinutes = recentHistory.isNotEmpty
        ? recentHistory.map((h) => h.minutes).toList()
        : [player.minutesLastGw];

    double? xgi90;
    final withXg = recentHistory.where(
      (h) => h.expectedGoals != null && h.expectedAssists != null && h.minutes > 0,
    );
    if (withXg.isNotEmpty) {
      final totalXgi = withXg
          .map((h) => h.expectedGoals! + h.expectedAssists!)
          .reduce((a, b) => a + b);
      final totalMinutes = withXg.map((h) => h.minutes).reduce((a, b) => a + b);
      xgi90 = totalMinutes > 0 ? (totalXgi / totalMinutes) * 90 : null;
    }

    final upcoming = allFixtures
        .where((f) => f.homeClubId == player.clubId || f.awayClubId == player.clubId)
        .take(_fixtureHorizon)
        .map((f) => f.homeClubId == player.clubId ? f.homeDifficulty : f.awayDifficulty)
        .toList();

    final competitorCount = allPlayers
        .where((p) =>
            p.id != player.id &&
            p.clubId == player.clubId &&
            p.position == player.position &&
            p.status == 'a' &&
            p.minutesLastGw > 0)
        .length;

    return PlayerEngineInput(
      player: player,
      form: player.form,
      recentMinutes: recentMinutes,
      upcomingFixtureDifficulty: upcoming,
      xgi90: xgi90,
      positionalCompetitorCount: competitorCount,
    );
  }
}
