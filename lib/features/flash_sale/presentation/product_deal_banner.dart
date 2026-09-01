import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../data/flash_sale.dart';
import 'sale_countdown.dart';

/// The offer a product page was opened from.
///
/// Optional everywhere it is passed. A product reached from search or a rail
/// has no deal behind it, and its page must look exactly as it always has --
/// which is why every widget in this file is additive and every caller can pass
/// null.
class ProductDeal {
  const ProductDeal({required this.item, this.endsAt});

  final FlashSaleItem item;

  /// When the sale it belongs to stops. Null for an offer with no deadline,
  /// which shows the badge and the price without a countdown.
  final DateTime? endsAt;

  int get discountPercent => item.discountPercent;
  bool get hasSaving => item.hasSaving;

  /// The "was" price, rescaled to whatever this page is actually charging.
  ///
  /// The card's figure cannot simply be reused: the detail page prices by the
  /// chosen variant and quantity tier, so a struck price copied from the card
  /// would stop matching the moment either changed, and the discount badge
  /// beside it would start claiming a percentage that is not what the two
  /// numbers show.
  num? listPriceFor(num unitPrice) {
    if (discountPercent <= 0 || discountPercent >= 100) return null;

    // The card's own figure while the page is charging what the card said.
    // Recomputing it would round independently and land a rupee out, and a
    // "was" price that changes by one between the grid and the page is the
    // kind of detail that makes a shopper doubt the rest of it.
    if (unitPrice == item.salePrice && item.hasSaving) return item.listPrice;

    final list = unitPrice * 100 / (100 - discountPercent);
    return list <= unitPrice ? null : list.roundToDouble();
  }
}

/// The red band under the gallery: which sale this is, and how long is left.
///
/// Sits directly below the images and above everything else, because it is the
/// reason the price underneath is what it is.
class ProductDealBanner extends StatelessWidget {
  const ProductDealBanner({
    super.key,
    required this.deal,
    this.onEnded,
    this.now,
  });

  final ProductDeal deal;

  /// Fired when the countdown runs out while the page is open.
  final VoidCallback? onEnded;

  /// The clock, injectable so a test can put the sale in the past.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final endsAt = deal.endsAt;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      color: AppColors.accent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The name and a four-cell countdown do not fit on one line on a
          // narrow phone. Squeezing them both used to shrink the digits to
          // the point of being unreadable -- which defeats the countdown -- so
          // below this they stack and each gets its full size.
          final narrow = constraints.maxWidth < 360;
          final title = _Title(compact: narrow);

          if (endsAt == null) return title;

          final clock = _Clock(
            endsAt: endsAt,
            onEnded: onEnded,
            now: now,
            alignEnd: !narrow,
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [title, const SizedBox(height: 8), clock],
            );
          }

          return Row(
            children: [
              title,
              const Spacer(),
              Flexible(child: clock),
            ],
          );
        },
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.bolt, size: 20, color: Color(0xFFFFC72C)),
        const SizedBox(width: 6),
        Text(
          'Flash Sales',
          style: theme.textTheme.titleSmall?.copyWith(
            color: AppColors.onAccent,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _Clock extends StatelessWidget {
  const _Clock({
    required this.endsAt,
    required this.alignEnd,
    this.onEnded,
    this.now,
  });

  final DateTime endsAt;
  final bool alignEnd;
  final VoidCallback? onEnded;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FittedBox(
      // Only ever shrinks, and now only has to cope with a large text scale
      // rather than with the whole band being too narrow.
      fit: BoxFit.scaleDown,
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            // Against the digits rather than the digits-and-label block.
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Ends in',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.onAccent.withValues(alpha: 0.95),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SaleCountdown(
            endsAt: endsAt,
            compact: true,
            boxed: true,
            onEnded: onEnded,
            now: now,
          ),
        ],
      ),
    );
  }
}

/// The discount, over the top-left corner of the gallery.
class ProductDealBadge extends StatelessWidget {
  const ProductDealBadge({super.key, required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Text(
        '-$percent%',
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: AppColors.onAccent, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// How much of the batch has gone, and what is left.
///
/// Both halves are independently optional: the catalogue publishes neither, so
/// on a real payload this draws nothing rather than a meter with no numbers
/// behind it.
class ProductDealStock extends StatelessWidget {
  const ProductDealStock({super.key, this.soldPercent, this.stock});

  final int? soldPercent;
  final int? stock;

  bool get hasAnything => soldPercent != null || stock != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sold = soldPercent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sold != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (sold / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.accent.withValues(alpha: 0.14),
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            if (sold != null)
              Expanded(
                child: Text(
                  '$sold% sold',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (stock != null)
              Text.rich(
                TextSpan(
                  text: 'Stock left: ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  children: [
                    TextSpan(
                      text: '$stock',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
