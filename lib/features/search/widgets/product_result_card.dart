import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/motion/motion_curves.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../wishlist/presentation/wishlist_flight.dart';
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
    this.padding = _pad,
    this.dense = false,
    this.imageFlush = false,
  });

  final Product product;
  final VoidCallback? onTap;
  final VoidCallback? onAddToCart;
  final VoidCallback? onToggleSaved;
  final bool saved;

  /// Inside the border, around everything. A grid that wants bigger pictures
  /// in the same width passes less; see [ResultGridSpec].
  final double padding;

  /// Draws the picture to the card's own top, left and right edges instead of
  /// inside [padding].
  ///
  /// Off everywhere but the product page's recommendation shelf, which asked
  /// for the picture to use the width it is given. The words below keep their
  /// padding either way, so only the picture changes.
  final bool imageFlush;

  /// The marketplace treatment: tighter internal gaps and the price in the
  /// brand's own ink.
  ///
  /// Opt-in, and false everywhere it is not asked for. This card is drawn by
  /// six surfaces -- search, the department feed, the home grid, the home
  /// carousel, the cart's recommendations and the discovery feed -- and only
  /// the last of them asked to be denser. A flag rather than a second card
  /// keeps the other five on exactly the layout they have, byte for byte,
  /// while the thing they share stays one widget.
  final bool dense;

  /// The card's internal rhythm, kept together so the gaps stay related.
  static const _pad = 10.0;
  static const _gap = 8.0;
  static const _gapTight = 5.0;

  /// The same rhythm, closed right up, for [dense].
  ///
  /// Four points between the picture and the price, two between the lines
  /// under it. Every point taken out here is a point the row does not spend on
  /// air -- and because the grid measures its rows from [heightFor], it comes
  /// off the vertical gap between rows as well as off the card.
  static const _gapDense = 4.0;
  static const _gapTightDense = 2.0;

  /// Lines of title the card always reserves, so cards in a row end level even
  /// when one title runs short.
  static const _titleLines = 2;

  /// Roughly the width a card wants. Columns come from this rather than from
  /// named device sizes, so a split-screen tablet gets the layout that fits
  /// rather than the layout its diagonal implies.
  static const targetWidth = 190.0;
  static const gridGap = 10.0;

  /// The gap between *rows* of cards, as against [gridGap] between columns.
  ///
  /// The two were one number, which is why the home page could not be made
  /// vertically denser without also narrowing its pictures. They are separate
  /// because the page spends them differently: a column gap is paid once
  /// across the width, a row gap is paid again for every row down a feed that
  /// stacks thirteen sections.
  static const rowGap = 6.0;

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
  static double heightFor(
    BuildContext context,
    double cardWidth, {
    double padding = _pad,
    bool dense = false,
    bool imageFlush = false,
  }) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);

    double lineOf(TextStyle? style, double fallback, {double lines = 1}) =>
        scaler.scale((style?.fontSize ?? fallback) * 1.35 * lines);

    // The picture is square and spans the padded width -- or the whole card,
    // when it is drawn flush to the edges.
    final image = imageFlush ? cardWidth : cardWidth - padding * 2;
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

    // The same two gaps the card draws. They are read from here rather than
    // hardcoded because the grid asks for this as a `mainAxisExtent`: a dense
    // card measured with the roomy gaps is a card the grid clips.
    final gap = dense ? _gapDense : _gap;
    final tight = dense ? _gapTightDense : _gapTight;

    // Flush: the picture pays no padding above it, so only the foot remains.
    final insets = imageFlush ? padding : padding * 2;
    return insets + image + gap + price + tight + title + tight + credibility;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Kept in step with [heightFor], which reads the same two.
    final gap = dense ? _gapDense : _gap;
    final tight = dense ? _gapTightDense : _gapTight;

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
          // Flush draws the picture to the card's own edges, so the padding
          // moves off the top and on to the words underneath it instead.
          padding: imageFlush ? EdgeInsets.zero : EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    // Against the card's edges it takes the card's own corner,
                    // top only; inside the padding it keeps its small one.
                    borderRadius: imageFlush
                        ? const BorderRadius.vertical(
                            top: Radius.circular(AppTheme.radiusCard),
                          )
                        : BorderRadius.circular(AppTheme.radiusControl),
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
              SizedBox(height: gap),
              // The words keep the padding the picture gave up, so only the
              // picture is flush and the text sits exactly where it did.
              Padding(
                padding: imageFlush
                    ? EdgeInsets.fromLTRB(padding, 0, padding, padding)
                    : EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PriceRow(
                      product: product,
                      onAddToCart: onAddToCart,
                      dense: dense,
                    ),
                    SizedBox(height: tight),
                    SizedBox(
                      height: titleHeight,
                      child: Text(
                        product.title,
                        maxLines: _titleLines,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                    if (product.salesLabel != null ||
                        product.tradeScore != null) ...[
                      SizedBox(height: tight),
                      _Credibility(product: product),
                    ],
                  ],
                ),
              ),
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
///
/// Saving plays: the heart dips, pops past its own size, and fills pink; at
/// the top of that pop a copy of it leaves for the wishlist icon. The state
/// the card draws afterwards is still the store's -- this only animates the
/// moment, and un-saving is the plain toggle it always was.
class _SaveButton extends StatefulWidget {
  const _SaveButton({
    required this.saved,
    required this.title,
    required this.onPressed,
  });

  final bool saved;
  final String title;
  final VoidCallback onPressed;

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton>
    with SingleTickerProviderStateMixin {
  /// The dip and the pop, in one run: 0 to 0.3 down, 0.3 to 1 back up and
  /// over. The flight leaves at the peak.
  static const _popDuration = Duration(milliseconds: 420);
  static const _peak = 0.42;

  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: _popDuration,
  );

  /// The card's heart is locked while its own heart is away, so a run of taps
  /// cannot put several of them in the air at once. It is let go the moment
  /// the sequence ends -- including when the save fails.
  bool _busy = false;

  /// Drawn filled from the tap until the store catches up.
  ///
  /// The wishlist call, its push to the server and the rebuild that follows
  /// take longer than the animation does, and a heart that fell back to its
  /// outline in that gap would be saying the product was not saved when it
  /// was. So the fill is held, and let go the moment the card is told what
  /// really happened -- [didUpdateWidget] below -- or by [_holdFill] if the
  /// save failed and nothing ever comes.
  bool _filling = false;

  /// The longest the fill is held on trust.
  static const _holdFill = Duration(seconds: 5);
  Timer? _release;

  @override
  void didUpdateWidget(_SaveButton old) {
    super.didUpdateWidget(old);
    // The store has spoken: it owns the heart from here.
    if (widget.saved != old.saved && _filling) {
      setState(() => _filling = false);
    }
  }

  @override
  void dispose() {
    _release?.cancel();
    _pop.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_busy) return;

    // Un-saving is not a flight: nothing is going to the wishlist.
    if (widget.saved) {
      widget.onPressed();
      return;
    }

    final reduced = MediaQuery.of(context).disableAnimations;
    setState(() {
      _busy = true;
      _filling = true;
    });

    // The real save runs alongside the animation rather than after it: the
    // wishlist call is the action, and this is only how it looks.
    widget.onPressed();

    final flight = _pop
        .forward(from: 0)
        .orCancel
        .then((_) {})
        .catchError((_) {});
    // Launched at the peak of the pop, from wherever this heart is now.
    await Future<void>.delayed(_popDuration * _peak);
    if (!mounted) return;
    await WishlistFlight.launch(context, reducedMotion: reduced);
    await flight;

    if (!mounted) return;
    // The button is free again as soon as its heart has landed. The fill
    // stays until the store says otherwise, so the heart never blinks back
    // to an outline on a product that is saved.
    setState(() => _busy = false);

    // Nothing came back: the save did not take, so the heart goes back to
    // what the card was told, rather than showing a save that never happened.
    _release?.cancel();
    _release = Timer(_holdFill, () {
      if (!mounted || !_filling) return;
      setState(() => _filling = false);
    });
  }

  /// 1 at rest, 0.85 at the bottom of the dip, over one on the way back.
  double get _scale {
    final t = _pop.value;
    if (t == 0 || _pop.isCompleted) return 1;
    if (t <= 0.3) return 1 - 0.15 * power2Out.transform(t / 0.3);
    return 0.85 + 0.15 * backOut3.transform((t - 0.3) / 0.7);
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.saved;
    final showFilled = saved || _filling;

    return Semantics(
      button: true,
      // Names the product, so a screen reader running down a grid of these does
      // not read out forty identical "Save" buttons.
      label: saved ? 'Saved: ${widget.title}' : 'Save ${widget.title}',
      child: Material(
        color: Colors.white.withValues(alpha: 0.88),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: AnimatedBuilder(
              animation: _pop,
              builder: (context, _) => Transform.scale(
                scale: _scale,
                // Outline out, fill in, rather than one icon swapping for
                // another between frames.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    showFilled ? Icons.favorite : Icons.favorite_border,
                    key: ValueKey(showFilled),
                    size: 17,
                    color: showFilled ? AppColors.accent : Colors.black54,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.product,
    this.onAddToCart,
    this.dense = false,
  });

  final Product product;
  final VoidCallback? onAddToCart;

  /// Puts the price in the brand's ink, as the home rails already do. On a
  /// discovery grid the price is the thing being scanned for.
  final bool dense;

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
                    color: dense ? theme.colorScheme.primary : null,
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

/// How a grid of [ProductResultCard]s divides its width: the columns, the gap
/// between cards, and the padding inside each.
///
/// One object so a grid, its skeleton and the card's own height all read the
/// same three numbers and cannot disagree about where a card ends.
@immutable
class ResultGridSpec {
  const ResultGridSpec({
    required this.columns,
    required this.gap,
    required this.cardPadding,
    this.rowGap,
  });

  final int columns;
  final double gap;
  final double cardPadding;

  /// Between rows, when it differs from the gap between columns.
  ///
  /// **Null means "the same as [gap]"**, which is what every grid did before
  /// this existed -- so a spec that does not ask for one is laid out exactly as
  /// it was, and only the home grid asks. Callers resolve it with
  /// `rowGap ?? gap`.
  ///
  /// Nullable and public rather than a private field behind a getter: a getter
  /// would have needed a custom initializer, and Dart has no private named
  /// parameter to initialise it from.
  final double? rowGap;

  /// The width one card gets out of [available].
  ///
  /// The column gap, deliberately: this divides the *width*, and the row gap
  /// has no business in it.
  double cardWidth(double available) =>
      (available - gap * (columns - 1)) / columns;

  /// The home grid, the rails and the department feed.
  ///
  /// The card's own defaults across, and a tighter measure down: the home page
  /// stacks section after section, so the vertical gap is the one being paid
  /// over and over. The horizontal is untouched.
  static ResultGridSpec standard(double available) => ResultGridSpec(
    columns: ProductResultCard.columnsFor(available),
    gap: ProductResultCard.gridGap,
    rowGap: ProductResultCard.rowGap,
    cardPadding: ProductResultCard._pad,
  );

  /// The standard grid with the gaps closed up, across and down.
  ///
  /// Four points, which is the measure the Future Cart shelf uses between its
  /// suggestion cards. Same columns, same padding inside each card: only the
  /// space between them is different, so the cards themselves are untouched
  /// and the row simply wastes less of the width on air.
  static ResultGridSpec compact(double available) => ResultGridSpec(
    columns: ProductResultCard.columnsFor(available),
    gap: 4,
    rowGap: 4,
    cardPadding: ProductResultCard._pad,
  );

  /// The search results. Bigger cards and tighter gaps than the standard
  /// grid, because a results page exists to look at the products: on a phone
  /// the picture gains about ten points a side from the card's padding and the
  /// gutter, and on a wider window the cards are allowed to grow rather than
  /// multiply into a row of thumbnails.
  static ResultGridSpec search(double available) {
    // Two columns on anything phone-sized. Three would put a 110pt card
    // under a thumb.
    if (available < 560) {
      return const ResultGridSpec(columns: 2, gap: 8, cardPadding: 6);
    }
    final target = available >= 1000 ? 240.0 : 210.0;
    return ResultGridSpec(
      columns: (available / target).floor().clamp(3, 6),
      gap: 10,
      cardPadding: 8,
    );
  }

  /// The discovery feed: wide cards with very little between them.
  ///
  /// Two columns on a phone -- three would put a 110pt card under a thumb --
  /// with the gutter down to four points and the card's own padding to four.
  /// On a 412pt phone that leaves each card about 202 points and its picture
  /// about 194, which is most of the half-width there is to give.
  ///
  /// **Wider windows take the width in bigger cards, not more of them.** This
  /// went the other way first -- up to seven columns at 1280, on the reasoning
  /// that a scanning feed wants density -- and that is a row of thumbnails,
  /// not a marketplace. The target width per card is now well above
  /// [search]'s, so a desktop window gets four broad cards where the results
  /// page gets five narrow ones.
  ///
  /// Every number here divides [available] exactly -- `cardWidth` subtracts
  /// the gutters before dividing -- so no combination of these can overflow
  /// sideways.
  static ResultGridSpec discovery(double available) {
    if (available < 560) {
      return const ResultGridSpec(columns: 2, gap: 4, cardPadding: 4);
    }
    final target = available >= 1000 ? 280.0 : 240.0;
    return ResultGridSpec(
      columns: (available / target).floor().clamp(3, 5),
      gap: 6,
      cardPadding: 5,
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
  const ResultGridSkeleton({
    super.key,
    this.count = 6,
    this.specFor = ResultGridSpec.standard,
  });

  final int count;

  /// The layout of the grid this stands in for, so it matches it exactly.
  final ResultGridSpec Function(double available) specFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Shimmer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final spec = specFor(constraints.maxWidth);
          final width = spec.cardWidth(constraints.maxWidth);
          final height = ProductResultCard.heightFor(
            context,
            width,
            padding: spec.cardPadding,
          );

          return Wrap(
            spacing: spec.gap,
            runSpacing: spec.gap,
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
                    padding: EdgeInsets.all(spec.cardPadding),
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
