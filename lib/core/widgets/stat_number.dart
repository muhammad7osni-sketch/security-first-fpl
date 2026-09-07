import 'package:flutter/material.dart';

/// A number rendered in the "scoreboard" treatment (Barlow Condensed,
/// bold, tabular figures) with a small caption underneath.
///
/// This is the encoding of the design system's "scoreboard, not
/// spreadsheet" principle: any screen showing a Player Rating, points
/// total, price, or similar headline number should use this instead of
/// a plain `Text` widget, so that number gets the same visual weight
/// everywhere in the app.
class StatNumber extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;
  final TextStyle? valueStyle;

  const StatNumber({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: (valueStyle ?? theme.textTheme.displaySmall)?.copyWith(
            color: valueColor ?? theme.textTheme.displaySmall?.color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
