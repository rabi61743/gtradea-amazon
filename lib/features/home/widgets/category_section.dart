import 'package:flutter/material.dart';

import '../../../shared/widgets/section_header.dart';
import 'category_tile.dart';

/// A category as the home feed models it.
class CategoryEntry {
  const CategoryEntry({
    required this.label,
    required this.icon,
    required this.tint,
  });

  final String label;
  final IconData icon;
  final Color tint;
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
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
                onTap: () {},
              );
            },
          ),
        ),
      ],
    );
  }
}
