import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../../shared/widgets/section_header.dart';

class DepartmentEntry {
  const DepartmentEntry({
    required this.label,
    required this.icon,
    required this.tint,
    this.imageUrl,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tint;

  /// Photograph for the tile; falls back to the tinted panel when absent.
  final String? imageUrl;

  /// Where the tile goes.
  final VoidCallback? onTap;
}

/// Two-up department tiles with a trailing "All departments".
///
/// Landscape panels rather than the squares the category blocks use: this list
/// runs longer, and a shorter tile keeps the whole department set reachable
/// without a long scroll.
class DepartmentGrid extends StatelessWidget {
  const DepartmentGrid({
    super.key,
    required this.title,
    required this.entries,
    this.leadingIcon,
    this.onSeeAll,
  });

  final String title;
  final IconData? leadingIcon;
  final List<DepartmentEntry> entries;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, leadingIcon: leadingIcon, onSeeAll: onSeeAll),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              // Landscape panel plus its label line.
              childAspectRatio: 1.28,
            ),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final entry = entries[i];
              return InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                onTap: entry.onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fills the cell minus the label, so a larger device
                    // text scale cannot overflow the tile.
                    Expanded(
                      child: ArtworkPanel(
                        icon: entry.icon,
                        tint: entry.tint,
                        imageUrl: entry.imageUrl,
                        iconScale: 0.46,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
