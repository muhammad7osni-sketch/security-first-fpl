import '../../../data_providers/models/club.dart';
import '../../../data_providers/models/fixture.dart';
import '../../../data_providers/models/gameweek.dart';
import '../../../data_providers/models/manager_entry.dart';
import '../../../data_providers/models/player.dart';

/// A squad player enriched with the two things the Dashboard actually
/// needs to show at a glance: their next fixture difficulty and whether
/// they're an availability risk. This is deliberately NOT the full
/// Statistics Engine output (Player Rating / Expected Points / Rotation
/// Risk score) — that's MVP2 (plan section 15); this is just the raw,
/// explainable facts a manager would want on the home screen today.
class DashboardSquadPlayer {
  final Player player;
  final Club club;
  final bool isStarting;
  final bool isCaptain;
  final bool isViceCaptain;
  final Fixture? nextFixture;

  const DashboardSquadPlayer({
    required this.player,
    required this.club,
    required this.isStarting,
    required this.isCaptain,
    required this.isViceCaptain,
    required this.nextFixture,
  });

  /// FPL's `status` flag: 'a' = available. Anything else is worth
  /// surfacing on the dashboard per plan section 12 (injury/suspension
  /// alerts) — this is the free baseline signal, not a replacement for
  /// the RotoWire/Sportmonks feed planned in section 6.
  bool get isAvailabilityRisk => player.status != 'a';
}

/// Everything the single-screen Dashboard (plan section 2: "شاشة واحدة،
/// مفيش تنقل زيادة") needs, pre-assembled by [DashboardRepository].
class DashboardData {
  final Gameweek currentGameweek;
  final Gameweek? nextGameweek;
  final ManagerEntry manager;
  final List<DashboardSquadPlayer> squad;

  const DashboardData({
    required this.currentGameweek,
    required this.nextGameweek,
    required this.manager,
    required this.squad,
  });

  /// The deadline the countdown/trigger system (plan section 3) cares
  /// about: the *next* upcoming gameweek's deadline if one exists,
  /// otherwise the current one (covers the brief window right after a
  /// deadline before FPL flips `is_current`).
  Gameweek get deadlineGameweek => nextGameweek ?? currentGameweek;

  List<DashboardSquadPlayer> get availabilityAlerts =>
      squad.where((p) => p.isAvailabilityRisk).toList();

  DashboardSquadPlayer? get captain =>
      squad.where((p) => p.isCaptain).firstOrElseNull;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrElseNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
