import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Edge-to-edge strip of promo cards under the search bar.
///
/// Cards are narrower than the viewport so the next one peeks in — the cue
/// that the strip scrolls, without needing arrows or dots.
class PromoRail extends StatelessWidget {
  const PromoRail({super.key, required this.items});

  final List<PromoItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _PromoCard(item: items[i]),
      ),
    );
  }
}

class PromoItem {
  const PromoItem({
    required this.headline,
    required this.caption,
    required this.tint,
  });

  final String headline;
  final String caption;
  final Color tint;
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.item});

  final PromoItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: item.tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            item.headline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            item.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
