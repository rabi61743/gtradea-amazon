import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/action_status.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/shimmer.dart';
import '../../../shared/widgets/snap_physics.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../search/widgets/product_result_card.dart';
import '../../wishlist/data/wishlist_store.dart';

/// A rail of products under a section heading.
///
/// The card is [ProductResultCard] -- the same one the department tabs and the
/// search results already use. The home rails used to draw a card of their own
/// with a five-star row on it, and this catalogue publishes no ratings, so that
/// row was blank on every card ever rendered. Two card definitions also meant
/// two price colours on one page: Trust Blue here, Commerce Orange everywhere
/// else. One card settles both.
///
/// Height comes from the card's own [ProductResultCard.heightFor] rather than
/// from a constant. The constant was `268 * textScale`, which is the kind of
/// guess that has already had to be corrected three times in this codebase.
class ProductCarousel extends StatelessWidget {
  const ProductCarousel({
    super.key,
    required this.title,
    required this.products,
    this.leadingIcon,
    this.onSeeAll,
    this.onAddToCart,
    this.width = cardWidth,
  });

  final String title;
  final IconData? leadingIcon;
  final List<Product> products;
  final VoidCallback? onSeeAll;
  final Future<void> Function(Product product)? onAddToCart;

  /// This rail's card width. [cardWidth] everywhere unless a caller asks for a
  /// more compact rail; the picture is square and the card's height is asked
  /// of the card, so both follow it proportionally.
  final double width;

  /// One card, at the width the grid would give it on a phone.
  static const cardWidth = ProductResultCard.targetWidth;
  static const gap = ProductResultCard.gridGap;

  /// Exactly how tall the rail is, asked of the card rather than assumed.
  static double heightFor(BuildContext context, {double width = cardWidth}) =>
      ProductResultCard.heightFor(context, width);

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
          height: heightFor(context, width: width),
          // One listener for the whole rail rather than one per card: the
          // hearts all read the same store, and a card each would be a dozen
          // subscriptions per department.
          child: ListenableBuilder(
            listenable: WishlistStore.instance,
            builder: (context, _) => ListView.separated(
              scrollDirection: Axis.horizontal,
              // Snaps to a card rather than drifting to a half-shown one,
              // which is what makes a rail feel like a set of things rather
              // than a strip that slid.
              physics: SnapPhysics(step: width + gap),
              padding: const EdgeInsets.symmetric(
                horizontal: SectionHeader.edge,
              ),
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(width: gap),
              itemBuilder: (context, i) {
                final product = products[i];
                return SizedBox(
                  width: width,
                  child: ProductResultCard(
                    product: product,
                    saved: WishlistStore.instance.contains(product.numIid),
                    onTap: () => openProduct(context, product),
                    onToggleSaved: () => _toggleSaved(context, product),
                    onAddToCart: onAddToCart == null
                        ? null
                        : () => onAddToCart!(product),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _toggleSaved(BuildContext context, Product product) =>
      toggleSavedProduct(context, product);
}

/// Saves or unsaves a product from a home-page card, and says which happened.
///
/// A function rather than a method because two arrangements of the same card
/// need it -- the rail above and [ProductGrid] beside it. Copying it would be a
/// second place for the snackbar wording and the [SavedProduct] mapping to
/// drift apart.
void toggleSavedProduct(BuildContext context, Product product) {
  final saved = WishlistStore.instance.toggle(
    SavedProduct(
      id: product.numIid,
      title: product.title,
      price: product.displayPrice ?? 0,
      imageUrl: product.imageUrl,
      sellerBadge: product.sellerBadge,
      salesLabel: product.salesLabel,
      category: product.categoryName,
      minOrder: product.minOrder,
    ),
  );
  // Only the removal is said out loud. Saving has its own animation now --
  // the heart flies to the Saved tab and the count moves with it -- so a
  // message repeating it in words was one confirmation too many.
  if (!saved) {
    ActionStatus.show(context, ActionStatus.removedFromWishlist);
  }
}

/// A rail of card-shaped bones, at exactly the height the real rail will be.
///
/// The department blocks used to render nothing at all while their rails
/// loaded, so five of them popped in at different moments and shoved the page
/// down under the reader's thumb each time. This holds the space.
///
/// Blocks rather than a drawing of the card's insides. [ResultGridSkeleton]
/// mimics the card row by row, and it can, because it lives in the same file
/// and reads the card's own private rhythm. From out here that would have to be
/// copied, and a copied rhythm is one that drifts the first time the card
/// changes -- a placeholder claiming a shape the card no longer has.
class ProductCarouselSkeleton extends StatelessWidget {
  const ProductCarouselSkeleton({
    super.key,
    this.title,
    this.count = 4,
    this.width = ProductCarousel.cardWidth,
  });

  final String? title;
  final int count;

  /// The card width of the rail this stands in for.
  final double width;

  @override
  Widget build(BuildContext context) {
    final title = this.title;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) SectionHeader(title: title),
        SizedBox(
          height: ProductCarousel.heightFor(context, width: width),
          child: Shimmer(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: SectionHeader.edge,
              ),
              itemCount: count,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: ProductCarousel.gap),
              itemBuilder: (context, _) => ShimmerBone.block(
                width: width,
                height: ProductCarousel.heightFor(context, width: width),
                radius: AppTheme.radiusCard,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
