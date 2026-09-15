import 'package:flutter/material.dart';

import '../../../shared/widgets/page_width.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../../shared/widgets/section_header.dart';

/// A product as the home rails render it.
class ProductItem {
  const ProductItem({
    required this.title,
    required this.price,
    required this.rating,
    required this.reviewCount,
    required this.icon,
    required this.tint,
    this.imageUrl,
    this.listPrice,
    this.onTap,
    this.footnote,
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

  /// Photograph for the tile; falls back to the tinted panel when absent.
  final String? imageUrl;

  /// What tapping the card does. Supplied by whoever built the list, because
  /// only they know which catalogue row this card stands for.
  final VoidCallback? onTap;

  /// A small fact shown where the rating would be, for catalogues that do not
  /// have ratings. Units sold, usually.
  final String? footnote;
}

/// Horizontally scrolling product cards under a section heading.
class ProductRail extends StatelessWidget {
  const ProductRail({
    super.key,
    required this.title,
    required this.items,
    this.leadingIcon,
    this.onSeeAll,
  });

  final String title;
  final IconData? leadingIcon;
  final List<ProductItem> items;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Skipped when there is nothing to put in it. A rail under a heading
        // that already names it -- the department picker does -- would say the
        // same word twice, and an empty SectionHeader still takes its padding.
        if (title.isNotEmpty || onSeeAll != null)
          SectionHeader(
            title: title,
            leadingIcon: leadingIcon,
            onSeeAll: onSeeAll,
          ),
        SizedBox(
          // Grows with the device text scale. The card is title + rating +
          // price under a square panel, so a fixed height overflows on a
          // phone with larger text -- the same trap the category tiles hit.
          height:
              268 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // The rail itself still runs edge to edge -- a card should be
            // able to scroll off the screen rather than stopping short of it
            // -- but its first and last card sit on the page's own margin.
            padding: EdgeInsets.symmetric(
              horizontal: PageWidth.marginOf(context),
            ),
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
      child: InkWell(
        onTap: item.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Square, not Expanded: this card stacks in an unbounded column,
            // so the panel has to declare its own height.
            ArtworkPanel(
              icon: item.icon,
              tint: item.tint,
              imageUrl: item.imageUrl,
              aspectRatio: 1,
              iconScale: 0.38,
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.25),
            ),
            const SizedBox(height: 6),
            _Stars(
              rating: item.rating,
              count: item.reviewCount,
              footnote: item.footnote,
            ),
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
      ),
    );
  }
}

/// Five stars with the rating filled in, plus the review count.
///
/// When nothing has been rated it shows the footnote instead, or nothing at
/// all. Five empty stars beside a zero is not "unrated" to anyone looking at
/// it -- it reads as a product everybody disliked.
class _Stars extends StatelessWidget {
  const _Stars({required this.rating, required this.count, this.footnote});

  final double rating;
  final int count;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (count <= 0) {
      final note = footnote;
      if (note == null) return const SizedBox(height: 13);
      return Text(
        note,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

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
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// A whole number with thousands separators, e.g. `27,590`.
///
/// The grouping on its own, for the few places that count something which is
/// not money -- the coin chip in the header, where the glyph beside the figure
/// already says what it counts and the `Rs.` would only cost the delivery
/// address the room it needs to name a place.
String formatGrouped(num value) {
  final rounded = value.round();
  // The sign is held back rather than grouped. A negative went through the loop
  // as "-120", where the minus counts as a character and the separator lands
  // straight after it: "-,120". Prices are never negative, so nothing showed it
  // until the coins page came to print what an account had spent.
  final digits = rounded.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return rounded < 0 ? '-$buffer' : buffer.toString();
}

/// Rupees with thousands separators, e.g. `Rs. 27,590`.
///
/// Hand-rolled rather than pulling in `intl` for one call site; NPR is shown
/// without decimals across the GtradeA storefront.
String formatRupees(num value) => 'Rs. ${formatGrouped(value)}';
