import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/flash_sale.dart';

/// One product at its sale price.
///
/// Every element below the picture is conditional on the figure behind it
/// existing. That is not defensiveness for its own sake -- the catalogue has no
/// list price, no stock and no sold count, so on a real payload most of this
/// card is absent, and it has to still look finished rather than half-drawn.
class FlashDealCard extends StatelessWidget {
  const FlashDealCard({
    super.key,
    required this.item,
    this.onTap,
    this.onAddToCart,
  });

  final FlashSaleItem item;
  final VoidCallback? onTap;
  final VoidCallback? onAddToCart;

  /// The card's internal rhythm, in one place so the gaps stay related to each
  /// other rather than drifting apart one edit at a time.
  static const _pad = 10.0;
  static const _gapImage = 10.0;
  static const _gapText = 8.0;
  static const _gapTight = 6.0;

  /// How many lines of title the card always reserves.
  ///
  /// Reserved rather than allowed to grow, because the grid lays these out in a
  /// Wrap and a Wrap does not stretch a row to a common height. A one-line
  /// title beside a two-line one made one card shorter than its neighbour, so
  /// their prices, savings and stock bars all sat on different lines.
  static const _titleLines = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = item.product;

    final titleStyle = (theme.textTheme.bodySmall ?? const TextStyle())
        .copyWith(height: 1.3);
    // Measured from the resolved style and the reader's own text scale, so the
    // reservation still holds at 200% type rather than clipping.
    final titleHeight = MediaQuery.textScalerOf(context).scale(
      (titleStyle.fontSize ?? 12) * (titleStyle.height ?? 1.3) * _titleLines,
    );

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(_pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  ArtworkPanel(
                    icon: iconForCategory(
                      product.categoryName ?? product.parentCategoryName,
                    ),
                    tint: tintForCategory(
                      product.categoryCid ?? product.numIid,
                    ),
                    imageUrl: product.imageUrl,
                    aspectRatio: 1,
                  ),
                  if (item.discountPercent > 0)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _DiscountBadge(percent: item.discountPercent),
                    ),
                ],
              ),
              const SizedBox(height: _gapImage),
              // Two lines' worth of space whether the title needs one or two,
              // so every card in a row ends at the same height.
              SizedBox(
                height: titleHeight,
                child: Text(
                  product.title,
                  maxLines: _titleLines,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              const SizedBox(height: _gapText),
              _PriceRow(item: item, onAddToCart: onAddToCart),
              if (item.hasSaving) ...[
                const SizedBox(height: _gapTight),
                // The rupee figure, which the percentage and the struck price
                // between them never actually state. It is the number people
                // compare deals on, and the one they have to do arithmetic for
                // if it is left off.
                _SavingChip(amount: item.listPrice - item.salePrice),
              ],
              if (item.soldPercent != null || item.stock != null) ...[
                const SizedBox(height: _gapImage),
                _StockMeter(soldPercent: item.soldPercent, stock: item.stock),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Text(
        '-$percent%',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: AppColors.onAccent, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// "Save Rs. 2,000", in the success colour rather than the sale red.
///
/// Green because it is the good news on the card, and because red is already
/// carrying the urgency -- two reds side by side and neither reads as either.
class _SavingChip extends StatelessWidget {
  const _SavingChip({required this.amount});

  final num amount;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        ),
        child: Text(
          'Save ${formatRupees(amount)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.successInk,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.item, this.onAddToCart});

  final FlashSaleItem item;
  final VoidCallback? onAddToCart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Only when it is genuinely higher. A crossed-out number equal to
              // or below the price being charged is a claimed saving that is
              // not there.
              if (item.hasSaving)
                Text(
                  formatRupees(item.listPrice),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              Text(
                formatRupees(item.salePrice),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
        if (onAddToCart != null) ...[
          const SizedBox(width: 8),
          // A fixed square rather than an IconButton's own metrics. Left to
          // itself the button was taller than the two lines of price beside it
          // and sat visually centred against them, so it lined up with neither
          // the struck price above nor the sale price it belongs to.
          SizedBox(
            width: 36,
            height: 36,
            child: Material(
              color: AppColors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                onTap: onAddToCart,
                child: Tooltip(
                  message: 'Add to cart',
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    size: 18,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// How much of the batch has gone, and what is left.
class _StockMeter extends StatelessWidget {
  const _StockMeter({this.soldPercent, this.stock});

  final int? soldPercent;
  final int? stock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sold = soldPercent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sold != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (sold / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.accent.withValues(alpha: 0.14),
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
        if (sold != null) const SizedBox(height: 6),
        Row(
          children: [
            if (sold != null)
              Expanded(
                child: Text(
                  '$sold% sold',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (stock != null)
              Text(
                'Stock: $stock',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
