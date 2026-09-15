import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/widgets/page_width.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../data/flash_sale.dart';
import 'sale_countdown.dart';

/// The Flash Sale card: what it is, how long is left, and why it is worth a tap.
///
/// Sits directly under the banner, above the deals panel. Deliberately not the
/// same block: the panel below shows what is in the sale, and this says the
/// sale is running and running out. One is merchandise, the other is a
/// deadline, and a deadline earns the top of the page because it is the one
/// thing here whose value goes to zero if it is scrolled past.
///
/// A filled red card: the bolt on its own tile, the heading and the subhead in
/// white, "Hurry up!" in pale yellow, a white "Shop now" pill, and the clock in
/// white boxes on a wash of the card's own colour.
///
/// It has been three things now, and the reasons are worth keeping. It was a
/// deep-teal panel with a white heading; then the heading went red, and red on
/// that teal measures **1.82:1**, which is a smudge rather than a heading, so
/// the card went white to carry it. It is red again by request, and the heading
/// is white again for the same reason in reverse: red on red is nothing.
///
/// **On the red itself.** The design's red is brighter than this one. White
/// body copy on it measures 4.05:1 and ordinary text needs 4.5, and this card
/// carries a sentence, not just a heading. So the ground is the same hue at a
/// lower lightness -- 5.55:1 at the top of the gradient, 7.30 at the bottom --
/// and every word on the card clears AA at the size it is actually set in. See
/// [AppColors.flashSaleTop] for the measurements.
///
/// The card being filled at all is a stated exception to the 60-30-10 budget,
/// recorded beside those colours rather than quietly taken.
///
/// The card carries a row of marks at its foot for a while -- the largest
/// discount, the number of deals, a note about checkout. They are gone. The
/// reference's own version of that row said "Best prices ever" and "When it's
/// gone, it's gone!", which this catalogue cannot support; what replaced it was
/// true but was a second summary of the deals panel sitting directly below,
/// under a card whose whole job is the deadline.
/// The black lift under the card's own furniture.
///
/// Every raised thing on the card carries the same one -- the bolt tile, the
/// countdown panel and the Shop now pill -- so they read as one set of objects
/// on the red rather than three separate treatments. Soft and low, cast down
/// and slightly right, as the card's own shadow is.
const _lift = [
  BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(1, 3)),
];

/// The same lift for words, which take a [Shadow] rather than a [BoxShadow].
///
/// Tighter than the boxes': type carries a shadow far less well, and a blur
/// wide enough for a panel turns a headline muddy.
const _inkLift = [
  Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(1, 2)),
];

class FlashSaleCard extends StatefulWidget {
  const FlashSaleCard({super.key, required this.sale, this.onTap, this.now});

  /// The card's own padding, inside its rounded edge.
  ///
  /// On the widget rather than its state because a test needs it: four places
  /// depended on this number and three carried their own copy -- this padding,
  /// the artwork's sizing, the clock's reserve, and a test computing the room
  /// the clock should get. Taking the visible one from 11 to 8 left the other
  /// three behind, so the card reserved space for a layout it no longer had
  /// and the test failed a card that was doing exactly what it was asked.
  static const pad = 8.0;

  final FlashSale sale;

  /// Where the card goes. The deals page, same as the panel below it -- a card
  /// on this page that led nowhere would be the only one.
  final VoidCallback? onTap;

  /// The clock, injectable so a test can put the sale in the past.
  final DateTime Function()? now;

  @override
  State<FlashSaleCard> createState() => _FlashSaleCardState();
}

class _FlashSaleCardState extends State<FlashSaleCard> {
  late bool _ended = widget.sale.hasEndedAt((widget.now ?? DateTime.now)());

  @override
  void didUpdateWidget(FlashSaleCard old) {
    super.didUpdateWidget(old);
    if (old.sale.endsAt != widget.sale.endsAt) {
      _ended = widget.sale.hasEndedAt((widget.now ?? DateTime.now)());
    }
  }

  /// The clock in its panel, unchanged.
  Widget _timerPanel() {
    // The clock in a panel of its own, a shade lighter than the
    // card. It is the reason this block is at the top of the page,
    // so it gets a frame rather than sitting loose on the teal.
    return Container(
      width: double.infinity,
      // Vertical only, and no ground of its own. The banner is the card's own
      // background now and shows through here; a wash, a hairline and a lift
      // over artwork would read as a panel sitting on the picture rather than
      // as the clock the picture is for.
      //
      // The cells inside keep theirs -- white boxes, red digits, white labels
      // -- which is what keeps the figures legible over the red.
      padding: const EdgeInsets.symmetric(vertical: 5),
      // Room to shrink only if it ever needs it. At the sizes people
      // actually use this does nothing; at 2x text the four cells
      // are wider than a phone and something has to give, and a
      // clock scaled a little beats an overflow.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SaleCountdown(
          endsAt: widget.sale.endsAt,
          now: widget.now,
          // Days, Hours, Minutes, Seconds, each labelled and each in
          // its own box. The light variant, because the card under
          // it is white now -- white boxes and white unit labels
          // would both disappear into it.
          boxed: true,
          // The smaller cells. Every figure and label is still
          // there and still legible; they simply stop taking a
          // block's worth of height on a card that was asked to
          // read as a banner.
          compact: true,
          // The on-colour variant: white boxes with red digits,
          // white unit labels, white colons. It is the variant this
          // card used while it was teal, and it is what the card
          // needs again now that it is filled.
          onLight: false,
          onEnded: () {
            if (mounted) setState(() => _ended = true);
          },
        ),
      ),
    );
  }

  /// The shape the artwork is drawn at in the card's corner.
  ///
  /// Not the file's own 3:1 -- that is a wide banner, and the corner wants the
  /// gift itself. The box is filled from the right, so what falls outside it is
  /// the flat red the artwork has nothing in.
  static const _artAspect = 1.25;

  /// How much of the card's width the artwork takes, and how tall it is drawn.
  ///
  /// From the reference: a little over a fifth of the width, standing about
  /// four fifths of the card's height in its bottom-right corner. Shares rather
  /// than fixed points, so it keeps its place on a phone, a tablet and a
  /// desktop window alike -- with a ceiling on the height, because the card's
  /// height comes from the type on it and not from the width of the screen.
  static const _artShare = 0.22;
  static const _artMaxHeight = 86.0;

  /// What the clock needs before the artwork is given anything, and the gap
  /// between the two.
  ///
  /// 250 is measured: the four cells, their colons, the labels under them and
  /// the panel's own padding and border come to a little over 230, and below
  /// that the panel's FittedBox starts scaling the clock down.
  static const _clockFloor = 250.0;
  static const _artGap = 8.0;

  /// The artwork's box, or null on a card too narrow to give it one.
  static Size? _artSize(double cardWidth) {
    const padding = FlashSaleCard.pad;
    final room = cardWidth - padding * 2 - _artGap - _clockFloor + padding;
    final width = math.min(
      math.min(cardWidth * _artShare, room),
      _artMaxHeight * _artAspect,
    );
    if (width < 56) return null;
    return Size(width, width / _artAspect);
  }

  @override
  Widget build(BuildContext context) {
    // Gone the moment it runs out. A "Flash Sale" heading over a clock reading
    // zeros is worse than no card: it advertises an offer that has stopped.
    if (_ended) return const SizedBox.shrink();

    return Padding(
      // 97% of the screen, centred, which is the measure every section down
      // this page shares -- see [PageWidth].
      //
      // Six above rather than fourteen. This is the gap between the hero and
      // this card, and it is one of the two largest at the top of the page --
      // the last pass at the home page's spacing missed it entirely, because
      // it belongs to the card rather than to the feed that stacks it.
      //
      // [FlashSaleCardSkeleton] carries the same measure and has to move with
      // it, or the page shifts when the sale lands.
      padding: PageWidth.insets(context, top: 6),
      // Outside the Material, which clips: a shadow drawn on the Ink inside
      // would be cut off at the very edge it is meant to fall past.
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Rounded to the card's own radius, so the shadow follows its
          // corners rather than boxing them.
          //
          // The theme's plain card radius, which is what the product cards and
          // the deal tiles take. It was 22, then briefly the carousel's 16 --
          // and 22 to 16 turned out to be invisible at this size, six points of
          // radius on a card the width of the screen. 12 is a step you can
          // actually see, and it lines this card up with the cards rather than
          // with the banner above it.
          //
          // All four places that carry the radius move together: this shadow,
          // the Material that clips, the Ink beneath the artwork, and the
          // skeleton that stands in while the sale loads.
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          // Two layers rather than one, which is what makes it read as a
          // shadow instead of a grey outline: a close, tighter one for the
          // contact edge, and a wider, fainter one for the diffusion that
          // falls away from it. Both offset down and a little right, as if
          // the light were above and to the left.
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(2, 3),
            ),
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 24,
              // Pulled in, so the far layer reads as a soft halo under the
              // card rather than a second edge around it.
              spreadRadius: -10,
              offset: Offset(4, 8),
            ),
          ],
        ),
        child: Material(
          // Filled red, edge to edge. Everything on it is drawn on the gradient
          // rather than on the page, which is why the card needs no border: the
          // colour is the edge.
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              // The gradient stays underneath the picture: it is what the card
              // is if the file ever fails to load, and what shows through the
              // scrim on the left where the artwork is only flat red anyway.
              gradient: AppColors.flashSaleBand,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              // The supplied banner, filling the card from the right.
              //
              // Cover rather than fill: the file is 3:1 and this card is nearer
              // 2.7:1, so covering it crops a little from one side and nothing
              // is stretched. Aligned right, so what is cropped is the flat red
              // at the artwork's left end and what is kept is the gift.
              image: const DecorationImage(
                image: AssetImage('assets/images/gift_banner.jpg'),
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
              ),
            ),
            child: InkWell(
              onTap: widget.onTap,
              child: LayoutBuilder(
                builder: (context, box) {
                  final art = _artSize(box.maxWidth);
                  return Stack(
                    children: [
                      // A scrim over the artwork's left-hand side, where every
                      // word on this card is set.
                      //
                      // The picture is busy on the right and plain on the left,
                      // so this is heaviest where the words are and gone by the
                      // time it reaches the gift: the heading, the sentence and
                      // the clock keep the contrast they had, and the artwork
                      // keeps the part of it worth seeing.
                      const Positioned.fill(child: _BannerScrim()),
                      _content(
                        context,
                        // The clock stops before the gift begins.
                        reserve: art == null
                            ? 0
                            : art.width - FlashSaleCard.pad + _artGap,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Everything written on the card, over the artwork.
  Widget _content(BuildContext context, {required double reserve}) {
    final theme = Theme.of(context);
    final subhead = widget.sale.subhead;

    return Padding(
      // Trimmed from 16, then to 11, and now to [pad]: the card's height is
      // the bulk between the hero and the promo banners, and padding is the
      // part of it that costs nothing to read.
      //
      // [FlashSaleCardSkeleton.height] mirrors what this produces and is
      // pinned against the real card by a test, so it moves with this.
      padding: const EdgeInsets.all(FlashSaleCard.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // The bolt, on a tile a shade lighter than the card so it
              // reads as a mark rather than as a hole. Commerce Orange
              // itself: the card's own gradient is that colour with the
              // light taken out, so the tile is the accent at full
              // strength. White on it is 3.90:1, which an icon needs 3
              // for.
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _lift,
                ),
                child: const Icon(
                  Icons.bolt,
                  size: 20,
                  color: AppColors.onAccent,
                ),
              ),
              const SizedBox(width: 10),
              // Expanded, and no Spacer after it. It was Flexible with a
              // Spacer beside it, and both are flex:1 -- so the row split
              // its free space evenly between the words and the gap, and
              // the label ellipsised to "Flash ..." on a 412dp handset
              // with room to spare. Taking the space here and letting the
              // button sit at the end of it is the same layout with the
              // words intact.
              Expanded(
                child: Text(
                  'Flash Sales',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    // White on the red now. The heading was red on white
                    // until the card was filled; red on red is nothing.
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    shadows: _inkLift,
                  ),
                ),
              ),
              if (widget.onTap != null) const _ShopNow(),
            ],
          ),
          if (subhead != null && subhead.isNotEmpty) ...[
            const SizedBox(height: 3),
            _Subhead(text: subhead),
          ],
          const SizedBox(height: 4),
          // The clock, ending where the corner artwork begins.
          Padding(
            padding: EdgeInsets.only(right: reserve),
            child: _timerPanel(),
          ),
        ],
      ),
    );
  }
}

/// "Unbeatable deals. Limited stock. **Hurry up!**"
///
/// The sale's own subhead, split at its last sentence so the urgent half can
/// carry the accent. Split rather than hardcoded: the words come from the sale,
/// and one that ends differently still renders -- it simply gets no accent.
class _Subhead extends StatelessWidget {
  const _Subhead({required this.text});

  final String text;

  /// One line, cut where it runs out. The card's height is the one it was asked
  /// to match, and a sale whose subhead runs long must not be the thing that
  /// grows it back.
  static const _clip = TextOverflow.ellipsis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // White on the card's red: 5.55:1 at its lightest point, 7.30 at its
    // darkest. Ordinary text needs 4.5, which is the whole reason the card's
    // red is a shade deeper than the design's -- see [AppColors.flashSaleTop].
    final base = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white,
      height: 1.25,
    );

    // The last sentence, if there is more than one. `lastIndexOf` on the
    // second-to-last stop, so "a. b. c!" splits before "c!".
    final trimmed = text.trimRight();
    final cut = trimmed.lastIndexOf(RegExp(r'[.!?]\s+'));
    if (cut < 0) {
      return Text(text, style: base, maxLines: 1, overflow: _clip);
    }

    return Text.rich(
      maxLines: 1,
      overflow: _clip,
      TextSpan(
        children: [
          TextSpan(text: trimmed.substring(0, cut + 1), style: base),
          const TextSpan(text: ' '),
          TextSpan(
            text: trimmed.substring(cut + 1).trimLeft(),
            style: base?.copyWith(
              color: AppColors.flashSaleHurry,
              fontWeight: FontWeight.w800,
              shadows: _inkLift,
            ),
          ),
        ],
      ),
    );
  }
}

/// The way in, as a filled pill.
///
/// Outlined in white while the card was teal; on a white card an outline in the
/// same red as the heading would be a second red thing competing with it, so it
/// is filled instead -- which is what the rest of the app does with a call to
/// action anyway.
class _ShopNow extends StatelessWidget {
  const _ShopNow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: _lift,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Shop now',
            style: theme.textTheme.labelMedium?.copyWith(
              // The card's deeper red rather than the accent: on white, the
              // accent is 3.90:1 and this label is not large text. This is
              // 7.30:1, and it is the same colour the card is made of.
              color: AppColors.flashSaleBottom,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 5),
          const Icon(
            Icons.arrow_forward,
            size: 14,
            color: AppColors.flashSaleBottom,
          ),
        ],
      ),
    );
  }
}

/// The wash between the banner and the words set on it.
///
/// The card's own colour at the left, where the heading, the sentence and the
/// clock are, fading out across the middle so the gift at the right end is left
/// as the artwork drew it. Without it the type sits on a picture with its own
/// highlights and loses its edge; with it the card reads as one thing.
class _BannerScrim extends StatelessWidget {
  const _BannerScrim();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            // The card's own red at nearly full strength under the words, and
            // nothing at all by the time it reaches the gift.
            Color(0xF2B5301A),
            Color(0xD9B5301A),
            Color(0x00B5301A),
          ],
          stops: [0.0, 0.42, 0.78],
        ),
      ),
    );
  }
}
