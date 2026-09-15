import 'package:flutter/material.dart';

import '../../../shared/widgets/section_header.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../search/widgets/product_result_card.dart';
import '../../wishlist/data/wishlist_store.dart';
import 'product_carousel.dart' show toggleSavedProduct;

/// Products laid out down the page rather than along a rail.
///
/// The same [ProductResultCard] the rails and the search results use, in the
/// same grid the search results use -- same columns, same gaps, same measured
/// height. That is the point of it: a shopper scrolling past should not be able
/// to tell that these cards were placed by different code from the ones on the
/// results page.
///
/// A rail shows four and asks to be swiped; this shows everything it is given
/// at once, which is what a section meant to be browsed rather than glanced at
/// needs.
class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.title,
    required this.products,
    this.subtitle,
    this.leadingIcon,
    this.onSeeAll,
    this.onAddToCart,
    this.spec = ResultGridSpec.standard,
    // No trailing four. The next section's heading brings its own room above
    // it, so this was four points of nothing between every grid and whatever
    // followed it.
    this.padding = const EdgeInsets.fromLTRB(_margin, 0, _margin, 0),
    this.wholeRows = false,
  });

  /// Draw only complete rows: as many cards as fill whole rows at the column
  /// count this width gets, when there is at least one full row. Off by
  /// default -- the home page shows everything it is given.
  final bool wholeRows;

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final List<Product> products;
  final VoidCallback? onSeeAll;
  final void Function(Product product)? onAddToCart;

  /// How the grid divides its width: columns, gaps and the padding inside
  /// each card. The standard grid unless a page asks for another -- the cart
  /// asks for the results page's compact one.
  final ResultGridSpec Function(double available) spec;

  /// Around the grid. The home page's own 12 by default.
  final EdgeInsets padding;

  /// The page margin the grid sits in, matching the results page's own.
  static const _margin = 12.0;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          subtitle: subtitle,
          leadingIcon: leadingIcon,
          onSeeAll: onSeeAll,
        ),
        Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Already inside the margin, so this is the space the cards
              // divide up -- the same reading the results grid takes.
              final available = constraints.maxWidth;
              final grid = spec(available);
              // A lone card on the last row is half a row of nothing beside
              // it; where asked, the remainder is left off.
              final count = wholeRows && products.length > grid.columns
                  ? products.length - products.length % grid.columns
                  : products.length;

              return GridView.builder(
                // It lives inside the home page's own scroll view, so it must
                // not scroll itself: two nested scrollables would fight for
                // the drag, and the inner one would swallow it.
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: count,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: grid.columns,
                  // Down and across are separate now. They were both `gap`,
                  // which meant the only way to close the rows up was to
                  // narrow the columns with them.
                  mainAxisSpacing: grid.rowGap ?? grid.gap,
                  crossAxisSpacing: grid.gap,
                  // The card's exact height, asked of the card. A ratio here
                  // would be a guess that has to be re-guessed every time a row
                  // is added to the card -- and it was 18 pixels short the
                  // first time somebody tried.
                  mainAxisExtent: ProductResultCard.heightFor(
                    context,
                    grid.cardWidth(available),
                    padding: grid.cardPadding,
                  ),
                ),
                itemBuilder: (context, i) {
                  final product = products[i];
                  return ProductResultCard(
                    product: product,
                    padding: grid.cardPadding,
                    saved: WishlistStore.instance.contains(product.numIid),
                    onTap: () => openProduct(context, product),
                    onToggleSaved: () => toggleSavedProduct(context, product),
                    onAddToCart: onAddToCart == null
                        ? null
                        : () => onAddToCart!(product),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
