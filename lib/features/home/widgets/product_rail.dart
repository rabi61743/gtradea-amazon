import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/widgets/artwork_panel.dart';

/// A product as the home rails render it.
class ProductItem {
  const ProductItem({
    required this.title,
    required this.price,
    required this.rating,
    required this.reviewCount,
    required this.icon,
    required this.tint,
    this.listPrice,
  });

  final String title;
  final num price;

  /// Struck-through "was" price. Only rendered when it is genuinely above
  /// [price] — a crossed-out number that is not a saving is a false claim.
  final num? listPrice;

  final double rating;
  final int reviewCount;
  final IconData icon;
  final Color tint;
}

/// Horizontally scrolling product cards under a section heading.
class ProductRail extends StatelessWidget {
  const ProductRail({
    super.key,
    required this.title,
    required this.items,
    this.onSeeAll,
  });

  final String title;
  final List<ProductItem> items;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
              if (onSeeAll != null)
                TextButton(onPressed: onSeeAll, child: const Text('See all')),
            ],
          ),
        ),
        SizedBox(
          // Grows with the device text scale. The card is title + rating +
          // price under a square panel, so a fixed height overflows on a
          // phone with larger text -- the same trap the category tiles hit.
          height: 268 *
              MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _ProductCard(item: items[i]),
          ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.item});

  final ProductItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = item.listPrice;
    final struck = (list != null && list > item.price) ? list : null;

    return SizedBox(
      width: 156,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ArtworkPanel(icon: item.icon, tint: item.tint, iconScale: 0.38),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.25),
          ),
          const SizedBox(height: 6),
          _Stars(rating: item.rating, count: item.reviewCount),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatRupees(item.price),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
              if (struck != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    formatRupees(struck),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Five stars with the rating filled in, plus the review count.
class _Stars extends StatelessWidget {
  const _Stars({required this.rating, required this.count});

  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star
                : (rating >= i - 0.5 ? Icons.star_half : Icons.star_border),
            size: 13,
            color: AppColors.star,
          ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$count',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Rupees with thousands separators, e.g. `Rs. 27,590`.
///
/// Hand-rolled rather than pulling in `intl` for one call site; NPR is shown
/// without decimals across the GtradeA storefront.
String formatRupees(num value) {
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return 'Rs. $buffer';
}
