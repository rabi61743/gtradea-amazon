import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../../shared/widgets/shimmer.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;

/// One product in the results grid.
///
/// The reference card carries a rating pill, a struck-through price and a
/// percentage off. This catalogue publishes none of the three: `rating` is null
/// on every row, there is no review count and no list price. So the card keeps
/// the reference's shape -- picture, price line, a badge, a credibility line --
/// and fills it with the signals that do exist:
///
///   * **units sold**, the only popularity figure the feed carries, in place of
///     the rating count;
///   * the **seller's** trade score, labelled as the seller's so it cannot be
///     read as a product rating;
///   * a badge derived from real sales rather than a "Sale" tag with no sale
///     behind it.
///
/// Every one of those is conditional on the figure existing, because on a lot
/// of rows none of them do and the card still has to look finished.
class ProductResultCard extends StatelessWidget {
  const ProductResultCard({
    super.key,
    required this.product,
    this.onTap,
    this.onAddToCart,
    this.onToggleSaved,
    this.saved = false,
  });

  final Product product;
  final VoidCallback? onTap;
  final VoidCallback? onAddToCart;
  final VoidCallback? onToggleSaved;
  final bool saved;

  /// The card's internal rhythm, kept together so the gaps stay related.
  static const _pad = 10.0;
  static const _gap = 8.0;
  static const _gapTight = 5.0;

  /// Lines of title the card always reserves, so cards in a row end level even
  /// when one title runs short.
  static const _titleLines = 2;

  /// Roughly the width a card wants. Columns come from this rather than from
  /// named device sizes, so a split-screen tablet gets the layout that fits
  /// rather than the layout its diagonal implies.
  static const targetWidth = 190.0;
  static const gridGap = 10.0;

  static int columnsFor(double width) =>
      (width / targetWidth).floor().clamp(2, 6);

  /// The width one card gets, given the space the grid has.
  static double widthFor(double available) {
    final columns = columnsFor(available);
    return (available - gridGap * (columns - 1)) / columns;
  }

  /// Exactly how tall a card of [cardWidth] will be.
  ///
  /// Measured from the card's own parts rather than expressed as an aspect
  /// ratio, because a ratio is a guess that has to be re-guessed every time a
  /// row is added -- and it was 18 pixels short the first time. The grid asks
  /// for this as a `mainAxisExtent`, so the two can never drift.
  ///
  /// Everything variable goes through the reader's text scaler: at 200% type a
  /// fixed height clips the sold line off the bottom.
  static double heightFor(BuildContext context, double cardWidth) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);

    double lineOf(TextStyle? style, double fallback, {double lines = 1}) =>
        scaler.scale((style?.fontSize ?? fallback) * 1.35 * lines);

    // The picture is square and spans the padded width.
    final image = cardWidth - _pad * 2;
    final title = lineOf(
      theme.textTheme.bodySmall,
      12,
      lines: _titleLines.toDouble(),
    );
    // The add-to-cart button is a fixed 32 square, so the price row is at
    // least that tall however small the type is.
    final priceText = lineOf(theme.textTheme.titleSmall, 14);
    final price = priceText > 32 ? priceText : 32.0;
    // The seller badge is a scaled label inside 2pt of padding.
    final credibility = lineOf(theme.textTheme.labelSmall, 11) + 4;

    return _pad * 2 +
        image +
        _gap +
        price +
        _gapTight +
        title +
        _gapTight +
        credibility;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final titleStyle = (theme.textTheme.bodySmall ?? const TextStyle())
        .copyWith(height: 1.3, fontWeight: FontWeight.w500);
    final titleHeight = MediaQuery.textScalerOf(context).scale(
      (titleStyle.fontSize ?? 12) * (titleStyle.height ?? 1.3) * _titleLines,
    );

    final badge = _badgeFor(product);

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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                    child: ArtworkPanel(
                      icon: iconForCategory(
                        product.categoryName ?? product.parentCategoryName,
                      ),
                      tint: tintForCategory(
                        product.categoryCid ?? product.numIid,
                      ),
                      imageUrl: product.imageUrl,
                      aspectRatio: 1,
                    ),
                  ),
                  if (badge != null)
                    Positioned(top: 6, left: 6, child: _Badge(badge: badge)),
                  if (onToggleSaved != null)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: _SaveButton(
                        saved: saved,
                        title: product.title,
                        onPressed: onToggleSaved!,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: _gap),
              _PriceRow(product: product, onAddToCart: onAddToCart),
              const SizedBox(height: _gapTight),
              SizedBox(
                height: titleHeight,
                child: Text(
                  product.title,
                  maxLines: _titleLines,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              if (product.salesLabel != null || product.tradeScore != null) ...[
                const SizedBox(height: _gapTight),
                _Credibility(product: product),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What a card can claim, and the real figure behind it.
///
/// Thresholds rather than a flag from the server, because there is no flag --
/// but the sales figure is real, so a badge derived from it is a fact about the
/// listing rather than a marketing tag stuck on at random.
enum ResultBadge {
  bestSeller('Best Seller', Icons.local_fire_department),
  popular('Popular', Icons.trending_up),
  verified('Verified', Icons.verified);

  const ResultBadge(this.label, this.icon);

  final String label;
  final IconData icon;
}

ResultBadge? _badgeFor(Product product) {
  final sales = product.sales ?? 0;
  if (sales >= 10000) return ResultBadge.bestSeller;
  if (sales >= 1000) return ResultBadge.popular;
  // Falls back to the seller's own vouching only when there is no sales story
  // to tell, so the badge slot never carries two claims at once.
  if (product.sellerBadge != null) return ResultBadge.verified;
  return null;
}

class _Badge extends StatelessWidget {
  const _Badge({required this.badge});

  final ResultBadge badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onAccent = badge == ResultBadge.verified
        ? theme.colorScheme.primary
        : AppColors.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: onAccent,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            badge.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// The heart, on a scrim so it stays visible over a pale photograph.
class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.saved,
    required this.title,
    required this.onPressed,
  });

  final bool saved;
  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // Names the product, so a screen reader running down a grid of these does
      // not read out forty identical "Save" buttons.
      label: saved ? 'Saved: $title' : 'Save $title',
      child: Material(
        color: Colors.white.withValues(alpha: 0.88),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              saved ? Icons.favorite : Icons.favorite_border,
              size: 17,
              color: saved ? AppColors.accent : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.product, this.onAddToCart});

  final Product product;
  final VoidCallback? onAddToCart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priced = product.hasPrice;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: priced
              ? Text(
                  formatRupees(product.displayPrice!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                )
              // Not "Rs. 0". The row is a real product whose pricing has not
              // been worked out, and a zero would be a lie about it.
              : Text(
                  'Price on request',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        // Nothing to add to a cart at an unknown price, so the button is not
        // offered rather than offered and failing.
        if (onAddToCart != null && priced) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 32,
            height: 32,
            child: Material(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                onTap: onAddToCart,
                child: Tooltip(
                  message: 'Add to cart',
                  child: Icon(
                    Icons.add_shopping_cart,
                    size: 16,
                    color: theme.colorScheme.primary,
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

/// Units sold and the seller's score -- what stands in for the reference's
/// rating row.
class _Credibility extends StatelessWidget {
  const _Credibility({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = product.tradeScore;
    final sold = product.salesLabel;

    // Scaled down rather than ellipsised or clipped. At 200% type the badge,
    // the word "seller" and the sold count together want more than a 190pt
    // card has, and every part of this row is load-bearing: truncating
    // "seller" to "sel..." is exactly how the score starts reading as a
    // product rating.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (score != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.successInk,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    score,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.star, size: 9, color: Colors.white),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // Says whose score it is. Without the word this reads as a product
            // rating, which is the one thing this catalogue cannot tell you.
            Text(
              'seller',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (sold != null)
            Text(
              sold,
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// The grid's shape while the page is in flight.
///
/// Cards rather than a spinner, and built from the real card's own constants
/// and its own [ProductResultCard.heightFor] -- so the placeholders are not
/// merely a similar size, they are the size, and the results cannot jump into a
/// different layout when they land.
///
/// One bone per element the real card has: picture, price, two lines of title,
/// the sold line, and the round add-to-cart button. A skeleton that omits the
/// button is a skeleton that shifts when the button appears.
class ResultGridSkeleton extends StatelessWidget {
  const ResultGridSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Shimmer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = ProductResultCard.widthFor(constraints.maxWidth);
          final height = ProductResultCard.heightFor(context, width);

          return Wrap(
            spacing: ProductResultCard.gridGap,
            runSpacing: ProductResultCard.gridGap,
            children: [
              for (var i = 0; i < count; i++)
                SizedBox(
                  width: width,
                  height: height,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    padding: const EdgeInsets.all(ProductResultCard._pad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const ShimmerPanel(
                          aspectRatio: 1,
                          radius: AppTheme.radiusControl,
                        ),
                        const SizedBox(height: ProductResultCard._gap),
                        // The price, and the add-to-cart square beside it.
                        Row(
                          children: [
                            ShimmerBone(width: width * 0.4, height: 13),
                            const Spacer(),
                            const ShimmerBone(
                              width: 32,
                              height: 32,
                              radius: AppTheme.radiusControl,
                            ),
                          ],
                        ),
                        const SizedBox(height: ProductResultCard._gapTight),
                        const ShimmerBone(),
                        const SizedBox(height: 4),
                        ShimmerBone(width: width * 0.55),
                        const SizedBox(height: ProductResultCard._gapTight),
                        // The sold line and the seller score.
                        ShimmerBone(width: width * 0.42, height: 10),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
