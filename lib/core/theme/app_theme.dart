import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';
import 'status_colors.dart';

/// SquadIQ's visual identity: "Matchday" - a dark, floodlit-pitch base
/// with functional status colors borrowed from things a football fan
/// already reads instinctively (a captain's armband, a red card, the
/// turf itself).
///
/// # Design plan (kept here, not just in a design doc, so the rationale
/// travels with the code)
///
/// **Color** - see `app_colors.dart` for the full named palette.
/// **Type** - see `app_typography.dart`: Barlow Condensed for
///   scoreboard-style numbers, Inter for body/data.
/// **Layout** - flat surfaces over drop shadows (a `hairline` border
///   does the separation work instead); minimal 8-12px corner radii,
///   not the fully-rounded "soft app" look; status is communicated with
///   a 4px left-edge accent bar on a card rather than tinting the whole
///   card background, so multiple statuses can sit in a list without
///   turning it into a wall of color blocks.
/// **Principles**:
///   1. Scoreboard, not spreadsheet - key numbers get large condensed
///      treatment, not small table cells.
///   2. Status colors are functional, defined once in `StatusColors`,
///      and mean the same thing on every screen.
///   3. Dark "under the floodlights" base so accent colors carry real
///      visual weight instead of competing with a bright background.
///   4. Left-edge accent bars over whole-card color washes - avoids the
///      generic "every card is a different pastel" SaaS look.
class AppTheme {
  AppTheme._();

  static ThemeData get matchday {
    const colorScheme = ColorScheme.dark(
      brightness: Brightness.dark,
      primary: AppColors.turfGreen,
      onPrimary: AppColors.nightPitch,
      primaryContainer: AppColors.turfGreenDim,
      onPrimaryContainer: AppColors.textPrimary,
      secondary: AppColors.armbandGold,
      onSecondary: AppColors.nightPitch,
      surface: AppColors.turfSurface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.turfSurfaceRaised,
      error: AppColors.redCard,
      onError: AppColors.textPrimary,
      outline: AppColors.hairline,
    );

    final textTheme = AppTypography.textTheme(colorScheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.nightPitch,
      textTheme: textTheme,
      fontFamily: textTheme.bodyMedium?.fontFamily,
      extensions: const [StatusColors.matchday],

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.nightPitch,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(
          bottom: BorderSide(color: AppColors.hairline, width: 1),
        ),
        titleTextStyle: textTheme.headlineSmall,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),

      cardTheme: CardThemeData(
        color: AppColors.turfSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.hairline, width: 1),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.turfSurfaceRaised,
        labelStyle: textTheme.labelMedium?.copyWith(color: AppColors.textPrimary),
        side: const BorderSide(color: AppColors.hairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.turfGreen,
          foregroundColor: AppColors.nightPitch,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.turfGreen,
          side: const BorderSide(color: AppColors.turfGreen),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.turfGreen),
      ),

      iconTheme: const IconThemeData(color: AppColors.textPrimary),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.turfSurfaceRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.turfGreen, width: 1.5),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.turfGreen
              : AppColors.textDisabled,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.turfGreenDim
              : AppColors.turfSurfaceRaised,
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.turfGreen,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.turfSurfaceRaised,
        contentTextStyle: textTheme.bodyMedium,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
