import 'package:flutter/material.dart';

/// A card with a 4px colored bar down the left edge instead of a
/// tinted background.
///
/// Encodes the design system's principle #4: status is communicated
/// with an accent bar, not a full-card color wash. This matters most
/// in lists — a list of five issues each with a different pastel
/// background reads as visual noise; five cards with a thin colored
/// edge read as a scannable list with a status hint.
///
/// Pass the color from `context.status` (see `status_colors.dart`),
/// never a raw `Colors.x` value, so the meaning stays consistent with
/// the rest of the app.
class StatusAccentCard extends StatelessWidget {
  final Color accentColor;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const StatusAccentCard({
    super.key,
    required this.accentColor,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accentColor),
            Expanded(child: Padding(padding: padding, child: child)),
          ],
        ),
      ),
    );
  }
}
