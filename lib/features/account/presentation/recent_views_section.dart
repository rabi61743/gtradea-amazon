import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/images/app_images.dart';
import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time_format.dart';
import '../../../core/ui/action_status.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../catalog/data/product.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../product/data/product_detail_content.dart';
import '../../product/data/product_repository.dart';
import '../../product/presentation/product_detail_screen.dart';
import '../../../shared/widgets/shimmer.dart';
import '../../wishlist/data/wishlist_store.dart';
import '../data/product_views_repository.dart';

/// Everything the shopper has opened lately, in one list.
///
/// The rows are the shop's own record at `/product-views` -- the same history
/// the product-history screen reads -- so the list is the account's, not this
/// device's, and it carries the time each product was actually opened.
///
/// It draws what that record holds and nothing else. The reference this was
/// built from also shows a feature line, a star rating, a badge and a
/// struck-through "was" price against each row; this catalogue publishes none
/// of those for a viewed product, and a rating or a discount invented here
/// would be a claim about a seller nobody made.
class RecentViewsSection extends StatefulWidget {
  const RecentViewsSection({
    super.key,
    required this.views,
    this.limit = shown,
  });

  /// The history to draw, as its caller already holds it.
  ///
  /// The product-history screen has fetched these rows before this section is
  /// ever built, and has filtered them by its own search, period and hidden
  /// list. Taking them rather than fetching means the section shows exactly
  /// what that screen shows, and asks the server nothing a second time.
  final List<ProductView> views;

  /// As many as the reference shows, where the section is a taste of the
  /// history rather than the history itself.
  static const shown = 10;

  /// How many rows to draw. [shown] by default; null for every one it was
  /// given, which is what the history screen asks for now that these rows
  /// are its list.
  final int? limit;

  /// Loads a card's picture into the image cache.
  ///
  /// Swapped out in tests, where an image decode begun inside the test clock
  /// never finishes -- the same reason the app's image provider is swapped.
  @visibleForTesting
  static Future<void> Function(BuildContext context, ImageProvider image)
  warmImage = _precache;

  static Future<void> _precache(BuildContext context, ImageProvider image) =>
      precacheImage(image, context, onError: (_, _) {});

  @override
  State<RecentViewsSection> createState() => _RecentViewsSectionState();
}

class _RecentViewsSectionState extends State<RecentViewsSection> {
  /// The catalogue's own record for a viewed product, once it has arrived.
  ///
  /// The history row carries a name, a picture, a price and a time and nothing
  /// else. The rating, the sold count behind a badge and the details under the
  /// title are the catalogue's, so they are read from it -- one request per
  /// row, shared and cached by [ProductRepository], and the row simply draws
  /// less until its answer lands.
  final Map<String, ProductDetail> _detail = {};
  final Set<String> _asked = {};

  /// Rows whose product record has been answered for -- with the record, or
  /// with a failure. Until then the row is drawn as a whole-card skeleton.
  ///
  /// This is the fix for the image arriving before the words. The history row
  /// carries only a name and a picture (measured: `product_data` holds
  /// `name` and `image_url`, nothing else); the description, the highlight,
  /// the department and the live price all come from the product record. A
  /// card drawn from the row alone showed its picture at once and then filled
  /// its price and description in a second or more later. Held back to one
  /// complete state, it appears with everything together.
  final Set<String> _settled = {};

  bool _rebuildQueued = false;

  /// How long a picture may keep a card waiting once its words are in. A slow
  /// image host must not hold a finished card back as a skeleton for good;
  /// past this the card shows, and the picture lands in its tile.
  static const imageGrace = Duration(seconds: 4);

  void _enrich(List<ProductView> views) {
    for (final view in views) {
      final id = view.productId;
      if (id.isEmpty || !_asked.add(id)) continue;
      // All of a batch at once, not queued: the batch is ten rows, and a
      // queue made the lower cards on screen wait out the upper ones.
      unawaited(_fetch(view));
    }
  }

  void _accept(String id, Map<String, dynamic> body) {
    final detail = ProductDetail.fromApi(body);
    // The answer has to be about the product that was asked for.
    if (detail.numIid == id) _detail[id] = detail;
  }

  /// The product record and the picture, side by side, and the card shown
  /// once both are in.
  ///
  /// Neither waits for the other to start: the picture's download begins in
  /// the same moment as the record's request. Showing the card on the record
  /// alone put its price and description on screen beside an empty tile, which
  /// is the same two-stage card the other way round.
  Future<void> _fetch(ProductView view) async {
    final id = view.productId;
    final url = view.imageUrl;
    final picture = url == null
        ? Future<void>.value()
        : RecentViewsSection.warmImage(context, _ViewRow.imageOf(context, url));

    // Fetched in the last few minutes -- by an earlier visit or the product
    // page -- is used as it is, with no second request.
    final cached = ProductRepository.instance.cachedDetail(id);
    if (cached != null) {
      _accept(id, cached);
    } else {
      try {
        _accept(id, await ProductRepository.instance.detail(id));
      } on ApiError {
        // A row that could not be enriched is drawn as the history recorded
        // it, rather than left as a skeleton forever.
      }
    }
    if (!mounted) return;
    await picture.timeout(imageGrace, onTimeout: () {});
    if (!mounted) return;
    _settled.add(id);
    _queueRebuild();
  }

  /// One rebuild per frame however many records land in it, rather than one
  /// per record: ten answers arriving together were ten rebuilds of the list.
  void _queueRebuild() {
    if (_rebuildQueued || !mounted) return;
    _rebuildQueued = true;
    scheduleMicrotask(() {
      _rebuildQueued = false;
      if (mounted) setState(() {});
    });
  }

  List<ProductView> get _views {
    final all = widget.views;
    final limit = widget.limit;
    return (limit == null || all.length <= limit) ? all : all.sublist(0, limit);
  }

  Product _productOf(ProductView view) => productStub(
    numIid: view.productId,
    title: view.title,
    imageUrl: view.imageUrl,
    displayPrice: view.price,
  );

  SavedProduct _savedOf(ProductView view) => SavedProduct(
    id: view.productId,
    title: view.title,
    price: view.price ?? 0,
    imageUrl: view.imageUrl,
  );

  void _open(ProductView view) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(product: _productOf(view)),
      ),
    );
  }

  void _toggleSaved(ProductView view) {
    final saved = WishlistStore.instance.toggle(_savedOf(view));
    // Only the removal is said out loud. Saving has its own animation now --
    // the heart flies to the Saved tab and the count moves with it -- so a
    // message repeating it in words was one confirmation too many.
    if (!saved) {
      ActionStatus.show(context, ActionStatus.removedFromWishlist);
    }
    setState(() {});
  }

  /// Buy now: the cart line this row is about, then the cart itself.
  ///
  /// The same thing the product page's own Buy now does -- add to cart and
  /// keep going -- rather than a second route to checkout with its own idea
  /// of what is being bought.
  void _buyNow(ProductView view) {
    // The catalogue's price where it has arrived, the history's otherwise.
    final price = _detail[view.productId]?.price ?? view.price;
    // A price nobody has published is not one to buy at: the product page
    // fetches the real figure, so that is where this goes instead.
    if (price == null || price <= 0) {
      _open(view);
      return;
    }

    CartStore.instance.add(
      CartLine(
        productId: view.productId,
        title: view.title,
        unitPrice: price,
        imageUrl: view.imageUrl,
        category: view.category,
      ),
    );
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CartScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (_views.isEmpty) return const SizedBox.shrink();
    _enrich(_views);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No strip at the head of the list. The rows are what this is, and
        // the page they sit on already says what page it is.
        for (final view in _views)
          if (!_settled.contains(view.productId) && view.productId.isNotEmpty)
            // The whole card in outline, at the card's own size, until its
            // record is in -- never a picture beside empty slots.
            const RecentViewsSkeleton(rows: 1)
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _Measure(
                child: _ViewRow(
                  view: view,
                  detail: _detail[view.productId],
                  saved: WishlistStore.instance.contains(view.productId),
                  onOpen: () => _open(view),
                  onSave: () => _toggleSaved(view),
                  onBuy: () => _buyNow(view),
                ),
              ),
            ),
      ],
    );
  }
}

/// The width every card in this history is drawn to.
///
/// 97% of whatever it is given, centred, so the air either side is a share of
/// the screen rather than a fixed inset -- the same card sits right on a
/// phone, a tablet and a desktop window.
class _Measure extends StatelessWidget {
  const _Measure({required this.child});

  final Widget child;

  static const widthFactor = 0.97;

  @override
  Widget build(BuildContext context) =>
      FractionallySizedBox(widthFactor: widthFactor, child: child);
}

/// One product the shopper opened, and what they can do about it.
///
/// The photograph beside the words: a square tile down the left of the card
/// with the wishlist heart in its corner, and to the right of it the name,
/// what the listing says about itself, one highlight, its department, and the
/// price beside Buy Now.
///
/// Every part sits in a measured slot, so a product with a long name makes the
/// same card as one with a short name. Without that the prices and buttons
/// wander down the column.
///
/// What is not here is not published: this catalogue sends one price per
/// product -- [ProductDetail.listPrice] is documented as always null against
/// it -- so there is no struck-out "was" price and no discount percentage. A
/// figure invented here would be an offer nobody made. It appears the day the
/// server sends one.
class _ViewRow extends StatelessWidget {
  const _ViewRow({
    required this.view,
    required this.saved,
    required this.onOpen,
    required this.onSave,
    required this.onBuy,
    this.detail,
  });

  final ProductView view;

  /// The catalogue's record, once it has arrived. Null until then.
  final ProductDetail? detail;

  final bool saved;
  final VoidCallback onOpen;
  final VoidCallback onSave;

  /// Buy now: into the cart and on to it.
  final VoidCallback onBuy;

  /// The picture's own square, sized to the words beside it: the card is as
  /// tall as its content and no taller, and the photograph fills that height
  /// rather than leaving a band of empty card above or below it.
  ///
  /// Clamped so a very large text setting cannot make the tile swallow the
  /// row, and a very small one cannot shrink it to a stamp.
  static double imageSize(BuildContext context) =>
      contentHeight(context).clamp(84.0, 132.0);

  /// The picture exactly as the tile asks for it, so loading it ahead of the
  /// card fills the same cache entry the tile then reads.
  static ImageProvider imageOf(BuildContext context, String url) =>
      AppImages.of(
        url,
        width: imageSize(context),
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );

  /// The slots the words sit in, scaled by the device's text setting so a
  /// larger one makes every card taller rather than clipping one.
  static double _nameSlot(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(12.5 * 1.25) * 2;
  static double _blurbSlot(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(11.5 * 1.3);
  static double _highlightSlot(BuildContext context) =>
      // The tick beside the words is 12pt, so the line is a shade taller than
      // the type alone.
      MediaQuery.textScalerOf(context).scale(11.5 * 1.3) + 3;
  static double _priceSlot(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(12.5 * 1.2) + 18;

  /// The whole card's text block: the slots and the gaps between them.
  static double contentHeight(BuildContext context) =>
      _nameSlot(context) +
      2 +
      _blurbSlot(context) +
      2 +
      _highlightSlot(context) +
      4 +
      _priceSlot(context);

  /// The short line under the name: what the seller wrote about it.
  ///
  /// The listing's own description where there is prose in it. This catalogue
  /// usually returns the description as a block of images with no words, and
  /// on those the first specification stands in -- it is the same fact, said
  /// by the same seller.
  String? get _blurb {
    final text = detail?.description.trim() ?? '';
    if (text.isNotEmpty) return text.replaceAll(RegExp(r'\s+'), ' ');
    final specs = detail?.specs ?? const [];
    if (specs.isEmpty) return null;
    return '${specs.first.label}: ${specs.first.value}';
  }

  /// What the listing puts forward about itself.
  ///
  /// One line of it: the card is as tall as this list makes it, and a second
  /// highlight costs every card in the column the same height for a fact most
  /// shoppers read on the product page anyway.
  ///
  /// Never the specification [_blurb] is already printing. With no prose in
  /// the listing the blurb falls back to the first specification, and this
  /// used to take that same first one -- so "Brand: Pulse treasure" appeared
  /// twice, one line above the other. It takes the next one instead, or none.
  List<ProductSpec> get _highlights {
    final specs = detail?.specs ?? const [];
    final blurb = _blurb;
    final unused = [
      for (final spec in specs)
        if ('${spec.label}: ${spec.value}' != blurb) spec,
    ];
    return unused.isEmpty ? const [] : unused.sublist(0, 1);
  }

  /// The department this belongs to, as the catalogue files it.
  String? get _subcategory {
    final name = detail?.category ?? view.category;
    return (name == null || name.trim().isEmpty) ? null : name.trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = detail?.price ?? view.price;
    final highlights = _highlights;
    final blurb = _blurb;
    final tag = _subcategory;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            // Tighter on the left, so the photograph sits closer to the card's
            // edge.
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The photograph down the left, in a fixed square, contained
                // so no shape is cropped or stretched, with the heart in its
                // corner rather than over the product.
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: imageSize(context),
                        width: imageSize(context),
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: view.imageUrl == null
                            ? Icon(
                                Icons.image_not_supported_outlined,
                                size: 24,
                                color: theme.colorScheme.onSurfaceVariant,
                              )
                            // Through the app's image path: a variant sized to
                            // this tile, kept on disk, rather than the full
                            // photograph downloaded and decoded on every visit.
                            : Image(
                                image: imageOf(context, view.imageUrl!),
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Material(
                        color: theme.colorScheme.surface.withValues(
                          alpha: 0.92,
                        ),
                        shape: const CircleBorder(),
                        child: IconButton(
                          onPressed: onSave,
                          visualDensity: VisualDensity.compact,
                          tooltip: saved ? 'Saved' : 'Save',
                          icon: Icon(
                            saved ? Icons.favorite : Icons.favorite_border,
                            size: 16,
                            color: saved
                                ? AppColors.wishlist
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: contentHeight(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: _nameSlot(context),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  view.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // When it was actually opened, from the shop's
                              // own record of it.
                              Text(
                                'Viewed ${formatRelative(view.viewedAt)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        // The slots below are drawn whether or not the listing
                        // filled them, so the price and the button land on the
                        // same line on every card.
                        SizedBox(
                          height: _blurbSlot(context),
                          child: blurb == null
                              ? null
                              : Text(
                                  blurb,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11.5,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          height: _highlightSlot(context),
                          child: highlights.isEmpty
                              ? null
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final spec in highlights)
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.check_circle_outline,
                                            size: 12,
                                            color: AppColors.trustBlue,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              '${spec.label}: ${spec.value}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    fontSize: 11,
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                        ),
                        const Spacer(),
                        SizedBox(
                          height: _priceSlot(context),
                          child: Row(
                            children: [
                              // The department rides on this row rather than
                              // costing every card a line of its own.
                              if (tag != null) ...[
                                Flexible(
                                  child: _Chip(
                                    // Cosmic Orange, which this palette calls
                                    // Commerce Orange.
                                    label: tag,
                                    ink: AppColors.commerceOrange,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      price != null && price > 0
                                          ? formatRupees(price)
                                          : view.priceLabel ?? '',
                                      maxLines: 1,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            // Rooted Blue, which this palette
                                            // calls Trust Blue.
                                            color: AppColors.trustBlue,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: onBuy,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.trustBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  textStyle: theme.textTheme.bodySmall
                                      ?.copyWith(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                child: const Text('Buy Now'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The list while it is being fetched.
///
/// Bones at the card's own measurements -- the same picture area, the same
/// two lines of name, the same slots under it and the same button -- so the
/// page does not jump when the history lands on top of it.
class RecentViewsSkeleton extends StatelessWidget {
  const RecentViewsSkeleton({super.key, this.rows = 3});

  final int rows;

  /// One card's full height: its padding, its border and its text block.
  static double cardExtent(BuildContext context) =>
      _ViewRow.contentHeight(context) + 16 + 2;

  /// As many bones as [height] shows, plus one so the last is cut by the edge
  /// rather than leaving a band of empty page under the bones.
  static int rowsFor(BuildContext context, double height) {
    if (!height.isFinite || height <= 0) return 3;
    return (height / (cardExtent(context) + 8)).ceil().clamp(1, 16);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _Measure(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    // The real card's own inset, so the bones and the cards
                    // that replace them line up edge for edge.
                    padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: _ViewRow.imageSize(context),
                          width: _ViewRow.imageSize(context),
                          child: const ShimmerPanel(radius: 10),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: _ViewRow.contentHeight(context),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const ShimmerBone(height: 12),
                                const SizedBox(height: 4),
                                const ShimmerBone(width: 200, height: 12),
                                const SizedBox(height: 5),
                                const ShimmerBone(width: 160, height: 10),
                                const SizedBox(height: 5),
                                const ShimmerBone(width: 120, height: 10),
                                const Spacer(),
                                Row(
                                  children: [
                                    const ShimmerBone(width: 84, height: 14),
                                    const Spacer(),
                                    const ShimmerBone(
                                      width: 96,
                                      height: 30,
                                      radius: 8,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The small pill under the highlights: the department this belongs to.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.ink});

  final String label;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      // One line, on the price row. A long department used to wrap to two
      // lines and stand taller than the price beside it.
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
    );
  }
}
