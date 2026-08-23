import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// One category: a square artwork panel with its label underneath.
///
/// The panel is a two-stop gradient behind an icon rather than a photograph.
/// This app has no image pipeline yet, and a tinted panel reads as deliberate
/// where a grey placeholder box reads as missing. Swapping in real imagery
/// later only touches this widget.
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.label,
    required this.icon,
    required this.tint,
    this.onTap,
  });

  final String label;
  final IconData icon;

  /// Seed colour for the panel; the gradient is derived from it so a caller
  /// only picks one value per category.
  final Color tint;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
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
                // Sized off the panel rather than fixed: the icon stands in for
                  // product photography, so it has to carry the tile.
                  child: LayoutBuilder(
                    builder: (context, constraints) => Icon(
                      icon,
                      size: constraints.maxWidth * 0.42,
                      color: tint,
                    ),
                  ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
