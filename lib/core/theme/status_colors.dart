import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Semantic status colors, available anywhere via
/// `Theme.of(context).extension<StatusColors>()!` or the `context.status`
/// shortcut below.
///
/// This is the single enforcement point for a rule worth keeping:
/// green/gold/amber/red/blue must mean the same thing on every screen.
/// Before this existed, screens each hardcoded their own
/// `Colors.green`/`Colors.amber`/`Colors.red` - harmless individually,
/// but it meant "green" on the Dashboard and "green" on Fixtures had no
/// guaranteed relationship. Add new semantic colors here, not as a new
/// hardcoded `Colors.x` in a widget.
class StatusColors extends ThemeExtension<StatusColors> {
  final Color good; // available, low difficulty, positive delta
  final Color warning; // doubtful, blank fixture, medium difficulty
  final Color critical; // injured/suspended/unavailable, high difficulty
  final Color info; // differential, neutral note
  final Color featured; // captaincy / highlighted moment

  const StatusColors({
    required this.good,
    required this.warning,
    required this.critical,
    required this.info,
    required this.featured,
  });

  static const matchday = StatusColors(
    good: AppColors.turfGreen,
    warning: AppColors.cautionAmber,
    critical: AppColors.redCard,
    info: AppColors.assistBlue,
    featured: AppColors.armbandGold,
  );

  @override
  StatusColors copyWith({
    Color? good,
    Color? warning,
    Color? critical,
    Color? info,
    Color? featured,
  }) {
    return StatusColors(
      good: good ?? this.good,
      warning: warning ?? this.warning,
      critical: critical ?? this.critical,
      info: info ?? this.info,
      featured: featured ?? this.featured,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      good: Color.lerp(good, other.good, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      critical: Color.lerp(critical, other.critical, t)!,
      info: Color.lerp(info, other.info, t)!,
      featured: Color.lerp(featured, other.featured, t)!,
    );
  }
}

/// Convenience getter: `context.status.good` instead of the full
/// `Theme.of(context).extension<StatusColors>()!.good`.
extension StatusColorsContext on BuildContext {
  StatusColors get status => Theme.of(this).extension<StatusColors>()!;
}
