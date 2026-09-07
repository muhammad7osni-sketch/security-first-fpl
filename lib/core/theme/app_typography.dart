import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Two typefaces, two clearly distinct jobs (per the frontend-design
/// skill's guidance: don't mix families without a reason).
///
/// - **Barlow Condensed** (bold/black) for anything that should read
///   like a stadium scoreboard or broadcast graphic: Player Ratings,
///   points totals, prices, countdown numbers, screen titles. Condensed
///   letterforms let big numbers sit in tight spaces without dominating
///   the layout the way a wide display face would.
/// - **Inter** for everything else: body copy, list items, form labels.
///   Chosen specifically for its tabular figures - prices and points
///   in a list stay vertically aligned digit-for-digit, which matters
///   in a stats-dense app like this one.
///
/// PRODUCTION NOTE: `google_fonts` fetches font files from Google's CDN
/// at runtime by default, which means an external network dependency
/// and a request to Google for every first load. Before shipping,
/// consider bundling both fonts as local assets instead (the
/// `google_fonts` package supports this via `GoogleFonts.config` +
/// pubspec assets) - avoids the runtime fetch and any associated
/// privacy/GDPR consideration for EU users.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(ColorScheme colorScheme) {
    final base = GoogleFonts.interTextTheme();
    final condensed = GoogleFonts.barlowCondensedTextTheme();

    return base.copyWith(
          // Scoreboard numerals: gameweek countdown, team rating, prices.
          // Tabular figures here specifically, so digit-heavy numbers
          // (prices, points) don't jitter in width as they update.
          displayLarge: condensed.displayLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 57,
            letterSpacing: 0,
            color: AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          displayMedium: condensed.displayMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 40,
            color: AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          displaySmall: condensed.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 30,
            color: AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          headlineLarge: condensed.headlineLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          headlineMedium: condensed.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          headlineSmall: condensed.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          titleLarge: condensed.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          titleSmall: base.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          bodyLarge: base.bodyLarge?.copyWith(color: AppColors.textPrimary),
          bodyMedium: base.bodyMedium?.copyWith(color: AppColors.textPrimary),
          bodySmall: base.bodySmall?.copyWith(color: AppColors.textSecondary),
          labelLarge: base.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          labelMedium: base.labelMedium?.copyWith(color: AppColors.textSecondary),
          labelSmall: base.labelSmall?.copyWith(color: AppColors.textSecondary),
        );
  }
}
