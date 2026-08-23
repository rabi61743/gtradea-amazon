import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../account/data/recently_viewed_store.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../home/widgets/product_rail.dart';
import '../data/product_detail_content.dart';
import '../../wishlist/data/wishlist_store.dart';
import '../widgets/assurance_row.dart';
import '../widgets/product_gallery.dart';
import 'image_viewer_screen.dart';
import '../widgets/ratings_summary.dart';
import '../widgets/variant_picker.dart';

/// Product detail: gallery, price, variants, delivery, specs, and a pinned
/// buy bar.
///
/// The reference opens with a sponsored ad above the product the shopper just
/// chose to look at. There is none here: the top of this page belongs to the
/// thing being sold.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, this.product = ProductDetail.sample});

  final ProductDetail product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _variant = 0;
  int _quantity = 1;
  bool _descriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    // So the app-bar badge is right on first paint rather than counting up
    // after the cart happens to load.
    CartStore.instance.load();

    // Open on something buyable. The picker refuses to select a sold-out
    // swatch, so defaulting to index 0 when index 0 is sold out would strand
    // the page on an option the shopper cannot change away from by tapping it.
    final firstInStock =
        widget.product.variants.indexWhere((variant) => variant.inStock);
    if (firstInStock > 0) _variant = firstInStock;

    // Opening the page is the visit. Recorded after the first frame so it
    // never competes with building it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RecentlyViewedStore.instance.load().then((_) {
        if (mounted) RecentlyViewedStore.instance.record(_savedProduct);
      });
    });
  }

  ProductDetail get _product => widget.product;

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Stable id for the sample product. A real build keys on the catalogue
  /// id; the title is unique enough for placeholder data.
  String get _productId => _product.title;

  ProductVariant? get _selectedVariant =>
      _product.variants.isEmpty ? null : _product.variants[_variant];

  /// The line this page would add, at the currently chosen variant and
  /// quantity. Built in one place so Add-to-cart and Buy-now cannot end up
  /// disagreeing about what is being bought.
  CartLine get _cartLine => CartLine(
    productId: _productId,
    variantLabel: _selectedVariant?.label,
    title: _product.title,
    unitPrice: _product.price,
    listPrice: _product.listPrice,
    imageUrl: _product.images.isEmpty ? null : _product.images.first,
    quantity: _quantity,
    minOrder: _product.minOrder,
    freeDelivery: _product.freeDelivery,
  );

  void _openCart() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CartScreen()));
  }

  /// True when the page is sitting on an option that cannot be bought -- every
  /// variant sold out, so there is nothing to default to.
  bool get _selectionUnavailable => _selectedVariant?.inStock == false;

  void _addToCart() {
    // Guarded here as well as in the picker. A rule that lives only in a
    // widget is one the next entry point into this page walks straight around.
    if (_selectionUnavailable) {
      _snack('${_selectedVariant!.label} is sold out');
      return;
    }
    final inCart = CartStore.instance.add(_cartLine);
    final variant = _selectedVariant?.label;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            variant == null
                ? 'Added to your cart. $inCart in cart.'
                : 'Added $variant to your cart. $inCart in cart.',
          ),
          action: SnackBarAction(label: 'View cart', onPressed: _openCart),
        ),
      );
  }

  /// Buy now is add-to-cart that keeps going, rather than a second path with
  /// its own idea of what is being bought.
  void _buyNow() {
    if (_selectionUnavailable) {
      _snack('${_selectedVariant!.label} is sold out');
      return;
    }
    CartStore.instance.add(_cartLine);
    _openCart();
  }

  SavedProduct get _savedProduct => SavedProduct(
    id: _productId,
    title: _product.title,
    price: _product.price,
    listPrice: _product.listPrice,
    imageUrl: _product.images.isEmpty ? null : _product.images.first,
  );

  Future<void> _share() async {
    final product = _product;
    // A real link once routing exists; the text is what actually travels,
    // and a bare URL with no context is a poor share.
    final text = [
      product.title,
      formatRupees(product.price),
      'https://gtradea.com/p/${Uri.encodeComponent(product.title)}',
    ].join(' - ');
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (_) {
      if (mounted) _snack('Could not open the share sheet');
    }
  }

  void _openViewer(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ImageViewerScreen(images: _product.images, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = _product;
    final discount = product.discountPercent;
    final list = product.listPrice;
    final vat = product.vatIncluded;
    final sold = product.soldCount;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Pinned: Save and Share have to stay reachable from the reviews
          // at the bottom of the page, which is exactly where a shopper
          // decides to keep something for later.
          SliverAppBar(
            pinned: true,
            title: const Text('Product'),
            actions: [
              ListenableBuilder(
                listenable: WishlistStore.instance,
                builder: (context, _) {
                  final saved = WishlistStore.instance.contains(_productId);
                  return IconButton(
                    icon: Icon(
                      saved ? Icons.favorite : Icons.favorite_border,
                      color: saved ? AppColors.wishlist : null,
                    ),
                    tooltip: saved ? 'Saved' : 'Save',
                    onPressed: () {
                      final nowSaved = WishlistStore.instance.toggle(
                        _savedProduct,
                      );
                      _snack(
                        nowSaved
                            ? 'Saved to your list'
                            : 'Removed from your list',
                      );
                    },
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Share',
                onPressed: _share,
              ),
              ListenableBuilder(
                listenable: CartStore.instance,
                builder: (context, _) => IconButton(
                  icon: Badge.count(
                    count: CartStore.instance.count,
                    isLabelVisible: true,
                    child: const Icon(Icons.shopping_cart_outlined),
                  ),
                  tooltip: 'Cart',
                  onPressed: _openCart,
                ),
              ),
            ],
          ),
          SliverList.list(
            children: [
              ProductGallery(images: product.images, onImageTap: _openViewer),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Rating and sales belong beside the name, where they read
                    // as facts about the product rather than a badge stuck on
                    // the photograph.
                    Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: AppColors.star),
                        const SizedBox(width: 4),
                        Text(
                          product.rating.toStringAsFixed(1),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${product.reviewCount})',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (sold != null) ...[
                          const SizedBox(width: 10),
                          Text(
                            '${_compact(sold)} sold',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Price, saving and tax on one block so nothing about what is
                    // owed is discoverable only further down the page.
                    // Wrap, not Row: price + struck price + saving overflows a
                    // 360pt phone by ~90px, and dropping the saving to a second
                    // line beats shrinking the price until it cannot be read.
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Text(
                          formatRupees(product.price),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        if (list != null && discount != null) ...[
                          Text(
                            formatRupees(list),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              decoration: TextDecoration.lineThrough,
                              decorationColor:
                                  theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '-$discount%',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (vat != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Includes ${formatRupees(vat)} VAT',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    VariantPicker(
                      variants: product.variants,
                      selectedIndex: _variant,
                      onSelected: (i) => setState(() => _variant = i),
                    ),
                    const SizedBox(height: 16),
                    _QuantityRow(
                      quantity: _quantity,
                      minOrder: product.minOrder,
                      onChanged: (value) => setState(() => _quantity = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _DeliveryCard(freeDelivery: product.freeDelivery),
              const SizedBox(height: 14),
              AssuranceRow(assurances: product.assurances),
              if (product.highlights.isNotEmpty) ...[
                _SectionTitle('Highlights'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _HighlightsGrid(highlights: product.highlights),
                ),
              ],
              _SectionTitle('Description'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.description,
                      maxLines: _descriptionExpanded ? null : 3,
                      overflow: _descriptionExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(
                          () => _descriptionExpanded = !_descriptionExpanded,
                        ),
                        child: Text(
                          _descriptionExpanded ? 'Show less' : 'Read more',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _SectionTitle('Specifications'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SpecTable(specs: product.specs),
              ),
              if (product.ratingSummary != null) ...[
                _SectionTitle('Ratings and reviews'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: RatingsSummary(
                    summary: product.ratingSummary!,
                    reviews: product.reviews,
                  ),
                ),
              ],
              if (product.similar.isNotEmpty)
                ProductRail(
                  title: 'Similar products',
                  leadingIcon: Icons.compare_arrows,
                  items: product.similar,
                  onSeeAll: () {},
                ),
              const SizedBox(height: 24),
            ],
          ),
        ],
      ),
      bottomNavigationBar: _BuyBar(
        total: product.price * _quantity,
        onAddToCart: _addToCart,
        onBuyNow: _buyNow,
      ),
    );
  }

  static String _compact(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
}

/// The handful of facts a shopper checks first, two to a row.
///
/// Not collapsible, unlike the reference. These are six short pairs; hiding
/// them behind a chevron saves a few hundred pixels and costs the shopper
/// the tap that answers "is this the right thing".
class _HighlightsGrid extends StatelessWidget {
  const _HighlightsGrid({required this.highlights});

  final List<ProductSpec> highlights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columnWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: [
            for (final item in highlights)
              SizedBox(
                width: columnWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Quantity stepper that respects a minimum order.
///
/// The floor is stated rather than enforced silently: a stepper that simply
/// refuses to go lower reads as broken.
class _QuantityRow extends StatelessWidget {
  const _QuantityRow({
    required this.quantity,
    required this.minOrder,
    required this.onChanged,
  });

  final int quantity;
  final int minOrder;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canDecrease = quantity > minOrder;

    return Row(
      children: [
        Text(
          'Quantity',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 18),
                tooltip: 'Fewer',
                onPressed: canDecrease ? () => onChanged(quantity - 1) : null,
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '$quantity',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'More',
                onPressed: () => onChanged(quantity + 1),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (minOrder > 1)
          Text(
            'Min $minOrder',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Where it goes and when, on the detail page rather than at checkout.
///
/// Delivery cost and timing are what a shopper in Nepal actually decides on,
/// and finding them only after entering an address is the reason carts get
/// abandoned.
class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.freeDelivery});

  final bool freeDelivery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Deliver to Lalitpur',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(onPressed: () {}, child: const Text('Change')),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    freeDelivery
                        ? 'Free delivery, 3 to 5 business days'
                        : 'Delivery charged at checkout, 3 to 5 business days',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: freeDelivery
                          ? AppColors.success
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: freeDelivery
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecTable extends StatelessWidget {
  const _SpecTable({required this.specs});

  final List<ProductSpec> specs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (var i = 0; i < specs.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == specs.length - 1
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        specs[i].label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        specs[i].value,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pinned actions.
///
/// Both carry the running total, because the reference's "Buy at Rs.330"
/// against a Rs.299 headline is exactly the moment a shopper stops trusting
/// the price -- if the number differs, the difference should be visible before
/// the tap, not after it.
class _BuyBar extends StatelessWidget {
  const _BuyBar({
    required this.total,
    required this.onAddToCart,
    required this.onBuyNow,
  });

  final num total;
  final VoidCallback onAddToCart;
  final VoidCallback onBuyNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAddToCart,
                  icon: const Icon(Icons.add_shopping_cart, size: 18),
                  label: const Text('Add to cart'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onBuyNow,
                  child: Text('Buy · ${formatRupees(total)}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
