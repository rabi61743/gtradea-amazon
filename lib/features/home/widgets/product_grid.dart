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
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final List<Product> products;
  final VoidCallback? onSeeAll;
  final void Function(Product product)? onAddToCart;

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
          padding: const EdgeInsets.fromLTRB(_margin, 0, _margin, 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Already inside the margin, so this is the space the cards
              // divide up -- the same reading the results grid takes.
              final available = constraints.maxWidth;
              final columns = ProductResultCard.columnsFor(available);

              return GridView.builder(
                // It lives inside the home page's own scroll view, so it must
                // not scroll itself: two nested scrollables would fight for
                // the drag, and the inner one would swallow it.
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: products.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: ProductResultCard.gridGap,
                  crossAxisSpacing: ProductResultCard.gridGap,
                  // The card's exact height, asked of the card. A ratio here
                  // would be a guess that has to be re-guessed every time a row
                  // is added to the card -- and it was 18 pixels short the
                  // first time somebody tried.
                  mainAxisExtent: ProductResultCard.heightFor(
                    context,
                    ProductResultCard.widthFor(available),
                  ),
                ),
                itemBuilder: (context, i) {
                  final product = products[i];
                  return ProductResultCard(
                    product: product,
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
