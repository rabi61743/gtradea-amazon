import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/flash_sale.dart';

/// One deal, as a tile in the sale's two-by-two grid.
///
/// Deliberately not interactive. The whole panel this sits in is one tap
/// target that goes to the deals page, so a tile with its own [InkWell] would
/// cut a hole in that: the ripple would stop at the card's edge and the tap
/// would land somewhere else, which is the sort of thing that makes a block
/// feel unreliable rather than rich. Everything here is decoration; the panel
/// owns the gesture.
///
/// Three lines and nothing else -- a square picture, what it is, what it
/// costs. A tile in a grid of four is a preview of the deals page, not a
/// substitute for it, so the stock meter, the struck-through price and the Add
/// button all belong on the page that has room to justify them.
class FlashDealTile extends StatelessWidget {
  const FlashDealTile({super.key, required this.item});

  final FlashSaleItem item;

  static const _pad = 10.0;
  static const _radius = 14.0;

  /// How tall one line of a style actually is.
  ///
  /// Laid out rather than worked out. Multiplying a font size by a guessed
  /// factor was wrong twice -- 1.4 pixels the first time and 1.3 the second --
  /// because a resolved TextStyle carries its own `height`, and the theme sets
  /// different ones for different styles. A TextPainter knows; arithmetic does
  /// not.
  static double _line(BuildContext context, TextStyle? style) {
    final painter = TextPainter(
      // Ascender and descender, so the measurement is a full line box rather
      // than the height of whichever glyphs happen to be in the string.
      text: TextSpan(text: 'Ag', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.height;
  }

  /// The label above the price: what the thing is.
  static TextStyle labelStyleOf(ThemeData theme) =>
      (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.2,
      );

  /// The line that carries the offer, and the only bold thing on the tile.
  static TextStyle hookStyleOf(ThemeData theme) =>
      (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w800,
        height: 1.2,
      );

  /// Everything below the picture, which is a fixed height by construction.
  ///
  /// Both lines are boxed to exactly one line, so four tiles in a grid are the
  /// same height whatever their titles say. Letting them size themselves is
  /// how a two-by-two grid ends up with a ragged bottom edge.
  static double captionHeightFor(BuildContext context) {
    final theme = Theme.of(context);
    return _line(context, labelStyleOf(theme)) +
        3 +
        _line(context, hookStyleOf(theme));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = item.product;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard + 4),
      ),
      padding: const EdgeInsets.fromLTRB(_pad, _pad, _pad, _pad + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: ArtworkPanel(
              icon: iconForCategory(
                product.categoryName ?? product.parentCategoryName,
              ),
              tint: tintForCategory(product.categoryCid ?? product.numIid),
              imageUrl: product.imageUrl,
              aspectRatio: 1,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: _line(context, labelStyleOf(theme)),
            child: Text(
              product.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyleOf(theme),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: _line(context, hookStyleOf(theme)),
            child: Text(
              // What the offer actually is, taken from the deal rather than
              // written as a category-wide claim. "From Rs. 299" over a single
              // product is a range with one member in it, and "Up to 60% off"
              // over a 40%-off item is a number nobody can point at.
              item.discountPercent > 0
                  ? '${item.discountPercent}% off'
                  : formatRupees(item.salePrice),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: hookStyleOf(theme).copyWith(
                color: item.discountPercent > 0
                    ? AppColors.accent
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
