import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';

/// One tile inside a [DealGroup]: a category shortcut with a price teaser
/// rather than a specific product.
class DealItem {
  const DealItem({
    required this.label,
    required this.teaser,
    required this.icon,
    required this.tint,
    this.imageUrl,
  });

  final String label;

  /// Price framing, e.g. "From Rs. 99" or "Under Rs. 399". Deliberately a
  /// string: these are marketing bands, not a product's actual price, and
  /// formatting them as money would imply a precision they do not have.
  final String teaser;

  final IconData icon;
  final Color tint;

  /// Photograph for the tile; falls back to the tinted panel when absent.
  final String? imageUrl;
}

/// A titled block sitting on its own tinted card.
///
/// Used where a group of offers belongs together and should read as one unit --
/// a seasonal campaign, or a set of shortcuts -- rather than as another flat
/// section of the feed. The tint is the caller's, so a festival block and an
/// everyday block are visibly different things.
class DealGroup extends StatelessWidget {
  const DealGroup({
    super.key,
    required this.title,
    required this.items,
    required this.tint,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<DealItem> items;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint.withValues(alpha: 0.30), tint.withValues(alpha: 0.12)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _DealCard(item: items[i]),
          ),
        ],
      ),
    );
  }
}

class _DealCard extends StatelessWidget {
  const _DealCard({required this.item});

  final DealItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ArtworkPanel(
                  icon: item.icon,
                  tint: item.tint,
                  imageUrl: item.imageUrl,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 2),
              Text(
                item.teaser,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
