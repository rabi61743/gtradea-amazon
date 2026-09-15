import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/animated_search_hint.dart';
import '../../../shared/widgets/brand_lockup.dart';
import '../../auth/data/auth_store.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../profile/data/profile_store.dart';
import '../../orders/presentation/order_tracker_button.dart';
// The anchor registry, so the tour can ring the real Orders icon below rather
// than a copy of it drawn for the overlay.
import '../../tour/data/tour_step.dart';
import '../../search/widgets/voice_search_sheet.dart';
import '../../support/presentation/support_button.dart';
import 'delivery_points_card.dart';

/// The brand band at the top of home: the lockup, the chrome, and search.
///
/// Three rows. The brand takes the first on its own -- mark, name and tagline,
/// with room around it, which is what makes the header read as a masthead
/// rather than as a toolbar. The delivery line and the three actions share the
/// second, and the search pill gets the full width of the third.
///
/// **One band, painted once.** This widget draws no background of its own. The
/// shell puts a single top-to-bottom gradient behind it and the department
/// strip together -- [AppColors.brandBand], dark teal at the status bar easing
/// into the brand teal by the time it reaches the products.
///
/// One decoration for both, deliberately. Giving each its own gradient would
/// run the ramp twice and snap back to the dark end at the join, which is the
/// seam this header has already had removed once.
///
/// Everything lines up on a single [_edge] inset -- see [_bellEdge] for the one
/// number that looks wrong and is not. The pill is deliberately white in both
/// brightnesses because it sits on the teal rather than on the page
/// background, so every child pins its own colour or inherits one that would
/// vanish against it.
class SearchHeader extends StatelessWidget {
  const SearchHeader({
    super.key,
    // The fixed lead of the placeholder. The example after it is animated --
    // see [AnimatedSearchHint] -- so this is the half that stays put.
    this.hintText = 'Search ',
    this.onTap,
    this.onImageSearch,
    this.onVoiceResult,
    this.compact = false,
  });

  /// True once the shopper is reading rather than arriving.
  ///
  /// Collapses both of the rows above the search bar -- the brand line and
  /// the utilities line -- and leaves what a shopper still needs while they
  /// read: the greeting and the search bar. The band shrinks with them, so the
  /// Himalayan artwork behind gives up its height at the same rate rather than
  /// being switched off.
  ///
  /// Nothing is disposed. The controls come back on the way up with the same
  /// state and the same badges, along the same curve they left by.
  final bool compact;

  /// How long the fold takes, each way.
  ///
  /// One duration and one curve for every part of it -- the height, the fade
  /// and the slide -- because they are one movement. Different timings on the
  /// three is what makes a header look like it is coming apart.
  static const fold = Duration(milliseconds: 450);

  /// The curve the band folds away on.
  ///
  /// An ease-**in**-out, and that is the half of this that matters more than
  /// the duration. The fold ran on an ease-out, which spends most of its
  /// travel in the first few frames and coasts into the finish: the band left
  /// the moment a scroll began and then drifted, which reads as the picture
  /// being snatched away rather than as it moving. Easing in as well gives it
  /// a gentle start, so it takes up the movement with the page instead of
  /// bolting ahead of it.
  static const foldCurve = Curves.easeInOutCubic;

  /// And the curve it comes back on.
  ///
  /// Still an ease-out, deliberately not matched to [foldCurve]. Coming back
  /// answers a deliberate reach for the search bar, and a gradual start there
  /// is indistinguishable from lag -- the one thing the quick return exists to
  /// avoid. Leaving is unprompted and can afford to be gentle; arriving is
  /// asked for and should be immediate.
  static const revealCurve = Curves.easeOutCubic;

  /// How long it takes to come *back*.
  ///
  /// Shorter than [fold], and deliberately not symmetric with it. The two
  /// directions are answering different things: folding away happens while the
  /// shopper is reading and can afford to be unhurried, where unfolding is the
  /// direct answer to a gesture -- they have reached up for the search bar, and
  /// every millisecond before it arrives reads as lag rather than as grace.
  ///
  /// Still eased rather than snapped: [revealCurve] runs over a shorter
  /// distance in time, so the band arrives quickly without the last few points
  /// of its travel landing as a jolt.
  static const reveal = Duration(milliseconds: 170);

  final String hintText;
  final VoidCallback? onTap;
  final VoidCallback? onImageSearch;

  /// Called with what the shopper dictated, once, only when something was
  /// heard.
  final ValueChanged<String>? onVoiceResult;

  /// The one inset everything in this header resolves to.
  static const double _edge = 16;

  /// How much clear band there is under the last row, before the band ends.
  ///
  /// Small by request: the greeting and the search pill are to sit low in the
  /// band, against its lower portion rather than centred in it. It was 32 for a
  /// while, which held them clear of the foot and read as a gap.
  ///
  /// Not nothing, and that is not a hedge against the brief. The band's corners
  /// are cut round, and a row flush to the foot would have the pill's ends run
  /// into that curve on both sides -- the one thing that would read as a
  /// mistake rather than as a design. Ten points is what puts the pill inside
  /// the last of the curve: at that height the corner has come in about three
  /// and a half points, and the pill's own margin is sixteen.
  ///
  /// Nothing here is proportional -- the foot of the band is in the same place
  /// relative to the type on a phone, a tablet and a desktop window, so the
  /// room under it is a fixed measure too.
  static const double footRoom = 10;
  static const double footRoomCompact = 8;

  /// And above the first row.
  ///
  /// The head keeps its room while the foot gives its up, which is what pushes
  /// the greeting and the pill down into the lower part of the band instead of
  /// simply making the band shorter.
  ///
  /// Ten points off each, by request: this is the clear band between the status
  /// bar and the brand lockup, and it was the only genuinely empty space at the
  /// top of the header. The status-bar inset below is *not* part of it -- that
  /// is what lets the teal run behind the clock rather than stopping at a white
  /// strip, and taking from it would slide the lockup under the signal icons.
  ///
  /// Taken again, 18 to 8, because the first cut was not visible.
  ///
  /// 28 to 18 moved the whole header up about ten points, which measures
  /// plainly and reads as nothing: the status bar above it is forty points on
  /// this class of phone, so a ten-point change is a seventh of the space above
  /// the mark. Eight is close to the floor -- the inset is the rest, and taking
  /// from that would put the lockup under the clock.
  static const double _headRoom = 8;
  static const double _headRoomCompact = 6;

  /// How tall the brand mark is drawn, from the width of the screen.
  ///
  /// The lockup is the first thing on the page and the reference gives it
  /// room, so it is bigger than the 30pt mark this header used to carry -- but
  /// sized rather than fixed, because the same 40pt block that reads as
  /// generous on a tablet crowds the delivery line on a 320pt phone.
  static double _markHeight(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // 30 draws the lockup about 130pt wide, which is the width the design
    // asks for. Below 360 the row has the country line to fit as well, so the
    // mark gives way first; a tablet gets the top of the range.
    if (width < 360) return 26;
    if (width < 600) return 30;
    return 34;
  }

  /// The search pill, so a test can measure the edges this header is about.
  static const pillKey = ValueKey('home-search-pill');

  /// The glyph size the three labelled header actions share.
  ///
  /// Smaller than Material's 24 so the group reads as chrome rather than as
  /// three buttons, and a little larger than the 15 the bare icons used: they
  /// now carry a word underneath, so the glyph is half of a control rather
  /// than all of one.
  ///
  /// 17 rather than 20 since the group was compacted by request. The word
  /// under it came down with it -- shrinking the glyph alone would have left
  /// three small icons under three labels the same size as before, which is
  /// the arrangement, not the icon, taking the room.
  ///
  /// Their tap targets are the tiles, which are taller and wider than the
  /// glyph, so this changes what is drawn and not what can be pressed.
  static const double _headerIconSize = 17;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The band already fills the status bar area. Without this the icons in
      // it are drawn dark on dark teal.
      value: AppTheme.brandBandOverlay,
      // No background of its own -- see the class doc. The shell paints the
      // band behind this and the department strip together.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The status bar inset is absorbed here rather than by a SafeArea so
          // the teal runs behind it instead of stopping at a white strip. It
          // stays whether or not the row below it is folded away.
          SizedBox(height: MediaQuery.of(context).padding.top),
          // One value drives the whole fold: 0 at the top of the feed, 1 once
          // the shopper is reading. Everything that moves is a lerp on it --
          // the paddings, the gap, the row's height, its opacity and how far
          // it has slid -- so there is nothing to fall out of step and nothing
          // to snap.
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: compact ? 1 : 0),
            // Whichever way it is going: the leisurely one on the way out, the
            // quick one on the way back. One value still drives every part of
            // the movement, so the height, the fade and the slide stay in step
            // with each other at either speed.
            duration: compact ? fold : reveal,
            // The curve goes with the direction, as the duration does: gentle
            // at both ends on the way out, immediate on the way back.
            curve: compact ? foldCurve : revealCurve,
            builder: (context, t, _) => Padding(
              // Horizontal insets live here rather than on the container, so
              // the colour still reaches both edges. The vertical ones tighten
              // as the header compresses, which is most of what makes the band
              // read as compact rather than merely shorter.
              padding: EdgeInsets.fromLTRB(
                _edge,
                lerpDouble(_headRoom, _headRoomCompact, t)!,
                _edge,
                lerpDouble(footRoom, footRoomCompact, t)!,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The brand on its own line, with room around it:
                  // the mark, the name and the line under it. The row
                  // below is two blocks that each want the width, so
                  // there is nowhere on it for a lockup to sit.
                  //
                  // Told what it is sitting on. The theme's surface colour
                  // would have the mark pick its light-surface version, whose
                  // blue quarter is Trust Blue -- which this band is a shade
                  // of, so half the logo would vanish into it.
                  //
                  // The band's *top* colour, since that is where the mark
                  // sits now that the band is a ramp. It is darker than the
                  // flat teal was, so the on-dark mark is still the right one.
                  // Row one: the brand at the left, and the country line at
                  // the right as a quiet second element.
                  //
                  // It folds away with the row below it. A shopper reading a
                  // feed is not looking for the company's name -- they are
                  // looking for the search bar, and the greeting beside it is
                  // enough to say whose shop this is.
                  ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: 1 - t,
                      child: Opacity(
                        opacity: (1 - t * 1.25).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, -14 * t),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              BrandLockup(
                                height: _markHeight(context),
                                behind: AppColors.brandBandTop,
                              ),
                              const SizedBox(width: 12),
                              // The country line gives way rather than pushing
                              // the row over the edge: it is the second
                              // element here, and a narrow screen is the case
                              // where that has to be true in layout and not
                              // only in the reading order.
                              const Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: _ProudlyNepalBanner(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // The gap goes with the row it separates.
                  SizedBox(height: lerpDouble(18, 0, t)),
                  // The utilities row: it slides up, fades, and releases its
                  // height together. ClipRect + Align is what gives the height
                  // back smoothly -- the row keeps its own layout at full size
                  // and is revealed by a fraction of it, so nothing inside
                  // reflows on the way out.
                  ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: 1 - t,
                      child: Opacity(
                        // Faded out a little ahead of the height, so the row is
                        // gone before its last few points of space are.
                        opacity: (1 - t * 1.25).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, -14 * t),
                          child: Row(
                            // Centred, not stretched: the row sits in a Column
                            // as tall as its children, and the two groups are
                            // brought to one height by their own minimums.
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Where it goes and what can pay towards it: the
                              // delivery address and the points balance, in the
                              // reference card, on the left of the icons.
                              const Expanded(child: DeliveryPointsCard()),
                              // A tight gap, by request: the icon group sits
                              // close to the card rather than floating off it.
                              const SizedBox(width: 6),
                              // Where to go: three destinations, each named
                              // under its glyph. The words are the point --
                              // three bare icons on a teal band were a guessing
                              // game, and the truck in particular read as
                              // delivery rather than orders.
                              _Block(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    OrderTrackerButton(
                                      // The real icon is what the tour rings.
                                      key: TourAnchors.instance.keyOf(
                                        TourAnchor.orders,
                                      ),
                                      label: 'Orders',
                                      color: AppColors.onPrimary,
                                      size: _headerIconSize,
                                    ),
                                    // Messages before notifications, by
                                    // request: orders, then the conversation
                                    // about them, then the alerts.
                                    const SupportButton(size: _headerIconSize),
                                    const NotificationBell(
                                      label: 'Notifications',
                                      color: AppColors.onPrimary,
                                      size: _headerIconSize,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // The last row, low in the band: the greeting on the left and
                  // the search pill taking the rest of the width, the two
                  // centred against each other.
                  //
                  // The pill stays through the fold and closes up under the
                  // brand as the row above it goes.
                  Padding(
                    padding: EdgeInsets.only(top: lerpDouble(14, 8, t)!),
                    child: Row(
                      // Both halves on one line through their middles. The
                      // greeting is two short lines and the pill is a single
                      // tall shape, so without this the two would hang from
                      // their tops and the pill would sit low against a
                      // greeting that does not.
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Sizes to its words and takes nothing when there is
                        // nobody to greet, so the pill keeps the full width it
                        // had for a signed out shopper.
                        const _Greeting(),
                        Expanded(
                          child: _SearchPill(
                            key: pillKey,
                            hintText: hintText,
                            onTap: onTap,
                            onImageSearch: onImageSearch,
                            onVoiceResult: onVoiceResult,
                          ),
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
    );
  }
}

/// The country banner at the right of the brand row.
///
/// Artwork now, where it used to be type. The words were set here because no
/// mark for them had been supplied; one has, so the type is gone and nothing
/// stands in its place -- an image that fails to load leaves the slot empty
/// rather than falling back to the sentence it replaced.
///
/// Drawn at the lockup's own height and no taller, so the brand row is the
/// height it always was and the header with it. The [FittedBox] above scales
/// it down on a narrow screen; between the two, the banner keeps its
/// proportions at every width and can neither stretch nor crop.
class _ProudlyNepalBanner extends StatelessWidget {
  const _ProudlyNepalBanner();

  /// Where the supplied artwork lives.
  ///
  /// The file supplied carried its own flat teal rectangle, which on a gradient
  /// band reads as a pasted-on block with visible edges -- and the reference
  /// design shows no such block. What ships is that same artwork with the
  /// ground keyed out and the empty margin trimmed off, so the header sizes the
  /// words rather than the space around them. Nothing was redrawn.
  static const asset = 'assets/brand/proudly_nepal.png';

  /// How tall it is drawn, against the brand mark opposite it.
  ///
  /// From the reference: the banner stands about 1.7 times the mark there, and
  /// takes roughly a third of the width -- which is what this comes to at the
  /// artwork's own 2.24:1, on every screen size, because both numbers are
  /// derived rather than fixed.
  static const heightFactor = 1.7;

  /// The supplied artwork's own shape, 1204 by 538.
  ///
  /// Used to reserve the space before the file has decoded, so the brand row
  /// does not reflow the moment it arrives. It is not a shape imposed on the
  /// picture: [BoxFit.contain] still letterboxes anything of another ratio
  /// rather than stretching it.
  static const aspect = 1204 / 538;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: SearchHeader._markHeight(context) * heightFactor,
      width: SearchHeader._markHeight(context) * heightFactor * aspect,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        // Nothing at all until the file is there. A missing asset must not put
        // a broken-image glyph on the masthead, and must not bring the words
        // back either.
        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      ),
    );
  }
}

/// One of the two rounded blocks on the chrome row.
///
/// A wash of white over the band rather than a colour of its own: the band is
/// a gradient, and a flat fill here would read as a patch on it at one end of
/// the ramp and vanish at the other. Alpha keeps the ramp showing through, so
/// the blocks sit on the teal at whatever shade it happens to be.
///
/// Nothing about it is a card -- no shadow, no border. It is there to group,
/// not to lift.
class _Block extends StatelessWidget {
  const _Block({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      // The Delivery + Points card's own height, from the one number both
      // use, so the two surfaces on this row are exactly level: 44 on a
      // phone, 56 on a tablet or desktop. A floor rather than a fixed height,
      // so a large text setting grows it rather than clipping it.
      constraints: BoxConstraints(
        minHeight: DeliveryPointsCard.rowHeight(context),
      ),
      // Tight by request: the three tiles already carry their own tap-target
      // padding, so the field around them only needs a sliver.
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      // The Delivery + Points card's own surface -- the same dark translucent
      // fill and hairline border -- so the two groups on this row read as a
      // pair rather than one dark card beside a lighter wash.
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        // The Flash Sales card's radius, shared with the Delivery + Points
        // card through the same constant.
        borderRadius: BorderRadius.circular(DeliveryPointsCard.radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      // The tiles' ripples are cut to the rounded corners.
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// "Hi, Pravakar" beside the search pill.
///
/// The name is the account's own -- [ProfileStore.displayName], which prefers
/// the gateway's profile row over the session's copy and falls back to the
/// part of the email before the @. Nothing here is written down.
///
/// **The first word only.** A greeting uses a first name, and the header has
/// one row to share with the search pill: a full name would push the pill
/// narrow on the phones this ships to.
///
/// Nothing at all when signed out. There is no name to use, and "Hi, Guest"
/// is a greeting to nobody.
class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AuthStore.instance, ProfileStore.instance]),
      builder: (context, _) {
        if (!AuthStore.instance.isSignedIn) return const SizedBox.shrink();

        final full = ProfileStore.instance.displayName?.trim() ?? '';
        if (full.isEmpty) return const SizedBox.shrink();
        final first = full.split(RegExp(r'\s+')).first;

        final theme = Theme.of(context);

        return Padding(
          padding: const EdgeInsets.only(right: 10),
          child: ConstrainedBox(
            // A long name gives way to the pill rather than squeezing it.
            constraints: const BoxConstraints(maxWidth: 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The greeting leads and the name follows it, smaller: the
                // word is the same every time, and the name is the part worth
                // reading.
                Text(
                  'Hi,',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                ),
                Text(
                  first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.onPrimary.withValues(alpha: 0.85),
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({
    super.key,
    required this.hintText,
    required this.onTap,
    required this.onImageSearch,
    required this.onVoiceResult,
  });

  final String hintText;
  final VoidCallback? onTap;
  final VoidCallback? onImageSearch;
  final ValueChanged<String>? onVoiceResult;

  /// How wide the microphone and camera boxes are inside the pill.
  ///
  /// There is no gap widget between those two icons -- none, at any point --
  /// so the space between them was never spacing to remove. Both carried a
  /// 32pt square box around an 18px glyph, which leaves seven points of empty
  /// target on each side: fourteen points of dead air between the marks, and
  /// nothing in the layout naming it.
  ///
  /// 26 takes twelve of those back. Width only: the height stays 32, because
  /// in a 38pt pill the vertical is the tight dimension and it is the half of
  /// the tap target actually worth keeping. Each icon still clears four points
  /// a side.
  ///
  /// On this class rather than on [SearchHeader]: the pill is the only thing
  /// that reads it, and a static on the header is not in scope here -- an
  /// unqualified name does not reach across classes, which is what the first
  /// attempt at this got wrong.
  static const double _pillActionWidth = 26;

  @override
  Widget build(BuildContext context) {
    final onPill = Colors.black.withValues(alpha: 0.55);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: SizedBox(
          // Trimmed from 44 by request. Short for a tap target, which this
          // pill gets away with because it is the full width of the header --
          // the height is the only tight dimension, and the whole bar answers
          // the tap.
          height: 38,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(Icons.search, size: 18, color: onPill),
              const SizedBox(width: 8),
              Expanded(
                // The pill is a button, not a field -- nothing is typed here,
                // so the hint cycles freely until the shopper taps through to
                // the search screen, where it stops the moment they type.
                child: AnimatedSearchHint(
                  prefix: hintText,
                  style: TextStyle(fontSize: 13.5, color: onPill),
                ),
              ),
              // Voice first, then image: they read as a pair of ways to search
              // without typing, and the cheaper one leads.
              if (onVoiceResult != null)
                VoiceSearchButton(
                  color: onPill,
                  // 18 gives it the same 32pt box the image button now has.
                  size: 18,
                  // Narrowed to [_SearchPill._pillActionWidth]; see there for
                  // why the two sat further apart than they looked.
                  boxWidth: _pillActionWidth,
                  onResult: onVoiceResult!,
                ),
              IconButton(
                icon: Icon(Icons.center_focus_weak, size: 18, color: onPill),
                tooltip: 'Search by image',
                // Matched to the voice button so the two sit level rather than
                // one carrying a 48pt box and the other a 32pt one.
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: _pillActionWidth,
                  height: 32,
                ),
                // The half that actually moves it. See the microphone: the
                // constraints above were being overruled by Material's 48pt
                // minimum tap target, so both icons kept their old footprint
                // and the gap never closed.
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onImageSearch,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
