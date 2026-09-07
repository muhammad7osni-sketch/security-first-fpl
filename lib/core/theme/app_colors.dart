import 'package:flutter/material.dart';

/// SquadIQ's color palette — "under the floodlights."
///
/// Design rationale (see also `docs` note in `app_theme.dart`): FPL
/// management happens at night after real matches, checking a screen
/// while the actual pitch is still lit up. The palette leans into that
/// rather than a generic light SaaS look — a dark, slightly green-black
/// base so the functional status colors (green/gold/red) read with the
/// same punch a stadium scoreboard has, instead of competing with a
/// bright white background.
///
/// Every color here is named for what it *means* in the product, not
/// just its hue — `criticalRed` is used in exactly one situation
/// (a critical Emergency Coach issue), `armbandGold` in exactly one
/// (captaincy), etc. Keep that discipline when adding new colors: a
/// color that means three different things in three screens defeats
/// the point of a semantic palette.
class AppColors {
  AppColors._();

  // ---- Base surfaces ----
  /// Page background — deep pitch-under-lights green-black, not pure
  /// black. Pure black reads as "OLED battery saver," this reads as
  /// "stadium at night."
  static const nightPitch = Color(0xFF0D1B14);

  /// Card/sheet surface — one step lighter than the page background so
  /// cards separate from it without needing a drop shadow.
  static const turfSurface = Color(0xFF16261D);

  /// A second, slightly lighter surface tier for nested content
  /// (e.g. a card inside a card, or a selected list tile).
  static const turfSurfaceRaised = Color(0xFF1F3327);

  /// Hairline dividers/borders — a muted green-grey, never pure white
  /// or pure grey, so borders still feel like part of the same world.
  static const hairline = Color(0xFF2A3D30);

  // ---- Brand / primary ----
  /// Turf Green — the primary brand color. Used for primary actions,
  /// the "available/good" status, and anything that should read as
  /// "on brand" rather than carrying a specific status meaning.
  static const turfGreen = Color(0xFF2FCB6E);
  static const turfGreenDim = Color(0xFF1F8F4D);

  // ---- Status colors (functional, not decorative) ----
  /// Armband Gold — captaincy and "featured/highlighted" moments only.
  /// This is the one warm accent in an otherwise cool palette, so it
  /// should stay rare enough to keep meaning "captain."
  static const armbandGold = Color(0xFFF5B914);

  /// Red Card — critical issues only (an unavailable starter, a
  /// captain flagged out). Never used for plain negative numbers or
  /// generic errors that aren't squad-critical.
  static const redCard = Color(0xFFE63946);

  /// Caution amber — warnings that aren't yet critical (doubtful
  /// player, blank-fixture starter).
  static const cautionAmber = Color(0xFFE8A33D);

  /// Assist Blue — informational/differential accent (a low-ownership
  /// pick, a neutral info banner). The one cool accent distinct from
  /// the brand green, used sparingly for "worth noting" rather than
  /// "good" or "bad."
  static const assistBlue = Color(0xFF38BDF8);

  // ---- Text ----
  static const textPrimary = Color(0xFFF3F7F4);
  static const textSecondary = Color(0xFFA8B8AD);
  static const textDisabled = Color(0xFF5C6E61);
}
