import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';

class DepartmentEntry {
  const DepartmentEntry({
    required this.label,
    required this.icon,
    required this.tint,
  });

  final String label;
  final IconData icon;
  final Color tint;
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
    this.onSeeAll,
  });

  final String title;
  final List<DepartmentEntry> entries;
  final VoidCallback? onSeeAll;

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
                onTap: () {},
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ArtworkPanel(
                      icon: entry.icon,
                      tint: entry.tint,
                      aspectRatio: 16 / 9,
                      iconScale: 0.46,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
          child: TextButton(
            onPressed: onSeeAll,
            child: const Text('All departments'),
          ),
        ),
      ],
    );
  }
}
