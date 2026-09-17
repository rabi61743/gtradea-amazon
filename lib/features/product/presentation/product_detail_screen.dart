import 'dart:async';

import 'package:flutter/material.dart';

import '../../restock/presentation/restock_request_bar.dart';

import 'package:share_plus/share_plus.dart';

import '../../../core/ui/action_status.dart';
import '../../../../core/network/api_error.dart';
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
import '../../search/widgets/product_result_card.dart' show ResultGridSpec;
import '../../home/widgets/product_rail.dart';
import '../../search/presentation/search_results_screen.dart';
import '../../search/presentation/visual_search_screen.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../data/product_detail_content.dart';
import '../data/product_repository.dart';
import '../../wishlist/data/wishlist_store.dart';
import '../widgets/product_logistics_section.dart';
import '../widgets/logistics_trust_card.dart';
import '../widgets/product_type_scale.dart';
import '../widgets/product_detail_images.dart';
import '../widgets/product_detail_skeleton.dart';
import '../widgets/product_summary_card.dart';
import '../widgets/animated_add_to_cart_button.dart';
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

  /// Whether the Highlights card is showing everything it has.
  bool _highlightsExpanded = false;

  /// Price, struck price and saving.
  ///
  /// Lifted out of build so the minimum-order pill can sit beside it in a row
  /// rather than under it. The widget itself is unchanged -- same Wrap, same
  /// wrapping behaviour when the three pieces will not fit on one line.
  Widget _priceBlock(
    ThemeData theme, {
    required ProductDetail product,
    num? list,
    int? discount,
  }) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 2,
      children: [
        // The headline price, or what to do about not
        // having one. A row that reached this page without a
        // price seeds the record with zero, and printing that
        // told the shopper the product was free.
        // The price of one at the quantity in front of the shopper, not the
        // listing's price of one. On a laddered listing those differ the
        // moment the stepper crosses a rung, and a headline that kept saying
        // the one-piece figure disagreed with the total on the buy bar.
        if (product.price > 0)
          // "Rs." and the figure are one line of text in two sizes, so the
          // prefix rides the digits' baseline however the number wraps.
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Rs. ', style: ProductType.currency(theme)),
                TextSpan(
                  text: formatRupees(_headlinePrice).substring(4),
                  style: ProductType.price(theme),
                ),
              ],
            ),
          )
        else
          // A row that reached this page without a price seeds the record
          // with zero, and printing that told the shopper it was free.
          Text(
            _priceUnknownLabel,
            style: ProductType.price(theme)
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        if (list != null && discount != null) ...[
          Text(
            formatRupees(list),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
              decorationColor: theme.colorScheme.onSurfaceVariant,
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
    );
  }

  /// Whether the seller wrote anything worth showing.
  ///
  /// The catalogue's `description` is HTML, and on most listings it holds
  /// nothing but the detail photographs -- which strip to an empty string.
  /// That is not a description, and printing the empty result would be a
  /// blank paragraph under a heading.
  bool get _hasDescription => _detail.description.trim().isNotEmpty;

  /// Where the rest of what the seller supplied can be found.
  static String _elsewhere(ProductDetail product) {
    final places = [
      if (product.specs.isNotEmpty) 'the specifications',
      if (product.detailImages.isNotEmpty) "the seller's photographs",
    ];
    return 'What they did supply is in ${places.join(' and ')} below.';
  }

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

  /// Set when the full record could not be fetched. The page then falls
  /// back to the card's own data underneath the error -- a title and a
  /// price the shopper just saw are worth more than an error page.
  ApiError? _detailError;

  /// Which fetch the page is waiting on.
  ///
  /// Bumped every time one starts, so a response that arrives after another
  /// has been asked for is dropped rather than painted. Without it, a slow
  /// answer for the product looked at a moment ago can land on the product
  /// being looked at now.
  int _fetch = 0;

  /// True until the record for [widget.product] is on screen.
  ///
  /// The page is opened from a catalogue row, which carries a title, a price
  /// and one picture -- and nothing of the gallery, the options, the facts or
  /// the photographs. Rendering that row means a page that is half built and
  /// then rearranges itself as the record lands. The skeleton holds the shape
  /// instead, and nothing product-specific is drawn until the record for this
  /// product is in hand.
  bool get _loadingDetail => _detail.isPreview && _detailError == null;

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
    final firstInStock = _detail.variants.indexWhere(
      (variant) => variant.inStock,
    );
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

  /// A different product handed to a page that is already on screen.
  ///
  /// Ordinarily each product is its own route and this never runs. It runs
  /// when something swaps the product underneath the page -- a deep link
  /// resolving, a route replaced rather than pushed -- and without it every
  /// piece of state below belongs to the product before: the record, the
  /// options, the quantities typed into the grid, the department rail. All of
  /// it is dropped, and the page goes back to its skeleton until the new
  /// record lands.
  @override
  void didUpdateWidget(covariant ProductDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.numIid == widget.product.numIid &&
        oldWidget.detail == widget.detail) {
      return;
    }

    setState(() {
      _detail = widget.detail ?? ProductDetail.fromProduct(widget.product);
      _matrix = VariantMatrix.from(_detail.variants);
      _picked.clear();
      _variant = 0;
      _quantity = _detail.minOrder > 0 ? _detail.minOrder : 1;
      _detailError = null;
      _similar = const [];
      _descriptionExpanded = false;
      _highlightsExpanded = false;
      _dealEnded = false;
    });

    if (widget.detail == null) unawaited(_loadDetail());
  }

  ProductDetail get _product => _detail;

  /// Fetches the full record and, once it lands, the rest of its department.
  Future<void> _loadDetail() async {
    final fetch = ++_fetch;
    final wanted = widget.product.numIid;
    if (_detailError != null) setState(() => _detailError = null);

    try {
      final body = await ProductRepository.instance.detail(wanted);
      // Three ways this answer can be the wrong one to paint: the page is
      // gone, another fetch has been asked for since, or the service
      // answered about a different product than the one asked for.
      if (!mounted || fetch != _fetch) return;
      final detail = ProductDetail.fromApi(body, fallback: widget.product);
      if (detail.numIid.isNotEmpty && detail.numIid != wanted) return;
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
      // The rest of the department, after the product itself is on screen.
      // Never before it: nothing about this page waits on a request for
      // anything other than the product being looked at.
      unawaited(_loadSimilar(detail));
    } on ApiError catch (e) {
      if (mounted && fetch == _fetch) setState(() => _detailError = e);
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
    // The ladder travels with the line when the price came from it, so the
    // cart reprices as the quantity changes there. An option the seller
    // prices on its own is not on the ladder.
    tiers: _selectedVariant?.price == null ? _product.tiers : const [],
  );

  /// What the freight quote is asked about.
  ///
  /// The same lines the cart would receive, so a figure the logistics section
  /// shows is a figure for this order rather than for a rounded-off version of
  /// it: a grid listing quotes every square that has a quantity typed into it,
  /// and everything else quotes the one line it would add.
  ///
  /// Empty while a grid has nothing typed in yet -- there is no order to price
  /// until there is.
  List<CartLine> get _quoteLines =>
      _matrix == null ? [_cartLine] : _pickedCartLines;

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
          // As on the single-option line: the ladder goes with the line when
          // the price came from it.
          tiers: line.$1.price == null ? _product.tiers : const [],
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
    final added = _putPickedInCart();
    if (added == null) return false;
    _sayPickedAdded(added);
    return true;
  }

  /// The grid's picks into the cart, or null (having said why) when they
  /// cannot go. Returns the lines added and the resulting count in the cart.
  (List<CartLine>, int, int)? _putPickedInCart() {
    final blocker = _pickedBlocker;
    if (blocker != null) {
      _snack(blocker);
      return null;
    }
    final lines = _pickedCartLines;
    final pieces = _pickedPieces;
    var inCart = 0;
    for (final line in lines) {
      inCart = CartStore.instance.add(line);
    }
    setState(_picked.clear);
    return (lines, pieces, inCart);
  }

  void _sayPickedAdded((List<CartLine>, int, int) added) {
    final (lines, pieces, inCart) = added;
    _snack2(
      'Added $pieces ${pieces == 1 ? 'piece' : 'pieces'} across '
      '${lines.length} ${lines.length == 1 ? 'option' : 'options'}. '
      '$inCart in cart.',
    );
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

  /// The quantity the bulk ladder is read at.
  ///
  /// The same one [_unitPrice] and [_pickedUnitPrice] pass to
  /// [ProductDetail.priceAt], so the rung drawn as current is the rung being
  /// charged: the stepper's count normally, and the pieces typed into the grid
  /// where there is one.
  int get _tierQuantity => _matrix == null ? _quantity : _pickedPieces;

  /// Whether the ladder is what the shopper will actually be charged.
  ///
  /// A single rung is just the headline price again, and a variant that
  /// carries its own price overrides the ladder entirely -- drawing it in
  /// either case would put a table on the page that the total underneath
  /// contradicts.
  bool get _tiersGovernPrice {
    if (_product.tiers.length < 2) return false;
    if (_matrix == null) return _selectedVariant?.price == null;
    // A grid can price individual squares. Where any square does, the ladder
    // is not the whole story.
    return _product.variants.every((v) => v.price == null);
  }

  /// The price of one to print at the top of the page.
  ///
  /// The rung the current quantity reaches where the ladder governs the price,
  /// the record's own figure otherwise. The headline used to be fixed at the
  /// listing's one-piece price, which contradicted both the ladder drawn
  /// beneath it -- whose current rung had moved -- and the total on the buy
  /// bar, the moment the stepper crossed a boundary.
  num get _headlinePrice =>
      _tiersGovernPrice ? _product.priceAt(_tierQuantity) : _product.price;

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

  /// Why nothing on this page can be bought right now, or null when something
  /// can -- in which case the page keeps its buy bar.
  ///
  /// Only what the catalogue actually says: the product itself gone, a grid
  /// with no option in stock, or every option sold out. One sold-out option
  /// beside others that are in stock is not this; the others can be bought.
  String? get _unavailableReason {
    if (_loadingDetail) return null;
    if (_detailError?.isNotFound ?? false) {
      return 'This product is no longer available.';
    }
    final matrix = _matrix;
    if (matrix != null) {
      return matrix.buyable.isEmpty ? 'Every option is sold out.' : null;
    }
    final variants = _product.variants;
    if (variants.isNotEmpty && variants.every((variant) => !variant.inStock)) {
      return 'Every option is sold out.';
    }
    return null;
  }

  /// Adds to the cart and completes with whether it is really there.
  ///
  /// The same add the page always made -- the same line or grid picks, the
  /// same sold-out and quantity rules, the one cart store -- followed by
  /// waiting for that store to save the change to the account before calling
  /// it done. The animated button turns to "Added" only on true, and the
  /// "added" message is said only then too. A guest's cart lives on the
  /// device, so for a guest the add itself is the confirmation.
  Future<bool> _addToCart() async {
    final List<CartLine> lines;
    final void Function() sayAdded;
    if (_matrix != null) {
      final added = _putPickedInCart();
      if (added == null) return false;
      lines = added.$1;
      sayAdded = () => _sayPickedAdded(added);
    } else {
      // Guarded here as well as in the picker. A rule that lives only in a
      // widget is one the next entry point into this page walks straight
      // around.
      if (_selectionUnavailable) {
        _snack('${_selectedVariant!.label} is sold out');
        return false;
      }
      final line = _cartLine;
      CartStore.instance.add(line);
      lines = [line];
      // No popup here: the button's own "Added to cart" is the confirmation.
      sayAdded = () {};
    }

    final keys = [for (final line in lines) line.key];
    final saved = await _confirmSaved(keys);
    if (!mounted) return saved;
    if (saved) {
      sayAdded();
    } else {
      final store = CartStore.instance;
      final refused = keys.map((key) => store.rejected[key]).nonNulls;
      _snack(
        refused.firstOrNull?.message ??
            store.syncError?.message ??
            'Could not add this to your cart. Please try again.',
      );
    }
    return saved;
  }

  /// Waits for the cart store to save the lines with these [keys] to the
  /// account, and says whether it did.
  ///
  /// Uses the store's own sync rather than a request of its own, so there is
  /// still one cart. A sync already under way is let finish first -- it may
  /// have started before these lines were added -- and then one more is run
  /// that certainly includes them. Saved means the server has given each line
  /// its own id and refused none of them.
  Future<bool> _confirmSaved(List<String> keys) async {
    final store = CartStore.instance;
    if (store.isGuestCart) return true;
    if (store.isSyncing) {
      final idle = Completer<void>();
      void listener() {
        if (!store.isSyncing && !idle.isCompleted) idle.complete();
      }

      store.addListener(listener);
      try {
        await idle.future.timeout(const Duration(seconds: 20));
      } on TimeoutException {
        return false;
      } finally {
        store.removeListener(listener);
      }
    }
    await store.syncNow();
    // Refused lines are these lines' problem only if they are these lines; a
    // different line already in the cart being refused says nothing about
    // this add. A sync error with nothing refused is the whole save failing.
    // These lines, and nothing else in the cart. A cart of seventy lines can
    // carry an error about one of the others -- a `category_restricted` line
    // from a month ago -- and the whole-cart `syncError` says so. Judging this
    // add by that error called a save that had plainly worked a failure: the
    // account had the line, with its own id, and the button still went back to
    // "Add to cart". A line the server did not take has no id, which is what
    // actually answers the question asked here.
    if (store.rejected.keys.any(keys.contains)) return false;
    final held = {for (final line in store.lines) line.key: line};
    return keys.every((key) => held[key]?.serverId != null);
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
    // The tax inside the figure the price block is about to print, which on a
    // laddered listing is the rung, not the record's price of one.
    final vat = ProductDetail.vatInside(_headlinePrice);
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
                      // Only the removal is said out loud: the filled heart
                      // is what says it was saved.
                      if (!nowSaved) {
                        ActionStatus.show(
                          context,
                          ActionStatus.removedFromWishlist,
                        );
                      }
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
          if (_loadingDetail)
            // Nothing of this product -- or of the last one -- until the
            // record for it is in hand.
            const SliverToBoxAdapter(child: ProductDetailSkeleton())
          else
            SliverList.list(
              children: [
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
                Center(
                  // 97% of the page, centred in it, which is the measure every
                  // card down this page shares -- see [cardWidthFactor]. A
                  // share of the width rather than a fixed inset, so it sits
                  // right on a phone, a tablet and a desktop window.
                  child: FractionallySizedBox(
                    widthFactor: cardWidthFactor,
                    // One card for everything about the thing being bought:
                    // its photographs, its name, what it costs, which option,
                    // how many, the summary of that choice, and how it will be
                    // carried. They are one decision, and each of those in a
                    // card of its own read as several.
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        // All four corners now that the card no longer runs to
                        // the screen edges: the top-only rounding existed
                        // because a rounded corner against the edge reads as a
                        // card that failed to reach it.
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusSection,
                        ),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      // So a photograph cannot paint over the rounded top.
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The photographs, at the top of the card and the
                          // full width of it. The gallery is unchanged: same
                          // aspect, same swiping, same video tab, same tap to
                          // the full-screen viewer.
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
                                    child: ProductDealBadge(
                                      percent: deal.discountPercent,
                                    ),
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
                          // Everything the card says in words keeps its own
                          // padding, so only the photographs touch the edges.
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.title,
                                  // Three lines and then an ellipsis: wholesale titles
                                  // run to forty words of keywords, and the price
                                  // below is what the shopper came for.
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: ProductType.title(theme),
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
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '(${product.reviewCount})',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    if (sold != null)
                                      Text(
                                        '${_compact(sold)} sold',
                                        style: ProductType.meta(theme),
                                      ),
                                    if (product.sellerName != null) ...[
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Text(
                                          product.sellerName!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: ProductType.meta(theme),
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
                                // The price at the left, the minimum order at the right:
                                // the two halves of what a wholesale listing costs, on one
                                // line. The pill keeps its own width and the price takes
                                // what is left, so neither pushes the other off the edge.
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _priceBlock(
                                        theme,
                                        product: product,
                                        list: list,
                                        discount: discount,
                                      ),
                                    ),
                                    if (product.minOrder > 1) ...[
                                      const SizedBox(width: 12),
                                      _MinOrderPill(minOrder: product.minOrder),
                                    ],
                                  ],
                                ),
                                if (vat != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Includes ${formatRupees(vat)} VAT',
                                    style: ProductType.meta(theme),
                                  ),
                                ],
                                // The seller's bulk ladder, where the seller
                                // published one and where it is what decides
                                // the price. Beside the headline figure rather
                                // than further down the page: it explains that
                                // figure, and it changes as the stepper below
                                // it moves.
                                if (_tiersGovernPrice) ...[
                                  const SizedBox(height: 10),
                                  _PriceTiers(
                                    tiers: _product.tiers,
                                    unitLabel: _product.unitLabel,
                                    quantity: _tierQuantity,
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
                                const SizedBox(height: 12),
                                // Two axes are bought by the tableful; one is bought by
                                // picking it. The grid is not forced onto a listing that
                                // does not have the shape for it -- see [VariantMatrix].
                                if (matrix != null) ...[
                                  VariantMatrixTable(
                                    matrix: matrix,
                                    quantities: _picked,
                                    total: _pickedTotal,
                                    minOrder: product.minOrder,
                                    onChanged: _setPicked,
                                    onImageTap: _openVariantImage,
                                  ),
                                ] else ...[
                                  VariantPicker(
                                    label: product.variantLabel,
                                    variants: product.variants,
                                    selectedIndex: _variant,
                                    onSelected: (i) =>
                                        setState(() => _variant = i),
                                    category: product.category,
                                  ),
                                  const SizedBox(height: 12),
                                  _QuantityRow(
                                    quantity: _quantity,
                                    minOrder: product.minOrder,
                                    onChanged: (value) =>
                                        setState(() => _quantity = value),
                                  ),
                                ],
                                // What is about to be bought, gathered up after the
                                // options and the count have been chosen. Inside the
                                // same card, under a rule: the summary is a recap of
                                // the choices above it, not a separate section.
                                const SizedBox(height: 12),
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: theme.colorScheme.outlineVariant,
                                ),
                                const SizedBox(height: 10),
                                ProductSummaryCard(
                                  imageUrl:
                                      _selectedVariant?.imageUrl ??
                                      (product.images.isEmpty
                                          ? null
                                          : product.images.first),
                                  title: product.title,
                                  // A grid listing is bought by the tableful, so no
                                  // single option is 'the' one -- and the grid's own
                                  // labels carry the fitting guides it deliberately
                                  // trims from its headers.
                                  variantLabel: matrix == null
                                      ? _selectedVariant?.label
                                      : null,
                                  // A grid listing is priced per square, so its
                                  // summary is the pieces typed into it rather than
                                  // the stepper's count.
                                  unitPrice: matrix == null
                                      ? _unitPrice
                                      : (_pickedPieces == 0
                                            ? 0
                                            : _pickedTotal / _pickedPieces),
                                  quantity: matrix == null
                                      ? _quantity
                                      : _pickedPieces,
                                  unitLabel: product.unitLabel,
                                  priceKnown: _priceKnown,
                                ),
                                // How it gets here, in the same card and under
                                // the same rule as the summary: the way an order
                                // is carried is part of what is being bought,
                                // and a card of its own read as a separate
                                // offer. Priced for the choices made above it.
                                const SizedBox(height: 10),
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: theme.colorScheme.outlineVariant,
                                ),
                                const SizedBox(height: 4),
                                ProductLogisticsSection(lines: _quoteLines),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Close under the card above, by request. Four is the measure
                // the recommendation cards sit at, and the one every gap down
                // this page now uses: sixteen, then eight, still left a band of
                // empty page between things that describe the same product.
                const SizedBox(height: 0),
                // The standing guarantees, and only those. The delivery window
                // moved into the product card with the rest of the logistics
                // line -- drawing it here as well would be the same promise
                // made twice, in two places that could disagree.
                LogisticsTrustCard(assurances: product.assurances),
                if (product.highlights.isNotEmpty) ...[
                  // Four between sections, everywhere down this page: one
                  // rhythm rather than a different rule at each seam.
                  const SizedBox(height: 0),
                  _PanelCard(
                    title: 'Highlights',
                    // In the header, on the right, as the reference has it.
                    // Null where there is nothing left to reveal: a control
                    // that opens onto nothing is worse than none.
                    trailing:
                        product.highlights.length > _HighlightsGrid.compactCount
                        ? _ViewMoreButton(
                            expanded: _highlightsExpanded,
                            onPressed: () => setState(
                              () => _highlightsExpanded = !_highlightsExpanded,
                            ),
                          )
                        : null,
                    child: _HighlightsGrid(
                      highlights: product.highlights,
                      expanded: _highlightsExpanded,
                    ),
                  ),
                ],
                const SizedBox(height: 0),
                // Always below the Highlights card, as the design has it -- and
                // present even when the seller wrote nothing, which on this
                // catalogue is most of them: 1688 returns the description as a
                // block of images with no prose in it at all. Saying so is the
                // storefront's own answer, and it beats a section that silently
                // is not there on one product and is on the next.
                _PanelCard(
                  title: 'Description',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_hasDescription) ...[
                        Text(
                          product.description,
                          maxLines: _descriptionExpanded ? null : 3,
                          overflow: _descriptionExpanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: ProductType.description(theme),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => setState(
                              () =>
                                  _descriptionExpanded = !_descriptionExpanded,
                            ),
                            // Reads as a link, like the card headers' own
                            // control. A default text button carries a 48pt
                            // padded tap target and a gutter of its own, which
                            // put most of the gap between the description and
                            // the panel below it -- and set the label in from
                            // the prose it belongs to. Forty keeps a thumb
                            // target; the flush left edge lines it up with the
                            // text it opens.
                            style: TextButton.styleFrom(
                              foregroundColor: theme.colorScheme.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0,
                                vertical: 4,
                              ),
                              minimumSize: const Size(0, 40),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: Text(
                              _descriptionExpanded ? 'Show less' : 'Read more',
                            ),
                          ),
                        ),
                      ] else ...[
                        Text(
                          'The seller has not written a description for this '
                          'product.',
                          style: ProductType.description(
                            theme,
                          ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        // Where the rest of what they did supply actually is.
                        // Both are real sections on this page, and neither is
                        // opened for them: this only says where to look.
                        if (product.specs.isNotEmpty ||
                            product.detailImages.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            _elsewhere(product),
                            style: ProductType.meta(theme)
                                .copyWith(height: 1.35),
                          ),
                        ],
                      ],
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
                //
                // One gap, not two: this was a 4 and an 8 stacked, which is a
                // twelve nobody chose.
                const SizedBox(height: 0),

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
                    // The Future Cart shelf's compact gap, by request: the
                    // cards themselves are unchanged, they just sit closer.
                    spec: ResultGridSpec.compact,
                    // And the picture to the card's edges, by request.
                    imageFlush: true,
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
                const SizedBox(height: 16),
              ],
            ),
        ],
      ),
      // A product nobody can buy right now gets the one thing that can be
      // done about it, in the place the buttons that would refuse used to be.
      bottomNavigationBar: _unavailableReason != null
          ? RestockRequestBar(product: _product, reason: _unavailableReason!)
          : _BuyBar(
              // Held back while the record is in flight: the bar buys a variant
              // and a quantity this page does not know yet, and a price that
              // changes under a finger already on the button is worse than a
              // button that waits a moment for its figure.
              loading: _loadingDetail,
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
              enabled:
                  !_loadingDetail &&
                  (matrix == null || _pickedPieces > 0) &&
                  _priceKnown,
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
  const _HighlightsGrid({required this.highlights, this.expanded = false});

  final List<ProductSpec> highlights;

  /// Whether every fact is on screen, or only the first [compactCount].
  final bool expanded;

  /// Three rows of two: enough to answer "is this the right thing" without
  /// pushing the description off the screen.
  static const compactCount = 6;

  /// The reference draws the facts as a ruled table: two columns split by a
  /// hairline, a hairline between each pair of rows, and the control in the
  /// card's own header rather than under the grid.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final shown = expanded
        ? highlights
        : highlights.take(compactCount).toList(growable: false);

    // Two at a time, because the rule between the columns has to run the
    // full height of the pair it separates.
    final rows = <List<ProductSpec>>[
      for (var i = 0; i < shown.length; i += 2)
        shown.sublist(i, i + 2 > shown.length ? shown.length : i + 2),
    ];

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows) ...[
            if (row != rows.first)
              Divider(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _cell(theme, row.first, first: true)),
                  // No rule against an empty half: an odd number of facts
                  // leaves the last row single, and a divider with nothing
                  // beyond it reads as something failing to load.
                  if (row.length > 1) ...[
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    Expanded(child: _cell(theme, row[1], first: false)),
                  ] else
                    const Expanded(child: SizedBox.shrink()),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// One fact: its mark, what it is called, and what it says.
  Widget _cell(ThemeData theme, ProductSpec item, {required bool first}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(first ? 0 : 14, 10, first ? 14 : 0, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A mark for the kind of fact this is, as the design has it.
          // Chosen from the label the seller filed it under, and a neutral
          // one where that says nothing recognisable -- the icon is a hint,
          // never the information.
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              _iconFor(item.label),
              size: 22,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The caption: it names what the fact underneath it is --
                // Brand, Origin -- and is the quieter of the two.
                Text(item.label, style: ProductType.attributeLabel(theme)),
                const SizedBox(height: 2),
                // The fact itself, which is what a shopper is scanning this
                // block for.
                Text(item.value, style: ProductType.attributeValue(theme)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The mark beside a fact, from the words the seller filed it under.
  ///
  /// Matched loosely and case-insensitively, because these labels come from a
  /// wholesale catalogue and are written by hand: "Item No.", "Item number"
  /// and "Model number" are all the same kind of fact. Anything unrecognised
  /// gets the neutral mark rather than a wrong one.
  static IconData _iconFor(String label) {
    final text = label.toLowerCase();
    bool has(List<String> words) => words.any(text.contains);

    if (has(['brand', 'manufactur', 'supplier', 'factory'])) {
      return Icons.apartment_outlined;
    }
    if (has(['categor', 'type', 'use', 'applicable'])) {
      return Icons.sell_outlined;
    }
    if (has(['size', 'dimension', 'specification', 'weight', 'length'])) {
      return Icons.straighten_outlined;
    }
    if (has(['item no', 'item number', 'model', 'sku', 'article'])) {
      return Icons.description_outlined;
    }
    if (has(['origin', 'place', 'location', 'made in'])) {
      return Icons.place_outlined;
    }
    if (has(['pack', 'box', 'carton', 'bag'])) {
      return Icons.inventory_2_outlined;
    }
    if (has(['material', 'fabric', 'texture'])) {
      return Icons.layers_outlined;
    }
    if (has(['colour', 'color'])) return Icons.palette_outlined;
    if (has(['style', 'design', 'pattern'])) return Icons.brush_outlined;
    return Icons.label_outline;
  }
}

/// The header control that opens the rest of a card.
///
/// A text button stripped to its label and chevron: the reference sets it
/// in the header's quiet colour rather than as a filled control, and it is
/// meant to be read as a link.
class _ViewMoreButton extends StatelessWidget {
  const _ViewMoreButton({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        // Trust Blue, as every other thing on this page that can be pressed
        // is: the header's quiet grey read as a caption rather than as a
        // control, so nobody knew there was anything to open.
        foregroundColor: theme.colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(expanded ? 'View less' : 'View more'),
          const SizedBox(width: 2),
          Icon(expanded ? Icons.chevron_left : Icons.chevron_right, size: 18),
        ],
      ),
    );
  }
}

/// "Min. order: 500 pcs".
class _MinOrderPill extends StatelessWidget {
  const _MinOrderPill({required this.minOrder});

  final int minOrder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Min. order: ',
                style: ProductType.minOrder(theme),
              ),
              TextSpan(
                text: '$minOrder pcs',
                style: ProductType.minOrderValue(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The width the cards down this page share.
const cardWidthFactor = 0.97;

/// A titled white card, which is the shape the design gives Highlights and
/// Description.
class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;

  /// Sits at the right of the header, level with the title.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 97% of the page, centred in it: the margin is a share of the width
    // rather than a fixed inset, so the card sits right on a phone, a tablet
    // and a desktop window. The same measure as the two panels below it.
    return Center(
      child: FractionallySizedBox(
        widthFactor: cardWidthFactor,
        child: Container(
          // 16 all round, and the same 16 corner the logistics block above it
          // carries, so the three cards down this page read as one stack.
          // Trimmed a little at top and bottom. The heading and the content
          // keep their own spacing inside; what went was the card's own margin
          // around them, which is what made every panel taller than its words.
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusSection),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: ProductType.sectionHeading(theme),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
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
        Text('Quantity', style: ProductType.quantityLabel(theme)),
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
              // Tap to type. The upper rungs of a quantity ladder are hundreds
              // or thousands of pieces, and the stepper alone is a thousand
              // taps from the next price.
              Semantics(
                button: true,
                label: 'Quantity $quantity. Tap to type a quantity.',
                excludeSemantics: true,
                child: InkWell(
                  key: const ValueKey('quantity-value'),
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _type(context),
                  child: ConstrainedBox(
                    // Room for a wholesale figure: a 500-piece minimum runs to
                    // four digits, and 28pt clipped it.
                    constraints: const BoxConstraints(minWidth: 44),
                    child: Text(
                      '$quantity',
                      textAlign: TextAlign.center,
                      style: ProductType.quantityValue(theme),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'More',
                // The cart's own ceiling, so the page never offers a quantity
                // the cart would quietly cut.
                onPressed: quantity < CartStore.maxPerLine
                    ? () => onChanged(quantity + 1)
                    : null,
              ),
            ],
          ),
        ),
        const Spacer(),
        // The floor is stated up beside the price now, on the pill the design
        // puts there. Repeating it here was the same fact twice, and at four
        // digits it was what pushed this row off the edge.
      ],
    );
  }

  Future<void> _type(BuildContext context) async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _QuantityDialog(
        initial: quantity,
        minOrder: minOrder,
        max: CartStore.maxPerLine,
      ),
    );
    if (value != null && value != quantity) onChanged(value);
  }
}

/// A typed quantity, refused with the reason when it cannot be ordered.
class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({
    required this.initial,
    required this.minOrder,
    required this.max,
  });

  final int initial;
  final int minOrder;
  final int max;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final _controller = TextEditingController(text: '${widget.initial}');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    final String? error;
    if (value == null) {
      error = 'Enter a whole number of pieces.';
    } else if (value < widget.minOrder) {
      error = 'The minimum order is ${widget.minOrder}.';
    } else if (value > widget.max) {
      error = 'The most one order can take is ${widget.max}.';
    } else {
      error = null;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quantity'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          helperText: 'Minimum ${widget.minOrder}',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Set')),
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
                  vertical: 8,
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
    this.loading = false,
  });

  /// Whether the product this bar is for is still being fetched. The bar
  /// keeps its height -- it is what the page is laid out against -- and
  /// shows a bone where the total will be.
  final bool loading;

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

  /// Adds to the cart; completes with whether the cart really has it.
  final Future<bool> Function() onAddToCart;
  final VoidCallback onBuyNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The safe area inside the bar rather than around it: outside, the room
    // kept for the phone's gesture bar showed the grey page under the buttons.
    // The bar's own white now runs to the bottom edge, behind it.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
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
                  style: ProductType.meta(theme),
                ),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  Expanded(
                    // The page's own add, with the drop-into-the-cart
                    // interaction. This page only: every other add-to-cart in
                    // the app keeps its plain button.
                    child: AnimatedAddToCartButton(
                      enabled: enabled,
                      onAdd: onAddToCart,
                      textStyle: ProductType.cta(theme),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: enabled ? onBuyNow : null,
                      style: ElevatedButton.styleFrom(
                        // White on the brand blue, stated rather than
                        // inherited: this is the one control on the page
                        // that must not lose its contrast to a theme tweak.
                        foregroundColor: Colors.white,
                        textStyle: ProductType.cta(theme),
                      ),
                      // A six-figure wholesale total is wider than half a
                      // phone at 15pt, and a button whose label wraps onto
                      // two lines reads as broken. It shrinks to fit rather
                      // than wrapping or clipping the figure being agreed.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          loading
                              ? 'Buy'
                              : selectionPrompt ??
                                    'Buy · ${formatRupees(total)}',
                          maxLines: 1,
                        ),
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

/// The seller's bulk ladder, as the backend published it.
///
/// Every figure here comes off `quantityTiers` in the product record --
/// thresholds, prices, and the unit they are counted in. Nothing is computed
/// except the top of each band, which is the next threshold less one, and the
/// last band which has no top at all.
///
/// Drawn only where the ladder is what the shopper will actually be charged:
/// [ProductDetail.priceAt] is the same function the cart line and the buy bar
/// use, so the highlighted rung and the total below it cannot disagree.
class _PriceTiers extends StatelessWidget {
  const _PriceTiers({
    required this.tiers,
    required this.unitLabel,
    required this.quantity,
  });

  final List<QuantityTier> tiers;

  /// What the seller counts in -- pcs, pairs, sets. Theirs, not ours.
  final String unitLabel;

  /// What is currently being bought, which decides the rung.
  final int quantity;

  /// The rung this quantity falls on, or -1 while it is under the first one.
  int get _activeIndex {
    var active = -1;
    for (var i = 0; i < tiers.length; i++) {
      if (quantity >= tiers[i].minQuantity) active = i;
    }
    return active;
  }

  /// "100 - 9,999" for a band with a next rung above it, "10,000+" for the last.
  String _band(int i) {
    final from = _grouped(tiers[i].minQuantity);
    if (i == tiers.length - 1) return '$from+';
    return '$from - ${_grouped(tiers[i + 1].minQuantity - 1)}';
  }

  static String _grouped(int n) {
    final digits = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _activeIndex;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiers.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            _TierRow(
              band: '${_band(i)} $unitLabel',
              price: tiers[i].price!,
              // The tick and the tint say the same thing twice on purpose:
              // colour alone is not an answer for a shopper who cannot see it.
              current: i == active,
              quantity: quantity,
              first: i == 0,
              last: i == tiers.length - 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.band,
    required this.price,
    required this.current,
    required this.quantity,
    required this.first,
    required this.last,
  });

  final String band;
  final num price;
  final bool current;
  final int quantity;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = current
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: current
            ? theme.colorScheme.primary.withValues(alpha: 0.06)
            : null,
        // Only the corners that are actually corners, so the tint does not
        // square off the card it sits inside.
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(first ? AppTheme.radiusCard : 0),
          bottom: Radius.circular(last ? AppTheme.radiusCard : 0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            if (current) ...[
              Icon(Icons.check, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: Text(
                band,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: current ? ink : theme.colorScheme.onSurfaceVariant,
                  fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatRupees(price),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ink,
                fontWeight: current ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
