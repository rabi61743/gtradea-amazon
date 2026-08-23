import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The tinted panel that stands in for product photography.
///
/// One implementation shared by category tiles, department tiles and product
/// cards so they cannot drift apart. The icon is sized from the panel rather
/// than fixed, because these panels range from a large square to a short
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
    this.aspectRatio,
    this.iconScale = 0.42,
  });

  final IconData icon;
  final Color tint;

  /// Null fills whatever space the parent gives, which is what keeps a tile
  /// from overflowing when the device's text scale makes the label taller
  /// than the layout assumed. Pass a ratio only where the panel drives the
  /// size rather than the other way round.
  final double? aspectRatio;

  /// Icon size as a fraction of the panel's shorter side.
  final double iconScale;

  @override
  Widget build(BuildContext context) {
    final panel = DecoratedBox(
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
    );

    final ratio = aspectRatio;
    return ratio == null ? panel : AspectRatio(aspectRatio: ratio, child: panel);
  }
}
