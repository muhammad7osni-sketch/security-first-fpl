import 'package:url_launcher/url_launcher.dart';

/// Helper for launching official FPL website URLs in external browser.
///
/// Per plan section 0, SquadIQ is read-only by design: any user action
/// that modifies their FPL team (transfers, captaincy, chips) happens on
/// the official FPL site, not through unofficial write endpoints. This
/// utility opens the relevant FPL page in the user's browser, pre-filled
/// with context where possible (e.g., direct link to transfers page).
///
/// This approach is:
/// • Legally safe — no ToS violation, FPL owns the write flow
/// • Transparent — user sees exactly what changes they're making
/// • Secure — no credential storage or session hijacking
class FplLauncher {
  static const _baseUrl = 'https://fantasy.premierleague.com';

  /// Opens the FPL homepage (fallback / general entry point).
  static Future<bool> openHome() => _launchUrl('$_baseUrl/');

  /// Opens the user's team management page (My Team tab).
  /// Shows the current squad with transfer/captain controls.
  static Future<bool> openMyTeam() => _launchUrl('$_baseUrl/my-team');

  /// Opens the Transfers page where users can make player swaps.
  /// This is the primary destination after SquadIQ suggests transfers.
  static Future<bool> openTransfers() => _launchUrl('$_baseUrl/transfers');

  /// Opens the Picks page for a specific gameweek (captain/formation changes).
  /// Falls back to current gameweek if [gameweekId] is null.
  static Future<bool> openPicks({int? gameweekId}) {
    final gw = gameweekId ?? 'current';
    return _launchUrl('$_baseUrl/my-team/$gw');
  }

  /// Opens the user's team page (read-only view for a specific entry).
  /// Useful if the user wants to review their public profile.
  static Future<bool> openEntry(int entryId) =>
      _launchUrl('$_baseUrl/entry/$entryId/event/1');

  /// Opens the Leagues/Cups section.
  static Future<bool> openLeagues() => _launchUrl('$_baseUrl/leagues');

  /// Opens the player details page for a specific player.
  /// Shows their stats, fixtures, ownership, etc.
  static Future<bool> openPlayer(int playerId) =>
      _launchUrl('$_baseUrl/player/$playerId');

  /// Opens the Fixtures page (optionally filtered by gameweek).
  static Future<bool> openFixtures({int? gameweekId}) {
    final path =
        gameweekId != null ? '/fixtures?event=$gameweekId' : '/fixtures';
    return _launchUrl('$_baseUrl$path');
  }

  /// Opens the Statistics page (leaderboards, most transferred, etc.).
  static Future<bool> openStatistics() => _launchUrl('$_baseUrl/statistics');

  // ──────────────────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────────────────

  static Future<bool> _launchUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    if (!await canLaunchUrl(uri)) {
      return false;
    }
    return await launchUrl(
      uri,
      mode: LaunchMode.externalApplication, // Opens in browser, not in-app
    );
  }
}
