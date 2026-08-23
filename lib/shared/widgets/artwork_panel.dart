import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Artwork for a tile: a photograph when one is available, and a tinted panel
/// with an icon when it is not.
///
/// One implementation shared by category tiles, department tiles, deal cards
/// and product cards so they cannot drift apart.
///
/// The tinted panel is not a placeholder that got left in -- it is the loading
/// and failure state. A shopper on a slow Nepali connection sees a coloured
/// panel rather than a grey hole, and a dead image URL degrades to the same
/// thing instead of a broken-image glyph.
class ArtworkPanel extends StatelessWidget {
  const ArtworkPanel({
    super.key,
    required this.icon,
    required this.tint,
    this.imageUrl,
    this.aspectRatio,
    this.iconScale = 0.42,
  });

  final IconData icon;
  final Color tint;

  /// Photograph to show in place of the icon. Null falls back to the panel.
  final String? imageUrl;

  /// Null fills whatever space the parent gives, which is what keeps a tile
  /// from overflowing when the device's text scale makes the label taller
  /// than the layout assumed. Pass a ratio only where the panel drives the
  /// size rather than the other way round.
  final double? aspectRatio;

  /// Icon size as a fraction of the panel's shorter side.
  final double iconScale;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;

    final content = url == null || url.isEmpty
        ? _fallback()
        : Image.network(
            url,
            fit: BoxFit.cover,
            // Fade in so a late-arriving image does not snap into place.
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 220),
                child: child,
              );
            },
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : _fallback(),
            errorBuilder: (context, error, stack) => _fallback(),
          );

    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
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
        child: SizedBox.expand(child: content),
      ),
    );

    final ratio = aspectRatio;
    return ratio == null ? panel : AspectRatio(aspectRatio: ratio, child: panel);
  }

  Widget _fallback() => Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shorter = constraints.maxWidth < constraints.maxHeight
                ? constraints.maxWidth
                : constraints.maxHeight;
            return Icon(icon, size: shorter * iconScale, color: tint);
          },
        ),
      );
}
