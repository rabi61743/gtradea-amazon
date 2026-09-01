import 'package:flutter/material.dart';

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
class FlashSaleCard extends StatefulWidget {
  const FlashSaleCard({super.key, required this.sale, this.onTap, this.now});

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

  @override
  Widget build(BuildContext context) {
    // Gone the moment it runs out. A "Flash Sale" heading over a clock reading
    // zeros is worse than no card: it advertises an offer that has stopped.
    if (_ended) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final subhead = widget.sale.subhead;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      // Outside the Material, which clips: a shadow drawn on the Ink inside
      // would be cut off at the very edge it is meant to fall past.
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Rounded to the card's own radius, so the shadow follows its
          // corners rather than boxing them.
          borderRadius: BorderRadius.circular(AppTheme.radiusCard + 10),
          // Two layers rather than one, which is what makes it read as a
          // shadow instead of a grey outline: a close, tighter one for the
          // contact edge, and a wider, fainter one for the diffusion that
          // falls away from it. Both offset down and a little right, as if
          // the light were above and to the left.
          boxShadow: const [
            BoxShadow(
              color: Color.fromARGB(239, 238, 5, 5),
              // color: Color(0x14000000),
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
          borderRadius: BorderRadius.circular(AppTheme.radiusCard + 10),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              gradient: AppColors.flashSaleBand,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard + 10),
            ),
            child: InkWell(
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
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
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.bolt,
                            size: 24,
                            color: AppColors.onAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
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
                            style: theme.textTheme.headlineSmall?.copyWith(
                              // White on the red now. The heading was red on white
                              // until the card was filled; red on red is nothing.
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        if (widget.onTap != null) const _ShopNow(),
                      ],
                    ),
                    if (subhead != null && subhead.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _Subhead(text: subhead),
                    ],
                    const SizedBox(height: 14),
                    // The clock in a panel of its own, a shade lighter than the
                    // card. It is the reason this block is at the top of the page,
                    // so it gets a frame rather than sitting loose on the teal.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        // A wash of white over the red rather than a colour of its
                        // own, so the panel stays a shade of the card however the
                        // gradient behind it changes.
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusCard,
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
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
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // White on the card's red: 5.55:1 at its lightest point, 7.30 at its
    // darkest. Ordinary text needs 4.5, which is the whole reason the card's
    // red is a shade deeper than the design's -- see [AppColors.flashSaleTop].
    final base = theme.textTheme.bodyMedium?.copyWith(
      color: Colors.white,
      height: 1.35,
    );

    // The last sentence, if there is more than one. `lastIndexOf` on the
    // second-to-last stop, so "a. b. c!" splits before "c!".
    final trimmed = text.trimRight();
    final cut = trimmed.lastIndexOf(RegExp(r'[.!?]\s+'));
    if (cut < 0) return Text(text, style: base);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: trimmed.substring(0, cut + 1), style: base),
          const TextSpan(text: ' '),
          TextSpan(
            text: trimmed.substring(cut + 1).trimLeft(),
            style: base?.copyWith(
              color: AppColors.flashSaleHurry,
              fontWeight: FontWeight.w800,
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
