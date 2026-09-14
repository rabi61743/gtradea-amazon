import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/brand_wordmark.dart';
import '../../../shared/widgets/shimmer.dart';
import '../../cart/data/cart_store.dart';
import 'suggestion_card.dart';

/// The Future Cart's own surfaces, derived from the brand rather than picked.
///
/// The reference draws this page on grounds the app has not needed before: a
/// blue-tinted header, a cream banner, a mint note at the foot. Each is one of
/// the six brand colours washed into white rather than a new hex, so the page
/// follows the brand if the brand ever moves -- the same reasoning
/// [AppColors.trustBlueDeep] is derived under.
abstract final class FutureCartPalette {
  /// The page itself: the brand blue at a whisper, which is the reference's
  /// very pale blue-white.
  static final page = Color.alphaBlend(
    AppColors.trustBlue.withValues(alpha: 0.04),
    Colors.white,
  );

  /// The strip the title sits on, a step bluer than the page.
  static final topBar = Color.alphaBlend(
    AppColors.trustBlue.withValues(alpha: 0.08),
    Colors.white,
  );

  /// The banner: Premium Ivory, warmed towards the accent across its width.
  static const bannerFrom = AppColors.premiumIvory;
  static final bannerTo = Color.alphaBlend(
    AppColors.commerceOrange.withValues(alpha: 0.07),
    AppColors.premiumIvory,
  );

  /// An unselected chip.
  static final chip = Color.alphaBlend(
    AppColors.trustBlue.withValues(alpha: 0.10),
    Colors.white,
  );

  /// The note at the foot: Success Green washed into white.
  static final note = Color.alphaBlend(
    AppColors.successGreen.withValues(alpha: 0.14),
    Colors.white,
  );

  /// Headings and the banner's own type: the head of the brand band, which is
  /// the reference's deep navy-teal.
  static const headline = AppColors.brandBandHead;

  /// The mark on the Complements heading.
  ///
  /// The one colour here that is not derived from the six. The reference draws
  /// that puzzle piece violet, and it is a section mark rather than anything
  /// that carries meaning elsewhere in the app -- so it is named here, used
  /// once, and not offered to anything else.
  static const complementInk = Color(0xFF7E57C2);
}

/// The side margin this page keeps, which is narrower than the app's.
///
/// Everywhere else uses [PageWidth]'s 97% measure -- 6.1 points a side on a
/// 406pt phone -- so that the home feed, the cart and the search results all
/// line up down the page. This page was asked twice to use the width it has,
/// and the second time to go past that shared margin, so it keeps its own.
///
/// Not a flat 2 at every size: on a 1280pt desktop window a two-point gutter
/// reads as a rendering fault rather than as a design. It is a fraction of the
/// width with a floor under it, which comes to 2.4 on a phone and about 7.7 on
/// a wide window -- edge-to-edge where the room is scarce, and still a margin
/// where it is not.
///
/// Because this is deliberately *not* the app's shared measure, a page that
/// wants to line up with the rest of the app should use [PageWidth] instead.
abstract final class FutureCartInsets {
  /// The floor, and the share of the width above it.
  static const minimum = 2.0;
  static const factor = 0.006;

  static double marginOf(BuildContext context) {
    final derived = MediaQuery.sizeOf(context).width * factor;
    return derived < minimum ? minimum : derived;
  }

  static EdgeInsets of(
    BuildContext context, {
    double top = 0,
    double bottom = 0,
  }) {
    final side = marginOf(context);
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }
}

/// Where the mascot goes.
///
/// The artwork is not in the repository yet. The slot is drawn from the file
/// the moment one exists at [asset] -- `assets/images/` is declared wholesale
/// in the pubspec, so dropping the PNG in is the whole of the change -- and
/// until then this takes no room and the layout closes up around it rather
/// than reserving a hole.
class FutureCartArt extends StatelessWidget {
  const FutureCartArt({super.key, required this.height, this.asset = mascot});

  /// The mascot at the desk, from the banner.
  static const mascot = 'assets/images/future_cart_mascot.png';

  /// The smaller mascot beside the note at the foot.
  static const mascotSmall = 'assets/images/future_cart_mascot_small.png';

  final String asset;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      height: height,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      errorBuilder: (context, _, _) => const SizedBox.shrink(),
    );
  }
}

/// The back arrow, the title and the lockup.
class FutureCartTopBar extends StatelessWidget {
  const FutureCartTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: FutureCartPalette.topBar,
      child: Padding(
        padding: FutureCartInsets.of(context, top: 6, bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
              color: FutureCartPalette.headline,
              iconSize: 22,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Future Cart',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 21,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: FutureCartPalette.headline,
                    ),
                  ),
                  const SizedBox(height: 1),
                  // Scaled down rather than ellipsised. On a 406pt phone the
                  // lockup leaves this line about 180 points and it came back
                  // as "Smarter suggestions for..." -- which is the half of
                  // the sentence that says nothing. The reference sets it in
                  // full on one line, and shrinking is what keeps all of it.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Smarter suggestions for a happier tomorrow',
                      maxLines: 1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // The supplied lockup, which is light-ground artwork and so belongs
            // on this pale strip. It is in the reference, which is the only
            // reason it is here.
            //
            // 28 rather than 34: the artwork is nearly five times as wide as
            // it is tall, so every point of height costs five of the width the
            // title beside it needs.
            const FutureCartArt(asset: AppBrand.lockupAsset, height: 28),
          ],
        ),
      ),
    );
  }
}

/// "Shop Smarter with Future Cart".
class FutureCartBanner extends StatelessWidget {
  const FutureCartBanner({super.key});

  /// The supplied artwork, and its own proportions: 2172 by 724.
  ///
  /// Reserved from the ratio rather than from a height, so the banner is the
  /// shape it was drawn at on every screen and the page does not reflow when
  /// the file decodes.
  ///
  /// 2042 by 648, not the supplied 2172 by 724: the artwork is a rounded card
  /// standing on a white canvas, and that canvas showed as a white frame
  /// against this page's pale blue ground. The file is cropped to the card --
  /// measured at left 67, top 34, rather than guessed, because the margin is
  /// not even on all four sides. This number has to move with the crop or the
  /// picture is letterboxed inside the shape it used to be.
  ///
  /// **Then taken a little under the file's own 3.151, by request.** The box
  /// is filled with [BoxFit.cover], so a shorter ratio is not free height: the
  /// picture scales up to fill it and loses the difference off its left and
  /// right edges. Measured inside the artwork, the content leaves 5.5% clear
  /// on the left but only **2.8% on the right**, and a centred crop takes from
  /// both -- so the right margin is the ceiling, and 2.8% of the width is the
  /// whole budget before "Ahead!" starts losing its flourish.
  ///
  /// This spends about half of it, roughly 1.4% a side, which buys some four
  /// points of height on a phone. Subtle is the brief, and here it is also the
  /// limit: more height than this wants taller artwork, not a smaller number.
  /// **And cropped again, by eight rows top and bottom.** The first crop was
  /// measured from the card's bounding box, but this card's cream is within
  /// four units of the white canvas it stands on, so the scan stopped late and
  /// left about six rows of that canvas along the top -- near-white, against a
  /// near-white page, which read as a soft rounded edge however square the clip
  /// above it was. That is why "edge to edge with a square top" was invisible
  /// on the device while the widget geometry measured exactly right. The file
  /// is now 2042 by 632, its first row warm cream rather than #FCFCFC.
  static const asset = 'assets/images/future_cart_banner.png';

  /// The file's own ratio is 3.231. This sits a little under it, which is the
  /// "slightly taller" the banner was asked for, carried across the re-crop:
  /// the same ~2.9% below natural that 3.06 was to the old 3.151. See the
  /// note above on [BoxFit.cover] -- that reduction is spent cropping the
  /// left and right edges, and 2.8% is the whole budget before "Ahead!"
  /// starts losing its flourish.
  static const aspect = 3.14;

  @override
  Widget build(BuildContext context) {
    // The supplied banner, exactly as supplied.
    //
    // This was five widgets -- a two-tone heading, the body copy, the mascot
    // slot and the handwritten aside over a gradient -- reproducing the design
    // in Flutter because the artwork did not exist yet. It exists now, so the
    // reproduction is gone and the file is drawn untouched.
    //
    // The heading went from the *page*, not from the picture: the artwork
    // carries "Shop Smarter with Future Cart" itself, so the widget that drew
    // those words as well would have said them twice. The file is the
    // original, byte for byte.
    //
    // The trade is worth naming: type inside a picture cannot answer the
    // reader's text-size setting and cannot be translated, which live text
    // could. That is what "use the provided banner exactly as shown" costs,
    // and it is a deliberate price rather than an oversight.
    //
    // Square across the top, rounded across the foot: the banner runs the full
    // width of the page and meets the bar above it, so a rounded top edge
    // would cut two notches of page ground into that join. The bottom keeps
    // its corners, which is what still reads as a card sitting on the page.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(AppTheme.radiusSection),
      ),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          // Named for a reader who cannot see it, since the words that used to
          // say this are now pixels.
          semanticLabel:
              'Shop smarter with Future Cart. Based on your past purchases, '
              'cart items and lifestyle needs, here are some suggestions for '
              'you.',
          // A missing file leaves the page's own ground rather than a broken
          // picture glyph, and the sections below it still read.
          errorBuilder: (context, _, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  FutureCartPalette.bannerFrom,
                  FutureCartPalette.bannerTo,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// The handwritten aside -- "Better Choices Ahead!" and "Shop Happier!" -- was
// drawn here in the app's own italic with an accent stroke under it, standing
// in for lettering that is artwork in the design. Both banners are now the
// supplied artwork and carry their own lettering, so the stand-in has no
// caller left and is gone rather than kept as a warning.

/// One filter chip.
class FutureCartChip extends StatelessWidget {
  const FutureCartChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.trustBlue : FutureCartPalette.chip,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelLarge?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? AppColors.onPrimary
                    : FutureCartPalette.headline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A section's mark, title, subtitle and "See all".
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.icon,
    required this.ink,
    required this.title,
    required this.subtitle,
    this.ringed = true,
    this.onSeeAll,
  });

  final IconData icon;
  final Color ink;
  final String title;
  final String subtitle;

  /// The reference rings the clock and leaves the puzzle piece bare.
  final bool ringed;

  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: ringed
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ink, width: 2),
                  ),
                  child: Icon(icon, size: 18, color: ink),
                )
              : Icon(icon, size: 27, color: ink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 16.5,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: FutureCartPalette.headline,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'See all',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.trustBlue,
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: AppColors.trustBlue,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Thoughtful suggestions. Always your choice."
class FutureCartFooterNote extends StatelessWidget {
  const FutureCartFooterNote({super.key});

  /// The supplied artwork, cropped to its card: 2121 by 429.
  ///
  /// The white canvas around it is gone -- measured at left 31, top 173, so
  /// most of what surrounded this one was a deep band above and below rather
  /// than at the sides. That makes it a markedly slimmer strip than the file
  /// as supplied (4.94 against 3.00), which is the shape the card always was.
  static const asset = 'assets/images/future_cart_note.png';
  static const aspect = 2121 / 429;

  @override
  Widget build(BuildContext context) {
    // The supplied note, exactly as supplied.
    //
    // This was five widgets -- a leaf, two lines of type, the small mascot and
    // the handwritten aside on a mint panel -- standing in for artwork that did
    // not exist. It does now, so the stand-in is gone.
    //
    // "Always your choice." went from the *page*, not from the picture: the
    // artwork says it already, and the widget that drew those words as well
    // would have said them twice. The file is the original, byte for byte.
    //
    // As with the banner above it, type inside a picture cannot answer the
    // reader's text-size setting and cannot be translated. That is the price
    // of using the artwork as drawn, and it is deliberate.
    //
    // Square top, rounded foot, as the banner above it -- see there for why.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(AppTheme.radiusSection),
      ),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          // The words are pixels now, so they are said here for a reader who
          // cannot see them.
          semanticLabel:
              'Thoughtful suggestions. Always your choice. '
              'Shop happier.',
          // A missing file leaves the page's own quiet panel rather than a
          // broken picture glyph.
          errorBuilder: (context, _, _) => DecoratedBox(
            decoration: BoxDecoration(color: FutureCartPalette.note),
          ),
        ),
      ),
    );
  }
}

/// The bar at the foot, counting what is waiting in the cart.
class BackToCartBar extends StatelessWidget {
  const BackToCartBar({super.key, required this.onTap});

  /// How much of the page the button takes, and the ceiling on it.
  ///
  /// A share rather than its content's width: hugging the words left it about
  /// 250 points on a phone, which read as small for the one action on the
  /// page. At 82% it comes to roughly 330 points on a 406-point screen -- a
  /// clear button with a margin still showing either side, rather than the
  /// full-bleed slab it started as.
  ///
  /// The cap is for tablets and desktops, where a share of the width and the
  /// whole width amount to the same thing for one short sentence.
  static const widthFactor = 0.82;
  static const maxWidth = 420.0;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: FutureCartInsets.of(context, top: 6, bottom: 10),
        child: ListenableBuilder(
          listenable: CartStore.instance,
          builder: (context, _) {
            // Units, not lines: a shopper who put three of something in
            // expects the bar to count three, which is the rule the header
            // badge already follows.
            final count = CartStore.instance.count;

            // A button across most of the page, not a slab across all of it.
            //
            // Three shapes in three passes, which is worth recording. It began
            // full-bleed with the label stranded between an icon at one edge
            // and a chevron at the other. Then it hugged its words, which was
            // too small and too round -- a stadium that far from the edges
            // reads as a floating chip rather than as this page's one action.
            // It now takes [widthFactor] of the page on the app's own card
            // corner, with the lift under it that says "button over content".
            return Center(
              // Shrink-wrapped vertically. Without this the page went blank:
              // `Scaffold.bottomNavigationBar` hands its child the whole
              // screen as a loose constraint, and a bare Center expands to
              // fill what it is given -- so the bar took the entire height and
              // the body was squeezed to nothing. The width is left to expand,
              // which is what centres the pill across the page.
              heightFactor: 1,
              child: FractionallySizedBox(
                widthFactor: widthFactor,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: maxWidth),
                  child: Material(
                    color: AppColors.trustBlueDeep,
                    // The app's own card corner, not a stadium. Fully rounded
                    // read as a floating chip; this is the one action on the
                    // page and it should look like the buttons around it.
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    elevation: 6,
                    shadowColor: AppColors.trustBlueDeep.withValues(alpha: 0.5),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onTap,
                      child: Padding(
                        // Height comes from this rather than a fixed box, so
                        // the button grows with the reader's text setting
                        // instead of clipping the words in a 54-point slot.
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Row(
                          // The box is a share of the page now, so the three
                          // parts sit together in the middle of it rather than
                          // being pushed out to its corners.
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.shopping_cart_outlined,
                              size: 20,
                              color: AppColors.onPrimary,
                            ),
                            const SizedBox(width: 10),
                            // Flexible, not Expanded: the words keep their own
                            // width in the middle of the row, and this only
                            // gives them somewhere to shrink into on a narrow
                            // screen or at a large text setting.
                            Flexible(
                              child: Text(
                                'Back to My Cart '
                                '($count ${count == 1 ? 'item' : 'items'})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: AppColors.onPrimary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The grid's shape while the page is in flight.
///
/// Built from the real card's own [SuggestionCard.heightFor] and column count,
/// so the placeholders are not merely a similar size -- they are the size, and
/// the cards cannot jump into a different layout when they land.
class SuggestionGridSkeleton extends StatelessWidget {
  const SuggestionGridSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Shimmer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth;
          final columns = SuggestionCard.columnsFor(available);
          const gap = SuggestionCard.gridGap;
          final width = (available - gap * (columns - 1)) / columns;
          final height = SuggestionCard.heightFor(context, width);

          return Wrap(
            spacing: gap,
            runSpacing: gap,
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
                    padding: const EdgeInsets.all(SuggestionCard.pad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const ShimmerPanel(
                          aspectRatio: 1,
                          radius: AppTheme.radiusCard,
                        ),
                        const SizedBox(height: 8),
                        const ShimmerBone(),
                        const SizedBox(height: 4),
                        ShimmerBone(width: width * 0.55),
                        const SizedBox(height: 6),
                        ShimmerBone(width: width * 0.45, height: 13),
                        const SizedBox(height: 8),
                        const ShimmerBone(height: 24, radius: 8),
                        const SizedBox(height: 8),
                        const ShimmerBone(height: 26, radius: 10),
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
