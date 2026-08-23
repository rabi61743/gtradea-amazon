import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';

/// One category: an artwork panel with its label underneath.
///
/// The panel takes whatever height the label leaves rather than claiming a
/// fixed square. A square panel plus a label overflows the grid cell as soon
/// as the device's text scale is a little above the layout's assumption --
/// which is exactly what happened on a real phone, at 1.2 pixels.
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
        children: [
          Expanded(child: ArtworkPanel(icon: icon, tint: tint)),
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
