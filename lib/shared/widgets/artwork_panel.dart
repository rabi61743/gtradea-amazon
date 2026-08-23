import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The tinted panel that stands in for product photography.
///
/// One implementation shared by category tiles, department tiles and product
/// cards so they cannot drift apart. The icon is sized from the panel rather
/// than fixed, because these panels range from a 190pt square to a short
/// landscape strip and a constant would look lost in one and crowded in the
/// other.
///
/// When real imagery arrives it replaces the body of this widget and nothing
/// else has to change.
class ArtworkPanel extends StatelessWidget {
  const ArtworkPanel({
    super.key,
    required this.icon,
    required this.tint,
    this.aspectRatio = 1,
    this.iconScale = 0.42,
  });

  final IconData icon;
  final Color tint;
  final double aspectRatio;

  /// Icon size as a fraction of the panel's shorter side.
  final double iconScale;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tint.withValues(alpha: 0.28),
              tint.withValues(alpha: 0.10),
            ],
          ),
        ),
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final shorter = constraints.maxWidth < constraints.maxHeight
                  ? constraints.maxWidth
                  : constraints.maxHeight;
              return Icon(icon, size: shorter * iconScale, color: tint);
            },
          ),
        ),
      ),
    );
  }
}
