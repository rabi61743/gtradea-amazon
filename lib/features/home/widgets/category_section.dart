import 'package:flutter/material.dart';

import '../../../shared/widgets/page_width.dart';

import '../../../shared/widgets/section_header.dart';
import 'category_tile.dart';

/// A category as the home feed models it.
class CategoryEntry {
  const CategoryEntry({
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

/// A titled block of category tiles.
///
/// Non-scrolling and shrink-wrapped: the whole page is one scroll view, so a
/// nested scrollable here would fight it.
class CategorySection extends StatelessWidget {
  const CategorySection({
    super.key,
    required this.title,
    required this.entries,
    this.subtitle,
    this.leadingIcon,
    this.onSeeAll,
  });

  final String title;

  /// Optional qualifier under the title, e.g. a price cap.
  final String? subtitle;
  final IconData? leadingIcon;
  final List<CategoryEntry> entries;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          subtitle: subtitle,
          leadingIcon: leadingIcon,
          onSeeAll: onSeeAll,
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: PageWidth.marginOf(context),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              // Rows tighter than columns, not the other way round: this was
              // the loosest row gap on the page, and vertical space is the one
              // being spent thirteen times down a stacked feed. The 14 across
              // is untouched.
              mainAxisSpacing: 10,
              crossAxisSpacing: 14,
              childAspectRatio: 0.86,
            ),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final entry = entries[i];
              return CategoryTile(
                label: entry.label,
                icon: entry.icon,
                tint: entry.tint,
                imageUrl: entry.imageUrl,
                onTap: entry.onTap,
              );
            },
          ),
        ),
      ],
    );
  }
}
