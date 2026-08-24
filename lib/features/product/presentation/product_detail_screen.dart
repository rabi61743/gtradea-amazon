import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../account/data/recently_viewed_store.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../home/widgets/product_rail.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../search/presentation/search_results_screen.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../data/product_detail_content.dart';
import '../data/product_repository.dart';
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
  const ProductDetailScreen({super.key, required this.product, this.detail});

  /// The catalogue row that was tapped. Enough to paint the page immediately.
  final Product product;

  /// A ready-made record, for tests and for the rare caller that already has
  /// one. When null the page fetches it.
  final ProductDetail? detail;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _variant = 0;
  late int _quantity = _detail.minOrder > 0 ? _detail.minOrder : 1;
  bool _descriptionExpanded = false;

  late ProductDetail _detail =
      widget.detail ?? ProductDetail.fromProduct(widget.product);

  /// Set when the full record could not be fetched. The page keeps rendering
  /// the card's own data underneath it -- a title and a price the shopper just
  /// saw are worth more than an error page.
  ApiError? _detailError;

  /// The rest of this department, for the rail at the bottom.
  List<Product> _similar = const [];

  @override
  void initState() {
    super.initState();
    // So the app-bar badge is right on first paint rather than counting up
    // after the cart happens to load.
    CartStore.instance.load();

    // Open on something buyable. The picker refuses to select a sold-out
    // swatch, so defaulting to index 0 when index 0 is sold out would strand
    // the page on an option the shopper cannot change away from by tapping it.
    final firstInStock = _detail.variants.indexWhere((variant) => variant.inStock);
    if (firstInStock > 0) _variant = firstInStock;

    if (widget.detail == null) unawaited(_loadDetail());

    // Opening the page is the visit. Recorded after the first frame so it
    // never competes with building it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RecentlyViewedStore.instance.load().then((_) {
        if (mounted) RecentlyViewedStore.instance.record(_savedProduct);
      });
      // The server keeps its own recently-viewed list for signed-in shoppers,
      // so the same visit counts on the web storefront too.
      unawaited(ProductRepository.instance.recordView(
        numIid: widget.product.numIid,
        name: widget.product.title,
        imageUrl: widget.product.imageUrl,
        priceLabel:
            widget.product.hasPrice ? formatRupees(widget.product.displayPrice!) : null,
      ));
    });
  }

  ProductDetail get _product => _detail;

  /// Fetches the full record and, once it lands, the rest of its department.
  Future<void> _loadDetail() async {
    try {
      final body = await ProductRepository.instance.detail(widget.product.numIid);
      if (!mounted) return;
      final detail = ProductDetail.fromApi(body, fallback: widget.product);
      setState(() {
        _detail = detail;
        _detailError = null;
        // The preview had no options; the record may. Start on one that can
        // actually be bought.
        final firstInStock = detail.variants.indexWhere((v) => v.inStock);
        _variant = firstInStock < 0 ? 0 : firstInStock;
        _quantity = detail.minOrder > 0 ? detail.minOrder : 1;
      });
      unawaited(_loadSimilar(detail));
    } on ApiError catch (e) {
      if (mounted) setState(() => _detailError = e);
    }
  }

  /// More from the same department. Real products rather than a hand-picked
  /// list, so it stays right as the catalogue changes.
  Future<void> _loadSimilar(ProductDetail detail) async {
    final cid = detail.categoryCid ?? widget.product.categoryCid;
    if (cid == null) return;
    try {
      final products =
          await CatalogRepository.instance.categoryProducts(cid, pageSize: 12);
      if (!mounted) return;
      final others = products
          .where((p) => p.numIid != detail.numIid)
          .take(8)
          .toList(growable: false);
      if (others.isEmpty) return;
      setState(() => _similar = others);
    } on ApiError {
      // A rail that did not load is a rail that is not shown.
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// The catalogue key. Everything that refers to this product later -- the
  /// cart line, the wishlist entry, the order item -- uses it.
  String get _productId => widget.product.numIid;

  ProductVariant? get _selectedVariant =>
      _product.variants.isEmpty ? null : _product.variants[_variant];

  /// The line this page would add, at the currently chosen variant and
  /// quantity. Built in one place so Add-to-cart and Buy-now cannot end up
  /// disagreeing about what is being bought.
  CartLine get _cartLine => CartLine(
    productId: _productId,
    variantLabel: _selectedVariant?.label,
    title: _product.title,
    unitPrice: _unitPrice,
    listPrice: _product.listPrice,
    // The chosen colourway's own photo, so two variants of one product are
    // told apart at a glance in the cart instead of showing the same picture
    // twice with only a text label between them.
    imageUrl: _selectedVariant?.imageUrl ??
        (_product.images.isEmpty ? null : _product.images.first),
    quantity: _quantity,
    minOrder: _product.minOrder,
    freeDelivery: _product.freeDelivery,
    category: _product.category,
    // Everything in this catalogue is imported, and the SKU is what the
    // server actually orders upstream -- a colour name would not identify it.
    source: '1688',
    skuId: _selectedVariant?.skuId,
    specId: _selectedVariant?.specId,
  );

  void _openCart() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CartScreen()));
  }

  /// What one of these costs right now.
  ///
  /// Three things can move it: the option chosen, the quantity -- wholesale
  /// listings price in bands -- and neither, in which case it is the headline
  /// price. Worked out in one place so the buy bar and the cart line cannot
  /// disagree about it.
  num get _unitPrice =>
      _selectedVariant?.price ?? _product.priceAt(_quantity);

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
              if (_detailError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: LoadFailed(
                    compact: true,
                    // The card's own title, price and photograph are still on
                    // screen underneath. Saying what is missing beats replacing
                    // a usable page with an error.
                    message: _detailError!.isNetwork
                        ? 'No connection, so options and specifications could '
                            'not be loaded.'
                        : _detailError!.message,
                    onRetry: _loadDetail,
                  ),
                ),
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
                    // What is known about this product, beside the name where
                    // it reads as fact rather than as a badge stuck on the
                    // photograph.
                    //
                    // The rating appears only when there is one. A catalogue
                    // with no reviews would otherwise show every product as
                    // zero stars, and "0.0 (0)" reads as rated badly rather
                    // than as not rated.
                    Row(
                      children: [
                        if (product.reviewCount > 0) ...[
                          const Icon(Icons.star,
                              size: 16, color: AppColors.star),
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
                          const SizedBox(width: 10),
                        ],
                        if (sold != null)
                          Text(
                            '${_compact(sold)} sold',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (product.sellerName != null) ...[
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              product.sellerName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
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
                      label: product.variantLabel,
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
              if (_similar.isNotEmpty)
                ProductRail(
                  title: 'More in ${product.category ?? 'this department'}',
                  leadingIcon: Icons.compare_arrows,
                  items: toProductItems(context, _similar),
                  onSeeAll: product.categoryCid == null
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => SearchResultsScreen(
                              query: '',
                              categoryCid: product.categoryCid,
                            ),
                          )),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ],
      ),
      bottomNavigationBar: _BuyBar(
        total: _unitPrice * _quantity,
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
