import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../catalog/data/product.dart';
import '../../catalog/presentation/catalog_visuals.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/future_cart_feed.dart';

/// One suggestion, drawn the way the Future Cart reference draws it.
///
/// Its own card rather than [ProductResultCard] with a flag, because the
/// reference's card is a different object: the picture sits on white and is
/// shown whole rather than cropped, the price leads in the body ink rather
/// than the brand blue, there is no badge, no sold line and no seller score,
/// and two things the results card has never had -- a reason with its own mark
/// and a full-width outlined Add button -- carry the design.
///
/// What it does share is the data and the behaviour: the same [Product] off
/// the same catalogue endpoints, the same heart wired to the same wishlist,
/// and the same add-to-cart path. Nothing here is a second source of truth.
class SuggestionCard extends StatelessWidget {
  const SuggestionCard({
    super.key,
    required this.suggestion,
    required this.saved,
    required this.onToggleSaved,
    required this.onAdd,
    this.onTap,
    this.quantity = 0,
    this.canIncrease = true,
    this.canDecrease = true,
    this.onIncrease,
    this.onDecrease,
    this.onRemove,
  });

  final Suggestion suggestion;
  final bool saved;
  final VoidCallback onToggleSaved;
  final VoidCallback onAdd;
  final VoidCallback? onTap;

  /// How many of this product the cart holds, or zero when it holds none.
  ///
  /// Read from [CartStore] by the page rather than counted here, so the card
  /// shows the cart's own figure and not a tally of its own taps. Zero draws
  /// the Add button; anything above it draws the controls.
  final int quantity;

  /// Whether the steps are allowed, by the cart's rules rather than this
  /// card's. Both come from the page, which is where [CartStore] is known:
  /// the floor is the line's minimum order and the ceiling is `maxPerLine`.
  final bool canIncrease;
  final bool canDecrease;

  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;

  /// Takes the line out of the cart and returns this card to its Add state.
  ///
  /// Its own control rather than a step off the bottom of the stepper: the
  /// store's rule is that removal is explicit, because a minus key that
  /// deletes the row out from under the finger is how shoppers lose things.
  final VoidCallback? onRemove;

  /// Inside the border, around everything.
  ///
  /// 7 rather than 10 by request: the page was asked to use the width it has.
  /// Six points a card, which go to the picture and to the pill -- and the
  /// pill is where they were needed, because a card 124 points wide left its
  /// words about thirteen characters a line.
  static const pad = 7.0;

  /// Between cards, down and across.
  ///
  /// Named here rather than in the grid because three places have to agree
  /// about it: the grid, its skeleton, and the width each card is measured at.
  ///
  /// Ten, then six, now four -- the page was asked twice to use the width it
  /// has. Four is the floor: a gutter narrower than this stops reading as a
  /// gap between two cards and starts reading as one card with a seam.
  static const gridGap = 4.0;

  /// The reference's rhythm between the picture, the words and the button.
  static const _gap = 8.0;
  static const _gapTight = 5.0;

  /// Lines held for the title and for the reason, so cards in a row end level
  /// however long one product's name runs. Both are two in the reference --
  /// "You usually buy this / every 30 days." wraps, and so does the title
  /// beside it.
  static const _titleLines = 2;
  static const _reasonLines = 2;

  /// The Add button's height, from the reference: a pill, not a chip.
  static const _buttonHeight = 34.0;

  /// Roughly the width one card wants. The reference sets three across a
  /// phone, which is what this is scaled to.
  static const targetWidth = 240.0;

  /// Square at the top, rounded at the foot.
  ///
  /// The banners above and below these rails were squared off at the top by
  /// request, so a card that keeps all four corners round reads as a different
  /// kind of object sitting on the same page. Square tops line the cards up
  /// with the sections they belong to; the bottom keeps its radius, which is
  /// what the rest of the app's cards do.
  static final _shape = BorderRadius.vertical(
    bottom: Radius.circular(AppTheme.radiusCard),
  );

  /// How many columns [available] gets.
  ///
  /// Three on a phone, because that is the reference -- it is drawn at 440
  /// points with three cards across, and a design whose whole point is a dense
  /// scan of suggestions does not become two cards on a real handset. Wider
  /// windows take the room in more columns rather than in cards half a screen
  /// wide.
  static int columnsFor(double available) =>
      available < 600 ? 3 : (available / targetWidth).floor().clamp(3, 6);

  /// The width one card gets on a rail, given the room [available].
  ///
  /// Wider than the grid's card by request, and sized so a card is always cut
  /// in half at the right-hand edge: the half-card *is* the affordance. A rail
  /// whose last visible card ends flush with the margin looks like a row that
  /// has finished, and nobody swipes a row that has finished.
  ///
  /// Hence the fractions. Two and a third cards on a phone, rising with the
  /// width so a desktop shows more of them rather than five cards the size of
  /// posters -- and every step keeps a part card at the end, so the invitation
  /// survives at every size.
  ///
  /// The fraction was exactly a half at every tier and is now a little under
  /// one, by request: the cards were asked to use the room they have. Dropping
  /// 0.15 of a card from each tier spends that room on the cards themselves --
  /// about six per cent wider on a phone -- and the part card at the edge is
  /// still plainly a part card, which is the whole job it was doing.
  static double carouselWidthFor(double available) {
    final visible = available < 600
        ? 2.35
        : available < 900
        ? 3.35
        : available < 1300
        ? 4.35
        : 5.35;
    // Gaps between the cards that are fully on screen; the half at the end
    // brings no gap of its own.
    return (available - gridGap * visible.floor()) / visible;
  }

  /// Exactly how tall a card of [width] will be.
  ///
  /// Measured from the card's own parts, the way the results grid measures
  /// its card, so the grid's row height and the card can never drift apart.
  /// Everything that can grow with the reader's text setting goes through the
  /// scaler: at 200% type a fixed height clips the Add button off the bottom.
  static double heightFor(BuildContext context, double width) {
    final theme = Theme.of(context);

    final image = width - pad * 2;
    final title = _block(context, _titleSize(theme), 1.3, _titleLines);
    final price = _block(context, _priceSize(theme), 1.25, 1);
    // The reason is a mark beside a pill; the pill's own padding is 5 top and
    // bottom and its text takes two lines -- a label over a figure.
    //
    // Measured one line at a time and multiplied, never two lines at once:
    // the pill draws each line in its own box, and ceil(a) + ceil(a) is not
    // ceil(2a). That difference is one pixel, and one pixel is an overflow --
    // which this card has already shipped once.
    final reason = _reasonLine(context, theme) * _reasonLines + 10;
    final button = _block(context, _buttonHeight, 1, 1);

    return pad * 2 +
        image +
        _gap +
        title +
        _gapTight +
        price +
        _gap +
        reason +
        _gap +
        button;
  }

  /// One text block's height, rounded up to a whole pixel.
  ///
  /// Up, and to a whole pixel, because this number is used twice: here, to
  /// tell the grid how tall a row is, and again in [build] to bound the box
  /// the text is drawn in. Any disagreement between those two is a RenderFlex
  /// overflow, and this card shipped one at exactly **half a pixel** -- the
  /// price was the one child measured by formula and drawn at its natural
  /// height, and the text engine rounds a line box up where the formula did
  /// not. Rounding here, and bounding every child there, is what makes the two
  /// agree by construction rather than by luck.
  static double _block(
    BuildContext context,
    double size,
    double height,
    int count,
  ) =>
      MediaQuery.textScalerOf(context)
          .scale(size * height * count)
          .ceilToDouble();

  /// A step under the theme's, by request.
  ///
  /// Derived from the theme rather than written down, so the card still
  /// follows the reader's text setting and moves with the app's own scale --
  /// it simply sits one point below it. Both feed [heightFor], so the card
  /// gets shorter with them rather than keeping a hole where the type was.
  static double _titleSize(ThemeData theme) =>
      (theme.textTheme.bodySmall?.fontSize ?? 12) - 1;
  static double _priceSize(ThemeData theme) =>
      (theme.textTheme.titleSmall?.fontSize ?? 14) - 1;

  /// A step under the label size rather than half a step.
  ///
  /// Measured on the phone: at 10.5 the pill fits about thirteen characters a
  /// line, and the reference's own reason -- "Goes well with your shampoo." --
  /// is twenty-seven. Two lines of that needs the smaller size, and both this
  /// and [heightFor] read it, so the box grows and shrinks with the type.
  static double _reasonSize(ThemeData theme) =>
      (theme.textTheme.labelSmall?.fontSize ?? 11) - 2;

  /// One line of the reason pill, which both the label and the figure get.
  static double _reasonLine(BuildContext context, ThemeData theme) =>
      _block(context, _reasonSize(theme), 1.25, 1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = suggestion.product;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: _shape,
      child: InkWell(
        borderRadius: _shape,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: _shape,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  // Filling the tile rather than standing whole inside it, by
                  // request.
                  //
                  // This was `contain`, which shows a seller's cut-out
                  // photograph entire and pads the rest -- honest about the
                  // shape of the thing, but it left pale margins around every
                  // picture and the card had just been widened twice to give
                  // the picture that room. `cover` spends it: the photograph
                  // fills the square and is cropped to it.
                  //
                  // The trade is real and worth naming: a tall or very wide
                  // product now loses its edges rather than shrinking to fit.
                  // The grid is square and the pictures are not.
                  ArtworkPanel(
                    icon: iconForCategory(
                      product.categoryName ?? product.parentCategoryName,
                    ),
                    tint: AppColors.mountainGrey,
                    imageUrl: product.imageUrl,
                    aspectRatio: 1,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _Heart(
                      saved: saved,
                      title: product.title,
                      onPressed: onToggleSaved,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _gap),
              SizedBox(
                height: _block(context, _titleSize(theme), 1.3, _titleLines),
                child: Text(
                  product.title,
                  maxLines: _titleLines,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: _gapTight),
              SizedBox(
                // Bounded, like the title above it. Left to its natural
                // height this was the half-pixel the card overflowed by.
                height: _block(context, _priceSize(theme), 1.25, 1),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    // Never "Rs. 0": the feed builds no card for a product it
                    // cannot price, so this is always a real figure.
                    formatRupees(product.displayPrice ?? 0),
                    maxLines: 1,
                    style: theme.textTheme.titleSmall?.copyWith(
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: _gap),
              SizedBox(
                height: _reasonLine(context, theme) * _reasonLines + 10,
                child: _Reason(
                  label: suggestion.label,
                  detail: suggestion.reason,
                  kind: suggestion.kind,
                  size: _reasonSize(theme),
                  line: _reasonLine(context, theme),
                ),
              ),
              const SizedBox(height: _gap),
              // One box, drawn two ways. The controls take exactly the room
              // the Add button leaves, so a card that joins the cart keeps
              // its height and the cards beside it do not shift.
              if (quantity > 0)
                _CartControls(
                  quantity: quantity,
                  height: _buttonHeight,
                  title: product.title,
                  canIncrease: canIncrease,
                  canDecrease: canDecrease,
                  onIncrease: onIncrease,
                  onDecrease: onDecrease,
                  onRemove: onRemove,
                )
              else
                _AddButton(onPressed: onAdd, height: _buttonHeight),
            ],
          ),
        ),
      ),
    );
  }
}

/// The outlined heart in the corner of the picture.
///
/// Outlined and unfilled until it is saved, as the reference has it, and on no
/// scrim: the picture behind it is a pale product shot rather than the
/// full-bleed photography the results card has to survive.
class _Heart extends StatelessWidget {
  const _Heart({
    required this.saved,
    required this.title,
    required this.onPressed,
  });

  final bool saved;
  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      // Named, so a screen reader running down a grid of these does not read
      // out six identical "Save" buttons.
      label: saved ? 'Saved: $title' : 'Save $title',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              saved ? Icons.favorite : Icons.favorite_border,
              size: 17,
              color: saved ? AppColors.wishlist : theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The reason: a tinted pill carrying its own mark, with the words beside it.
///
/// The mark sits **inside** the pill by request. It used to stand outside,
/// which read as two objects on the row -- a loose icon and a chip next to it
/// -- rather than as one labelled tag. Inside, the pill spans the whole card
/// and the mark plainly belongs to it. The words lose nothing by the move: the
/// icon costs the same points wherever it is drawn, and the pill gains back
/// the gap that used to separate the two.
///
/// The colour is the kind's, so the three repeat reasons are told apart at a
/// glance without reading -- which is the job the reference gives it.
class _Reason extends StatelessWidget {
  const _Reason({
    required this.label,
    required this.detail,
    required this.kind,
    required this.size,
    required this.line,
  });

  /// The label, in three or four words: "You Usually Buy".
  final String label;

  /// The figure under it: "Every 30 days". Empty where the label is the whole
  /// fact, and then the label takes both lines instead.
  final String detail;

  final SuggestionKind kind;
  final double size;

  /// How tall one line is, measured by the card so the two agree.
  final double line;

  @override
  Widget build(BuildContext context) {
    final (icon, ink) = _mark;

    return Container(
      height: double.infinity,
      // Four on the left rather than five: the mark now starts the row, and a
      // glyph reads as further in than a letter does at the same inset.
      padding: const EdgeInsets.fromLTRB(4, 5, 5, 5),
      decoration: BoxDecoration(
        // The mark's own colour, barely there. The reference tints the pill
        // rather than filling it.
        color: ink.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 13, color: ink),
          const SizedBox(width: 4),
          Expanded(
            child: detail.isEmpty
                // No figure to put under it, so the label takes both lines.
                // "You Buy This Frequently" is the whole fact there is.
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _labelStyle(context, ink),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Each line in a box the card measured, so what the grid
                      // reserves and what the pill draws cannot disagree.
                      SizedBox(
                        height: line,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _labelStyle(context, ink),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: line,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _detailStyle(context, ink),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// The label: the heavier of the two lines, in the mark's own colour.
  TextStyle? _labelStyle(BuildContext context, Color ink) => Theme.of(context)
      .textTheme
      .labelSmall
      ?.copyWith(
        fontSize: size,
        height: 1.25,
        fontWeight: FontWeight.w800,
        color: ink,
      );

  /// The figure under it, held back a step so the label leads.
  TextStyle? _detailStyle(BuildContext context, Color ink) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: size,
        height: 1.25,
        fontWeight: FontWeight.w500,
        color: ink.withValues(alpha: 0.85),
      );

  /// The mark and its ink.
  ///
  /// Four kinds, four colours, from the reference. The orange here is the
  /// brand accent being spent on something other than a call to action, which
  /// the 60-30-10 budget normally forbids -- it is the reference's own
  /// treatment for a restock rhythm, and the card's actual call to action is
  /// the Add button below it.
  (IconData, Color) get _mark => switch (kind) {
    SuggestionKind.rhythm => (Icons.sync, AppColors.commerceOrange),
    SuggestionKind.lastBought => (Icons.schedule, AppColors.destructiveLight),
    SuggestionKind.frequent => (Icons.sync, AppColors.trustBlue),
    SuggestionKind.complement => (Icons.extension, AppColors.successInk),
  };
}

/// "+ Add to Cart", outlined and the full width of the card.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed, required this.height});

  final VoidCallback onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: MediaQuery.textScalerOf(context).scale(height),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          // The theme's button is 44 tall with a hairline edge; the
          // reference's is shorter, in the brand blue, and rounded further.
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          side: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.55),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, size: 15),
              const SizedBox(width: 3),
              Text(
                'Add to Cart',
                maxLines: 1,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the Add button becomes once the product is in the cart: fewer, how
/// many, more -- and remove beside them.
///
/// Drawn in exactly the box [_AddButton] leaves behind, so joining the cart
/// costs the card no height.
///
/// Remove keeps a square of its own at the end rather than living under the
/// minus key. The two are not the same kind of action: stepping down to the
/// minimum is a quantity the shopper chose, and deleting the line is not
/// something they should reach by pressing minus once too often.
class _CartControls extends StatelessWidget {
  const _CartControls({
    required this.quantity,
    required this.height,
    required this.title,
    required this.canIncrease,
    required this.canDecrease,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
  });

  final int quantity;
  final double height;

  /// The product's name, spoken by the controls rather than shown -- a screen
  /// reader running down a rail of these would otherwise read out a row of
  /// identical "More" and "Fewer" buttons.
  final String title;

  final bool canIncrease;
  final bool canDecrease;
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return SizedBox(
      // The Add button's own measure, so the card's height is unchanged.
      height: MediaQuery.textScalerOf(context).scale(height),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Filled faintly rather than left open: the stepper is the
                // card's live state, and a bare outline reads as another
                // button waiting to be pressed.
                color: primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primary.withValues(alpha: 0.55)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StepKey(
                    icon: Icons.remove,
                    ink: primary,
                    label: 'Fewer $title',
                    onPressed: canDecrease ? onDecrease : null,
                  ),
                  Expanded(
                    child: Semantics(
                      label: '$quantity in cart',
                      excludeSemantics: true,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            // A wholesale line can run to four figures, so the
                            // figure is scaled down rather than clipped.
                            '$quantity',
                            maxLines: 1,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _StepKey(
                    icon: Icons.add,
                    ink: primary,
                    label: 'More $title',
                    onPressed: canIncrease ? onIncrease : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 5),
          _StepKey(
            icon: Icons.delete_outline,
            ink: theme.colorScheme.error,
            label: 'Remove $title from cart',
            onPressed: onRemove,
            bordered: true,
          ),
        ],
      ),
    );
  }
}

/// One key of the controls: a glyph in a box a finger can find.
///
/// [InkWell] rather than [IconButton] deliberately. An icon button honours its
/// 48-point tap target *outside* whatever constraints it is handed, which in a
/// 34-point row is how a control ends up taller than the row holding it -- the
/// same trap that kept the search bar's two icons apart.
class _StepKey extends StatelessWidget {
  const _StepKey({
    required this.icon,
    required this.ink,
    required this.label,
    required this.onPressed,
    this.bordered = false,
  });

  final IconData icon;
  final Color ink;
  final String label;
  final VoidCallback? onPressed;

  /// Remove carries an edge of its own; the two steps sit inside the
  /// stepper's.
  final bool bordered;

  /// Wide enough to hit, narrow enough that two keys and a figure still fit
  /// across a card 157 points wide with remove beside them.
  static const _width = 28.0;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final colour = enabled ? ink : Theme.of(context).disabledColor;
    final radius = BorderRadius.circular(bordered ? 10 : 9);

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox(
        width: _width,
        child: Material(
          color: bordered
              ? ink.withValues(alpha: enabled ? 0.06 : 0.03)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: bordered
                ? BorderSide(color: colour.withValues(alpha: 0.45))
                : BorderSide.none,
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(borderRadius: radius),
            onTap: onPressed,
            child: Center(child: Icon(icon, size: 15, color: colour)),
          ),
        ),
      ),
    );
  }
}
