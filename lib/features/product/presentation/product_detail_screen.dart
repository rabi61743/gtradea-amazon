import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../account/data/recently_viewed_store.dart';
import '../../auth/data/auth_store.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../flash_sale/presentation/product_deal_banner.dart';
import '../../catalog/data/product.dart';
import '../../home/widgets/product_grid.dart';
import '../../home/widgets/product_rail.dart';
import '../../search/presentation/search_results_screen.dart';
import '../../search/presentation/visual_search_screen.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../data/product_detail_content.dart';
import '../data/product_repository.dart';
import '../../wishlist/data/wishlist_store.dart';
import '../data/storefront_config.dart';
import '../widgets/assurance_row.dart';
import '../widgets/delivery_guarantee_card.dart';
import '../widgets/product_detail_images.dart';
import '../widgets/product_gallery.dart';
import '../widgets/product_section_panel.dart';
import '../widgets/product_quote_sheet.dart';
import 'image_viewer_screen.dart';
import '../widgets/ratings_summary.dart';
import '../widgets/variant_matrix_table.dart';
import '../widgets/variant_picker.dart';

/// Product detail: gallery, price, variants, delivery, specs, and a pinned
/// buy bar.
///
/// The reference opens with a sponsored ad above the product the shopper just
/// chose to look at. There is none here: the top of this page belongs to the
/// thing being sold.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.product,
    this.detail,
    this.deal,
    this.now,
  });

  /// The catalogue row that was tapped. Enough to paint the page immediately.
  final Product product;

  /// A ready-made record, for tests and for the rare caller that already has
  /// one. When null the page fetches it.
  final ProductDetail? detail;

  /// The offer this page was opened from, when it was opened from one.
  ///
  /// Null for a product reached from search, a rail or a wishlist -- and the
  /// page then renders exactly as it did before deals existed. Everything it
  /// adds is additive: a badge over the gallery, a band under it, the "was"
  /// price beside the price, and the stock meter.
  final ProductDeal? deal;

  /// The clock, injectable so a test can watch a sale expire.
  final DateTime Function()? now;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _variant = 0;
  late int _quantity = _detail.minOrder > 0 ? _detail.minOrder : 1;
  bool _descriptionExpanded = false;

  late ProductDetail _detail =
      widget.detail ?? ProductDetail.fromProduct(widget.product);

  /// The SKUs pivoted into a grid, when this listing is sold as one.
  ///
  /// Cached against the record rather than recomputed in build: a listing can
  /// carry 234 SKUs and this page rebuilds on every digit typed into the grid.
  late VariantMatrix? _matrix = VariantMatrix.from(_detail.variants);

  /// How many of each SKU the grid has on the order, keyed by SKU id.
  ///
  /// Empty for a listing without a grid, which goes on using [_variant] and
  /// [_quantity] exactly as before. The two paths never both apply: a grid
  /// exists or it does not.
  final Map<String, int> _picked = {};

  /// Set when the full record could not be fetched. The page keeps rendering
  /// the card's own data underneath it -- a title and a price the shopper just
  /// saw are worth more than an error page.
  ApiError? _detailError;

  /// The rest of this department, for the rail at the bottom.
  List<Product> _similar = const [];

  /// The site's shipping settings, which the delivery card is drawn from.
  ///
  /// Null until they arrive, and the card is simply not drawn until then --
  /// there is no skeleton, because a delivery window that appears and then
  /// changes is worse than one that appears a moment late.
  ShippingEstimate? _shipping;

  @override
  void initState() {
    super.initState();
    // So the app-bar badge is right on first paint rather than counting up
    // after the cart happens to load.
    CartStore.instance.load();

    // Open on something buyable. The picker refuses to select a sold-out
    // swatch, so defaulting to index 0 when index 0 is sold out would strand
    // the page on an option the shopper cannot change away from by tapping it.
    final firstInStock = _detail.variants.indexWhere(
      (variant) => variant.inStock,
    );
    if (firstInStock > 0) _variant = firstInStock;

    if (widget.detail == null) unawaited(_loadDetail());
    unawaited(_loadShipping());

    // Opening the page is the visit. Recorded after the first frame so it
    // never competes with building it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RecentlyViewedStore.instance.load().then((_) {
        if (mounted) RecentlyViewedStore.instance.record(_savedProduct);
      });
      // The server keeps its own recently-viewed list for signed-in shoppers,
      // so the same visit counts on the web storefront too.
      unawaited(
        ProductRepository.instance.recordView(
          numIid: widget.product.numIid,
          name: widget.product.title,
          imageUrl: widget.product.imageUrl,
          priceLabel: widget.product.hasPrice
              ? formatRupees(widget.product.displayPrice!)
              : null,
        ),
      );
    });
  }

  ProductDetail get _product => _detail;

  /// Fetches the full record and, once it lands, the rest of its department.
  Future<void> _loadDetail() async {
    try {
      final body = await ProductRepository.instance.detail(
        widget.product.numIid,
      );
      if (!mounted) return;
      final detail = ProductDetail.fromApi(body, fallback: widget.product);
      setState(() {
        _detail = detail;
        _detailError = null;
        _matrix = VariantMatrix.from(detail.variants);
        // The preview's SKU ids are not the record's, so anything typed into a
        // grid drawn from the preview would be an order against ids the server
        // does not have.
        _picked.clear();
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

  /// The site's shipping settings, cached across the run by the repository.
  Future<void> _loadShipping() async {
    try {
      final shipping = await StorefrontConfigRepository.instance.shipping();
      if (mounted) setState(() => _shipping = shipping);
    } on ApiError {
      // Silent, and the card stays away. A promise about delivery that could
      // not be fetched is one the page should not be making up.
    }
  }

  /// More from the same department. Real products rather than a hand-picked
  /// list, so it stays right as the catalogue changes.
  Future<void> _loadSimilar(ProductDetail detail) async {
    // Two id spaces, and asking the wrong endpoint is answered with an empty
    // list rather than an error -- which is what left this shelf missing on
    // every product opened from search.
    //
    // The record from `/api/1688/product` carries a 1688 leaf category, which
    // only the keyword endpoint can read. The card the shopper tapped carries
    // the storefront's own cid, but only when it came from the cached index:
    // keyword results carry no category at all. So each id is put to the
    // endpoint that understands it, nearest match first.
    final offerCid = detail.categoryCid;
    final storeCid = widget.product.categoryCid;
    if (offerCid == null && storeCid == null) return;
    try {
      var products = const <Product>[];
      if (offerCid != null) {
        products = await CatalogRepository.instance.categoryOffers(offerCid);
      }
      if (products.isEmpty && storeCid != null && storeCid != offerCid) {
        products = await CatalogRepository.instance.categoryProducts(
          storeCid,
          pageSize: 12,
        );
      }
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

  /// True while the visual-search screen is being pushed, so a second tap on
  /// the icon cannot stack a second search for the same picture.
  bool _searchingImage = false;

  /// Looks for products that look like the photograph on screen.
  ///
  /// The catalogue's own address for the picture goes to the image-search
  /// service, which fetches it itself -- so nothing is downloaded here and
  /// re-uploaded, and the search is against the real photograph rather than a
  /// re-encoding of it.
  Future<void> _searchByImage(String imageUrl) async {
    if (_searchingImage || imageUrl.isEmpty) return;
    setState(() => _searchingImage = true);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VisualSearchScreen.forImageUrl(imageUrl: imageUrl),
      ),
    );
    if (mounted) setState(() => _searchingImage = false);
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
    // The same "was" figure the page is showing, so the cart does not quietly
    // disagree with the page a shopper just read it from.
    listPrice: _listPrice,
    // The chosen colourway's own photo, so two variants of one product are
    // told apart at a glance in the cart instead of showing the same picture
    // twice with only a text label between them.
    imageUrl:
        _selectedVariant?.imageUrl ??
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
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CartScreen()));
  }

  // --- The grid path -------------------------------------------------------
  //
  // A two-axis listing is bought by the tableful: a buyer types quantities into
  // several colour-and-size squares and adds them in one go. Everything below
  // exists because that is a set of cart lines rather than one, and because the
  // wholesale price band is set by the whole order rather than by each square.

  /// The SKUs with a quantity against them, paired with it.
  List<(ProductVariant, int)> get _pickedLines {
    final matrix = _matrix;
    if (matrix == null) return const [];
    final lines = <(ProductVariant, int)>[];
    // Walked in grid order rather than in map order, so the cart lists the
    // colours in the order the buyer read them down the table.
    for (final row in matrix.rows) {
      for (final column in matrix.columns) {
        final variant = matrix.at(row.value, column);
        final skuId = variant?.skuId;
        if (variant == null || skuId == null) continue;
        final quantity = _picked[skuId] ?? 0;
        if (quantity > 0) lines.add((variant, quantity));
      }
    }
    return lines;
  }

  int get _pickedPieces => _pickedLines.fold(0, (sum, line) => sum + line.$2);

  /// What one piece of [variant] costs on an order of [_pickedPieces].
  ///
  /// The SKU's own price where the seller set one, and otherwise the band the
  /// whole order falls into -- not the band each square would fall into alone.
  /// A buyer taking fifty pieces across five colours has ordered fifty, and
  /// pricing each colour as an order of ten would quietly overcharge them.
  num _pickedUnitPrice(ProductVariant variant) =>
      variant.price ?? _product.priceAt(_pickedPieces);

  num get _pickedTotal => _pickedLines.fold<num>(
    0,
    (sum, line) => sum + _pickedUnitPrice(line.$1) * line.$2,
  );

  /// One cart line per square with something in it.
  List<CartLine> get _pickedCartLines => _pickedLines
      .map(
        (line) => CartLine(
          productId: _productId,
          variantLabel: line.$1.label,
          title: _product.title,
          unitPrice: _pickedUnitPrice(line.$1),
          listPrice: _product.listPrice,
          imageUrl: line.$1.imageUrl.isNotEmpty
              ? line.$1.imageUrl
              : (_product.images.isEmpty ? null : _product.images.first),
          quantity: line.$2,
          // The minimum is on the order as a whole and has already been checked
          // against it. Repeating it on each line would have the cart refuse a
          // colour the buyer only took two of as part of a valid order of fifty.
          minOrder: 1,
          freeDelivery: _product.freeDelivery,
          category: _product.category,
          source: '1688',
          skuId: line.$1.skuId,
          specId: line.$1.specId,
        ),
      )
      .toList(growable: false);

  void _setPicked(String skuId, int quantity) {
    setState(() {
      if (quantity <= 0) {
        _picked.remove(skuId);
      } else {
        _picked[skuId] = quantity;
      }
    });
  }

  /// Why the grid cannot be ordered yet, or null when it can.
  String? get _pickedBlocker {
    final pieces = _pickedPieces;
    if (pieces == 0) {
      return 'Enter how many you want of at least one option.';
    }
    final minimum = _product.minOrder;
    if (minimum > 1 && pieces < minimum) {
      return 'This seller takes orders of $minimum or more. '
          'You have $pieces.';
    }
    return null;
  }

  /// Adds every square with something in it, and reports what went in.
  bool _addPickedToCart() {
    final blocker = _pickedBlocker;
    if (blocker != null) {
      _snack(blocker);
      return false;
    }
    final lines = _pickedCartLines;
    var inCart = 0;
    for (final line in lines) {
      inCart = CartStore.instance.add(line);
    }
    final pieces = _pickedPieces;
    _snack2(
      'Added $pieces ${pieces == 1 ? 'piece' : 'pieces'} across '
      '${lines.length} ${lines.length == 1 ? 'option' : 'options'}. '
      '$inCart in cart.',
    );
    setState(_picked.clear);
    return true;
  }

  /// A snack with a way through to the cart, which the plain [_snack] has not.
  void _snack2(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(label: 'View cart', onPressed: _openCart),
        ),
      );
  }

  /// Opens the quote request over the product it is about.
  Future<void> _requestQuote() async {
    // `/product-requests` is an authenticated endpoint, so a guest would get a
    // 401 after typing the whole thing out. Said first instead.
    if (AuthStore.instance.account == null) {
      _snack('Sign in to request a quote');
      return;
    }
    final sent = await ProductQuoteSheet.show(
      context,
      product: _product,
      // Whatever the page is showing, so the seller quotes the option that was
      // actually being looked at.
      variantLabel: _matrix == null ? _selectedVariant?.label : null,
    );
    if (!mounted || sent != true) return;
    _snack('Quote request sent. The seller will come back to you.');
  }

  /// Opens the detail strip in the zoom viewer.
  ///
  /// Its own list rather than the gallery's: these are a different set of
  /// pictures, and paging out of one into the other would be a viewer that
  /// jumps somewhere the shopper did not open.
  void _openDetailImage(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          images: _product.detailImages,
          initialIndex: index,
        ),
      ),
    );
  }

  void _openVariantImage(VariantRow row) {
    if (row.imageUrl.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(images: [row.imageUrl]),
      ),
    );
  }

  /// What one of these costs right now.
  ///
  /// Three things can move it: the option chosen, the quantity -- wholesale
  /// listings price in bands -- and neither, in which case it is the headline
  /// price. Worked out in one place so the buy bar and the cart line cannot
  /// disagree about it.
  num get _unitPrice => _selectedVariant?.price ?? _product.priceAt(_quantity);

  /// Whether this page knows what the thing in front of the shopper costs.
  ///
  /// A catalogue row without a price seeds the preview record with zero
  /// (`ProductDetail.fromProduct`), and a grid has no total until a square is
  /// filled in. Both used to render as "Rs. 0", which is a claim that the
  /// product is free rather than an admission that the price is not in yet.
  /// Nothing in this catalogue is free, so zero always means "not known".
  bool get _priceKnown => _matrix == null ? _unitPrice > 0 : _pickedTotal > 0;

  /// What to say instead of a price, chosen by why it is missing.
  ///
  /// An unfilled grid or an unchosen variant is a question the shopper can
  /// answer. A listing with neither is one whose price simply has not arrived,
  /// and telling them to pick something they cannot see would be a dead end.
  String get _priceUnknownLabel =>
      _matrix != null || _product.variants.isNotEmpty
      ? 'Select an option'
      : 'Price unavailable';

  /// The offer, until its countdown runs out under the shopper.
  ///
  /// Cleared rather than left in place: once the sale is over the badge, the
  /// band and the struck price are all claims about a price that is no longer
  /// being offered, and the page has to stop making them.
  ProductDeal? get _deal => _dealEnded ? null : widget.deal;
  bool _dealEnded = false;

  /// The "was" price this page should strike through.
  ///
  /// The record's own list price wins when the server published one -- that is
  /// a real figure and the offer's is derived. Otherwise the offer's
  /// percentage is rescaled to whatever the current variant and quantity
  /// actually cost.
  num? get _listPrice => _product.listPrice ?? _deal?.listPriceFor(_unitPrice);

  int? get _discountPercent {
    final list = _listPrice;
    if (list == null || list <= _unitPrice) return null;
    return _product.listPrice != null
        ? _product.discountPercent
        : _deal?.discountPercent;
  }

  /// True when the page is sitting on an option that cannot be bought -- every
  /// variant sold out, so there is nothing to default to.
  bool get _selectionUnavailable => _selectedVariant?.inStock == false;

  void _addToCart() {
    if (_matrix != null) {
      _addPickedToCart();
      return;
    }
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
    if (_matrix != null) {
      // Buy now is still add-to-cart that keeps going, so a grid order arrives
      // at checkout as the same set of lines it would have arrived as anyway.
      if (_addPickedToCart()) _openCart();
      return;
    }
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
    listPrice: _listPrice,
    imageUrl: _product.images.isEmpty ? null : _product.images.first,
    // Snapshotted with the rest, so the saved list renders on a dead
    // connection and still shows what was saved after the listing moves on.
    sellerBadge: widget.product.sellerBadge,
    salesLabel: widget.product.salesLabel,
    category: _product.category,
    minOrder: _product.minOrder,
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
    // The offer's figures when the page was opened from one, the record's own
    // otherwise. Same two locals the price block below already used, so nothing
    // there had to move.
    final discount = _discountPercent;
    final list = _listPrice;
    final deal = _deal;
    final vat = product.vatIncluded;
    final sold = product.soldCount;
    final matrix = _matrix;

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
              // Beside Save and Share rather than in a card down the page.
              // Asking the seller to price something is an action about this
              // product, which is what this row is for, and it stays reachable
              // from anywhere in a long listing.
              IconButton(
                icon: const Icon(Icons.request_quote_outlined),
                tooltip: 'Request a quote',
                onPressed: _requestQuote,
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
              // The gallery is untouched; the badge is laid over its corner and
              // the band added beneath it.
              if (deal == null)
                ProductGallery(
                  images: product.images,
                  videoUrl: product.videoUrl,
                  onImageTap: _openViewer,
                  onSearchImage: _searchByImage,
                )
              else ...[
                Stack(
                  children: [
                    ProductGallery(
                      images: product.images,
                      videoUrl: product.videoUrl,
                      onImageTap: _openViewer,
                      onSearchImage: _searchByImage,
                    ),
                    if (deal.discountPercent > 0)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: ProductDealBadge(percent: deal.discountPercent),
                      ),
                  ],
                ),
                ProductDealBanner(
                  deal: deal,
                  now: widget.now,
                  onEnded: () {
                    if (mounted) setState(() => _dealEnded = true);
                  },
                ),
              ],
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
                          const Icon(
                            Icons.star,
                            size: 16,
                            color: AppColors.star,
                          ),
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
                        // The headline price, or what to do about not
                        // having one. A row that reached this page without a
                        // price seeds the record with zero, and printing that
                        // told the shopper the product was free.
                        Text(
                          product.price > 0
                              ? formatRupees(product.price)
                              : _priceUnknownLabel,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: product.price > 0
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
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
                              color: AppColors.successInk,
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
                    // Only where the offer published them. The catalogue has
                    // neither figure, so on a real payload this draws nothing
                    // rather than a meter with nothing behind it.
                    if (deal != null &&
                        (deal.item.soldPercent != null ||
                            deal.item.stock != null)) ...[
                      const SizedBox(height: 12),
                      ProductDealStock(
                        soldPercent: deal.item.soldPercent,
                        stock: deal.item.stock,
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Two axes are bought by the tableful; one is bought by
                    // picking it. The grid is not forced onto a listing that
                    // does not have the shape for it -- see [VariantMatrix].
                    if (matrix != null)
                      VariantMatrixTable(
                        matrix: matrix,
                        quantities: _picked,
                        total: _pickedTotal,
                        minOrder: product.minOrder,
                        onChanged: _setPicked,
                        onImageTap: _openVariantImage,
                      )
                    else ...[
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
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Directly above the returns and warranty row, which is the rest
              // of what a buyer checks before committing.
              if (_shipping != null)
                DeliveryGuaranteeCard(guarantee: _shipping!.guarantee),
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
              // Two panels rather than a strip of tabs. Both start closed:
              // between them they run to a screen or three of table and
              // photography, and a shopper looking for the ratings below
              // should not have to scroll past all of it.
              //
              // Each is drawn only when the listing has something to put in
              // it, so neither is ever a control that opens onto nothing.
              const SizedBox(height: 8),
              if (product.specs.isNotEmpty)
                ProductSectionPanel(
                  title: 'Specifications',
                  child: _SpecTable(specs: product.specs),
                ),
              if (product.detailImages.isNotEmpty)
                ProductSectionPanel(
                  title: 'Detail images',
                  // Said on the closed panel, so the count is known before it
                  // is opened -- which is what the old tab label carried.
                  trailingLabel: '${product.detailImages.length}',
                  child: ProductDetailImages(
                    images: product.detailImages,
                    onImageTap: _openDetailImage,
                  ),
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
                // A grid rather than a rail: two cards across, the same shape
                // the home page's "Discover something new" uses, so the shelf
                // reads as a set to browse rather than one more thing to swipe
                // at the bottom of a long page. The column count is the card's
                // own `columnsFor`, so it stays right on a wider screen.
                ProductGrid(
                  title: 'More in ${product.category ?? 'this department'}',
                  leadingIcon: Icons.compare_arrows,
                  products: _similar,
                  onSeeAll: product.categoryCid == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SearchResultsScreen(
                              query: '',
                              categoryCid: product.categoryCid,
                            ),
                          ),
                        ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ],
      ),
      bottomNavigationBar: _BuyBar(
        total: matrix == null ? _unitPrice * _quantity : _pickedTotal,
        // What the bar is about to buy, when that is more than one thing. The
        // picker path buys the one option named above it and needs no caption.
        subtitle: matrix == null || _pickedPieces == 0
            ? null
            : '$_pickedPieces across ${_pickedLines.length} '
                  '${_pickedLines.length == 1 ? 'option' : 'options'}',
        // Nothing typed into the grid is nothing to buy, and neither is a
        // listing whose price is not known yet. The grid states its own reason
        // in the summary directly above, so a dead button here is not a dead
        // end. Refusing the tap is also what stops a Rs. 0 line reaching the
        // cart, where it would be charged as free.
        enabled: (matrix == null || _pickedPieces > 0) && _priceKnown,
        // Until there is a price to show, the button asks for one instead of
        // printing Rs. 0 -- which reads as a free product rather than as a
        // question the shopper has not answered yet.
        selectionPrompt: _priceKnown ? null : _priceUnknownLabel,
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
                    // The caption, one step up from 11pt: it names what the
                    // fact underneath it is -- Brand, Model -- and at the old
                    // size it was the smallest type on the page.
                    Text(
                      item.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // The fact itself, which is what a shopper is scanning
                    // this block for: 16pt at full weight rather than 14pt at
                    // w600. Nothing else moves -- same grid, same gap, same
                    // colours -- the block only grows taller by the extra
                    // line height.
                    Text(
                      item.value,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
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
    this.subtitle,
    this.enabled = true,
    this.selectionPrompt,
  });

  final num total;

  /// Shown on the buy button in place of the total, while there is nothing
  /// chosen to total up.
  ///
  /// A grid listing has no price until a square has a quantity in it, and
  /// formatting that absence as a total reads as a free product rather than
  /// an unanswered question. The price is not zero; it is not yet known.
  final String? selectionPrompt;

  /// What is being bought, when it is more than one option.
  final String? subtitle;

  final bool enabled;
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
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null) ...[
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: enabled ? onAddToCart : null,
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      label: const Text('Add to cart'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: enabled ? onBuyNow : null,
                      child: Text(
                        selectionPrompt ?? 'Buy · ${formatRupees(total)}',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
