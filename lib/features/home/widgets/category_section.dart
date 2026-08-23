import 'package:flutter/material.dart';

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

/// A titled block of category tiles with a trailing "Shop more".
///
/// Non-scrolling and shrink-wrapped: the whole page is one scroll view, so a
/// nested scrollable here would fight it.
class CategorySection extends StatelessWidget {
  const CategorySection({
    super.key,
    required this.title,
    required this.entries,
    this.onShopMore,
  });

  final String title;
  final List<CategoryEntry> entries;
  final VoidCallback? onShopMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 14),
          child: Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
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
              // Room for the square panel plus its label line.
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
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
          child: TextButton(
            onPressed: onShopMore,
            child: const Text('Shop more'),
          ),
        ),
      ],
    );
  }
}
