import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../../core/images/app_images.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';

class BannerItem {
  const BannerItem({
    required this.headline,
    required this.caption,
    required this.cta,
    required this.tint,
    this.eyebrow = '',
    this.imageUrl,
    this.gradient,
    this.icon,
    this.onTap,
  });

  /// A short line above the headline -- the campaign or department. Optional,
  /// and the server does not send one, so it is only the fallbacks that use it.
  final String eyebrow;

  final String headline;
  final String caption;
  final String cta;
  final Color tint;
  final String? imageUrl;

  /// Two colours behind the card. Falls back to a wash of [tint] when absent,
  /// which is what a server banner gets.
  final List<Color>? gradient;

  /// A large, faint glyph for a card with no photograph.
  final IconData? icon;

  /// Where the banner goes. Null when the campaign points somewhere this app
  /// has no screen for -- the banner still shows, it just stops pretending to
  /// be a button.
  final VoidCallback? onTap;

  /// True when there is nothing to write over the artwork.
  ///
  /// Plenty of the real banners are artwork with the words already baked in and
  /// send no title at all. Those get no scrim: darkening a picture to improve
  /// the contrast of text that is not there just makes the picture worse.
  bool get isArtworkOnly => headline.isEmpty && caption.isEmpty;
}

/// Full-width hero carousel that advances on its own.
///
/// Auto-advance yields to a finger and then takes over again: it stops the
/// moment the customer touches the carousel -- a banner that keeps moving under
/// a finger is how people tap the wrong offer -- and starts again [_resumeAfter]
/// once they have finished, on whichever slide they left it on. It never gets
/// stuck on a slide because somebody swiped to it.
///
/// It stays still, permanently, only when the platform asks for reduced motion,
/// which is what `MediaQuery.disableAnimations` reports.
class HeroBanner extends StatefulWidget {
  const HeroBanner({
    super.key,
    required this.items,
    this.interval = const Duration(seconds: 5),
  });

  final List<BannerItem> items;
  final Duration interval;

  /// The card's height, from the width available to it.
  ///
  /// A ratio rather than a fixed height, so the banner keeps its proportions
  /// from a 320pt phone to a desktop window instead of becoming a letterbox on
  /// one and a wall on the other. Clamped at both ends: below the floor the
  /// headline and the button stop fitting, and above the ceiling the banner
  /// pushes the entire catalogue off the first screen.
  static double heightFor(double width) => (width * 0.46).clamp(158.0, 260.0);

  /// Past this the card stops growing and centres. A banner three feet wide is
  /// not more engaging, only harder to read across.
  static const maxCardWidth = 900.0;

  /// How much of the page the card takes, by request.
  ///
  /// A share rather than the fixed 16pt inset it used to carry: the margin is
  /// then the same fraction of a phone, a tablet and a desktop window, and the
  /// card matches the other cards down this page, which are measured the same
  /// way.
  static const widthFactor = 0.97;

  /// The inset on each side that leaves the card [widthFactor] of [width].
  static double insetFor(double width) => width * (1 - widthFactor) / 2;

  /// Whether the carousel is allowed to run its clock at all.
  ///
  /// True in the app, always. It exists for the suite: the clock that advances
  /// the slides is also what fills the progress bar, so it schedules a frame
  /// for as long as the carousel is on screen -- and a tree with a frame
  /// always pending is a tree `pumpAndSettle` waits on forever. Every test
  /// that pumps a page with a hero on it would hang.
  ///
  /// So `test/flutter_test_config.dart` switches it off for the whole suite,
  /// and the tests that are about the carousel switch it back on for
  /// themselves. Nothing about the timing is mocked -- when it is on, it is
  /// the real clock at the real interval.
  @visibleForTesting
  static bool autoplayEnabled = true;

  /// The progress bar, so a test can measure the fill rather than the pixels.
  static const progressKey = ValueKey('hero-autoplay-progress');

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner>
    with SingleTickerProviderStateMixin {
  final _controller = PageController();

  /// The autoplay clock **and** what the progress bar is drawn from.
  ///
  /// One thing, deliberately. A bar driven by a second timer beside the
  /// carousel's own is a bar that drifts: it would fill at its own pace, reset
  /// on its own schedule, and disagree with the slide underneath it the first
  /// time a frame was dropped or a page took longer to settle. Here the
  /// carousel advances *because* this controller finished, so the bar reaching
  /// its end and the slide changing are the same event.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: widget.interval,
  )..addStatusListener(_onClock);

  /// Whether the carousel is advancing on its own right now.
  bool _autoplaying = false;

  /// The wait between a shopper letting go and the carousel picking up again.
  ///
  /// Long enough to read the slide they chose, short enough that the carousel
  /// is plainly still running rather than parked.
  static const _resumeAfter = Duration(milliseconds: 2500);

  /// Pending resumption, if a shopper has just been at it. Held so a second
  /// swipe restarts the wait rather than stacking a second timer on it.
  Timer? _resume;

  /// True while the platform is asking for less movement. Read from
  /// [MediaQuery] in [didChangeDependencies], and the one case where autoplay
  /// does not come back at all.
  bool _reduceMotion = false;

  int _index = 0;

  /// Drives the parallax. Kept separate from [_index] because it updates on
  /// every frame of a drag, not once per settled page.
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  /// The clock reaching its end is what turns the page.
  void _onClock(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!mounted || !_controller.hasClients || widget.items.length < 2) return;

    final next = (_index + 1) % widget.items.length;
    _controller.animateToPage(
      next,
      // A little longer when it is the loop back to the first: that one travels
      // the whole set, and at the ordinary duration it reads as a rewind rather
      // than as a return.
      duration: Duration(milliseconds: next == 0 ? 700 : 520),
      curve: Curves.easeOutCubic,
    );
    // Restarted here rather than waiting for the page to settle, so the bar
    // begins the next slide's fill as the slide begins moving.
    _clock.forward(from: 0);
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final page = _controller.page;
    if (page != null && page != _page) setState(() => _page = page);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here rather than in initState: MediaQuery is not available yet at
    // initState, and the answer can change while the app is running.
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    if (!_canAutoplay) {
      _stop();
    } else if (_resume?.isActive != true) {
      // Not while a shopper's own pause is still running: a rebuild in the
      // middle of it would take the slide out from under them, which is the
      // whole thing the pause is for.
      _start();
    }
    _warm();
  }

  /// Fetches the artwork for the banner after this one.
  ///
  /// One ahead, not all of them. The campaign PNGs average 2.4 MB, so warming
  /// the whole set would pull 28 MB before a shopper had looked at anything --
  /// and a page that is scrolled past in two seconds does not need twelve
  /// pictures. One ahead is what a swipe can reach before it lands.
  ///
  /// [precacheImage] resolves through the same [AppImages] provider the card
  /// uses, so this warms the disk cache and the memory cache together and the
  /// card finds it already there rather than starting a second fetch.
  void _warm() {
    final width = _lastWidth;
    if (width == null) return;

    final dpr = MediaQuery.devicePixelRatioOf(context);
    // The current one as well as the next: on the first frame nothing has been
    // drawn yet, and this is the moment the first banner is worth having.
    for (final offset in const [0, 1]) {
      final i = _index + offset;
      if (i >= widget.items.length) break;
      final url = widget.items[i].imageUrl;
      if (url == null || url.isEmpty) continue;
      precacheImage(
        AppImages.of(url, width: width, devicePixelRatio: dpr),
        context,
        // A banner that will not load is not worth an error: the gradient
        // underneath is the failure state, and the card will report it again
        // when it tries for itself.
        onError: (_, _) {},
      );
    }
  }

  /// The width the cards were last laid out at, so warming asks for the same
  /// variant the card will. A different width would be a second download.
  double? _lastWidth;

  @override
  void didUpdateWidget(HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different set arrived -- the real banners replacing the fallbacks, say.
    // Counting on towards an index the new list may not have would jump to a
    // blank page.
    if (oldWidget.items.length != widget.items.length) {
      _index = 0;
      _page = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
      if (_autoplaying) _clock.forward(from: 0);
    }
    // The bar's fill is the carousel's own interval, whatever it is set to.
    if (oldWidget.interval != widget.interval) {
      _clock.duration = widget.interval;
      if (_autoplaying) _clock.forward(from: _clock.value);
    }
  }

  void _start() {
    if (_autoplaying || !_canAutoplay) return;
    setState(() => _autoplaying = true);
    _clock.forward(from: _clock.value);
  }

  void _stop() {
    _resume?.cancel();
    _clock.stop();
    if (_autoplaying) setState(() => _autoplaying = false);
  }

  /// Whether the carousel is allowed to run at all.
  bool get _canAutoplay =>
      HeroBanner.autoplayEnabled && !_reduceMotion && widget.items.length > 1;

  /// A finger is on it: stop, and forget any pending resumption -- the wait
  /// starts again when they let go, not from where it was.
  void _pause() {
    _resume?.cancel();
    _clock.stop();
    if (_autoplaying) setState(() => _autoplaying = false);
  }

  /// They have let go. Pick up again after a beat, on whatever slide they left
  /// it on.
  void _resumeSoon() {
    if (!_canAutoplay || _autoplaying) return;
    _resume?.cancel();
    _resume = Timer(_resumeAfter, () {
      if (mounted) _start();
    });
  }

  @override
  void dispose() {
    _resume?.cancel();
    _clock.dispose();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = HeroBanner.heightFor(width);
        // Recorded for _warm, which runs outside layout and would otherwise
        // have to guess at the width -- and a guess would warm a variant the
        // card then does not ask for, making it a wasted download rather than
        // a saved one.
        if (_lastWidth != width) {
          _lastWidth = width;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _warm();
          });
        }

        // The card's own box, which the bar is laid over: the same share of
        // the width, the same ceiling, and centred the same way -- so the bar
        // sits inside the card rather than beside it on a wide window.
        final cardWidth = width > HeroBanner.maxCardWidth
            ? HeroBanner.maxCardWidth
            : width;
        return Column(
          children: [
            SizedBox(
              height: height,
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      // A finger on the carousel pauses it; letting go starts
                      // the wait. Both are needed: the first alone is what left
                      // it stuck on whatever slide somebody swiped to.
                      if (notification is UserScrollNotification) {
                        if (notification.direction != ScrollDirection.idle) {
                          _pause();
                        } else {
                          _resumeSoon();
                        }
                      } else if (notification is ScrollEndNotification) {
                        _resumeSoon();
                      }
                      return false;
                    },
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: widget.items.length,
                      onPageChanged: (i) {
                        setState(() {
                          _index = i;
                          // The new slide starts its turn from nothing, so the
                          // pill measures this slide rather than carrying the
                          // last one's progress into it.
                          if (!_autoplaying) _clock.value = 0;
                        });
                        // Warm the one after this, so a swipe lands on artwork
                        // that is already there.
                        _warm();
                        _resumeSoon();
                      },
                      itemBuilder: (context, i) => _BannerCard(
                        item: widget.items[i],
                        sideInset: HeroBanner.insetFor(cardWidth),
                        // How far this card is from resting in the middle, -1 to 1.
                        // The card uses it to drift its artwork and settle its
                        // words, which is what makes the swipe feel like depth
                        // rather than a slide show.
                        offset: (i - _page).clamp(-1.0, 1.0),
                      ),
                    ),
                  ),
                  // A short pill along the foot of the card, centred on it and
                  // inside its rounded corner. Nothing sits below the carousel
                  // any more: this is the whole indicator.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Center(
                      child: _CarouselProgress(
                        key: HeroBanner.progressKey,
                        clock: _clock,
                        index: _index,
                        count: widget.items.length,
                        running: _autoplaying,
                      ),
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

/// Where the carousel has got to, as a small pill on the card itself.
///
/// The whole indicator, and the only one: the rail of dots that used to sit
/// under the carousel is gone, and with it the gap it needed. This is 52 by 4,
/// with rounded ends, centred along the foot of the artwork -- part of the
/// picture rather than a control parked beneath it.
///
/// **What it fills from.** Two things at once, and both are the carousel's own:
/// which slide is showing, and how far that slide is through its turn. The
/// second comes straight from the [AnimationController] whose completion turns
/// the page -- there is no second timer to drift against, so the pill is full
/// at the instant the last slide ends. A shopper who swipes moves the first
/// term immediately, which is what makes the pill answer a swipe rather than
/// lag behind it.
///
/// The fill is animated rather than set, so a swipe slides it along instead of
/// snapping, and so it keeps moving when the clock stops.
class _CarouselProgress extends StatelessWidget {
  const _CarouselProgress({
    super.key,
    required this.clock,
    required this.index,
    required this.count,
    required this.running,
  });

  final Animation<double> clock;

  /// Which slide is showing, and how many there are.
  final int index;
  final int count;

  /// Whether the carousel is advancing on its own. The pill draws the same
  /// either way -- the clock holds its value when it stops, so a paused
  /// carousel simply stops creeping -- and this is here for the one case that
  /// has no progress to show: a single banner, which is already at its end.
  final bool running;

  static const double _width = 52;
  static const double _height = 4;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_height),
        child: SizedBox(
          width: _width,
          height: _height,
          // A neutral under it rather than a tint of the artwork: the track has
          // to read on a dark photograph and on a bright one alike.
          child: ColoredBox(
            color: Colors.white.withValues(alpha: 0.45),
            child: AnimatedBuilder(
              animation: clock,
              builder: (context, _) {
                // One banner is a carousel with nowhere to go: a full pill,
                // rather than an empty one that will never fill.
                if (count <= 1) return const _PillFill();

                // The slide, plus how far through it the clock has got. The
                // clock holds where it stopped, so a pause holds the pill
                // there too -- and a swipe zeroes it, so the new slide starts
                // its own turn rather than inheriting the last one's.
                final within = clock.value.clamp(0.0, 1.0);
                final progress = ((index + within) / count).clamp(0.0, 1.0);

                return Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TweenAnimationBuilder<double>(
                    // Short: long enough that a swipe slides rather than jumps,
                    // short enough that it has caught up before the eye moves
                    // back to the picture.
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                    tween: Tween<double>(end: progress),
                    builder: (context, value, _) => FractionallySizedBox(
                      widthFactor: value,
                      // Both factors. The Align hands its child loose
                      // constraints, so a fill with no height of its own takes
                      // the smallest it is allowed -- which is none, and a
                      // pill that paints nothing at all.
                      heightFactor: 1,
                      child: const ColoredBox(color: AppColors.commerceOrange),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The pill filled end to end, for a carousel with one slide in it.
class _PillFill extends StatelessWidget {
  const _PillFill();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: AppColors.commerceOrange);
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.item, this.offset = 0, this.sideInset = 16});

  /// The margin on each side, which is what makes the card its share of the
  /// page. Passed in rather than fixed here: the parent is the one that knows
  /// how wide the page is.
  final double sideInset;

  final BannerItem item;

  /// -1 when this card is a full page to the left, 0 when it is resting, 1 when
  /// it is a page to the right.
  final double offset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = item.imageUrl;
    final hasImage = url != null && url.isNotEmpty;
    final settled = 1 - offset.abs();

    final colours =
        item.gradient ??
        [item.tint.withValues(alpha: 0.96), item.tint.withValues(alpha: 0.62)];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: HeroBanner.maxCardWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: sideInset),
          child: Semantics(
            button: item.onTap != null,
            label: [
              item.eyebrow,
              item.headline,
              item.caption,
            ].where((s) => s.isNotEmpty).join('. '),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard + 4),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: item.onTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: colours,
                        ),
                      ),
                    ),
                    if (hasImage)
                      _Artwork(url: url, offset: offset)
                    else if (item.icon != null)
                      Positioned(
                        right: -18,
                        bottom: -22,
                        child: Icon(
                          item.icon,
                          size: 168,
                          color: Colors.white.withValues(alpha: 0.13),
                        ),
                      ),
                    // Only where words have to be read over the picture.
                    if (hasImage && !item.isArtworkOnly) const _Scrim(),
                    _Copy(item: item, settled: settled, theme: theme),
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

/// The photograph, drifting slightly as the page turns.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.offset});

  final String url;
  final double offset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final width = constraints.maxWidth;

        return Transform.translate(
          // A fraction of the page's own travel, so the picture lags the card.
          // Small on purpose: enough to read as depth, not enough to notice as
          // an effect.
          offset: Offset(offset * width * 0.12, 0),
          child: Transform.scale(
            // Scaled up by more than the drift, so the edges never pull in and
            // expose the gradient behind.
            scale: 1.18,
            // Through the disk cache. The campaign artwork is the heaviest
            // thing the app fetches by a wide margin -- the twelve live banners
            // total 28.5 MB of PNG, averaging 2.4 MB each -- and until now
            // every one of them was downloaded again on every cold start. The
            // host serves static files and ignores resize parameters, so
            // nothing here can make the first fetch smaller; caching it means
            // there is only ever one.
            child: Image(
              image: AppImages.of(
                url,
                width: width.isFinite && width > 0 ? width : null,
                devicePixelRatio: dpr,
              ),
              fit: BoxFit.cover,
              frameBuilder: (context, child, frame, wasSync) {
                if (wasSync) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 260),
                  child: child,
                );
              },
              // The gradient underneath is the loading and failure state, so
              // both fall through to it rather than to a grey box or a broken
              // image glyph.
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const SizedBox.shrink(),
              errorBuilder: (context, error, stack) => const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}

/// Darkens the left of the picture so white text stays legible on it.
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          // Weighted to the left, where the words are, and clearing by the
          // middle so the artwork is still the artwork.
          stops: const [0, 0.55, 1],
          colors: [
            Colors.black.withValues(alpha: 0.62),
            Colors.black.withValues(alpha: 0.28),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

/// Eyebrow, headline, caption and the button, in that order of weight.
class _Copy extends StatelessWidget {
  const _Copy({required this.item, required this.settled, required this.theme});

  final BannerItem item;
  final double settled;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    // Rises and fades into place as the card settles. Applied to the words
    // only -- the button stays put, because a control that is still arriving is
    // a control people mis-tap.
    final lift = (1 - settled) * 14;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          // Two-thirds, so the words never run over the middle of the picture
          // however long the campaign headline is.
          widthFactor: 0.68,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Opacity(
                  opacity: settled.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, lift),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.eyebrow.isNotEmpty) ...[
                          Text(
                            item.eyebrow.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        // Skipped rather than rendered blank: a banner whose
                        // artwork already carries the words sends no title, and
                        // an empty Text still takes up a line.
                        if (item.headline.isNotEmpty)
                          Text(
                            item.headline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: AppColors.onPrimary,
                              fontWeight: FontWeight.w800,
                              height: 1.12,
                              shadows: const [
                                Shadow(blurRadius: 8, color: Colors.black26),
                              ],
                            ),
                          ),
                        if (item.caption.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            item.caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.92),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (item.cta.isNotEmpty) ...[
                const SizedBox(height: 12),
                _CtaChip(label: item.cta, tint: item.tint),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CtaChip extends StatelessWidget {
  const _CtaChip({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            color: Colors.black26,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: tint, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_forward_rounded, size: 16, color: tint),
          ],
        ),
      ),
    );
  }
}

/// What stands in the banner's place while the first set is being fetched.
///
/// Exactly the size the banner will be, which is the whole point: a smaller
/// placeholder that then grows shifts the entire page under the reader the
/// moment it arrives.
class HeroBannerSkeleton extends StatefulWidget {
  const HeroBannerSkeleton({super.key});

  @override
  State<HeroBannerSkeleton> createState() => _HeroBannerSkeletonState();
}

class _HeroBannerSkeletonState extends State<HeroBannerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A pulsing placeholder is exactly the kind of motion reduced-motion is
    // asking about, so it holds still instead.
    if (MediaQuery.of(context).disableAnimations) {
      _shimmer.stop();
      _shimmer.value = 0.5;
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            SizedBox(
              height: HeroBanner.heightFor(constraints.maxWidth),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: HeroBanner.maxCardWidth,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: HeroBanner.insetFor(
                        constraints.maxWidth > HeroBanner.maxCardWidth
                            ? HeroBanner.maxCardWidth
                            : constraints.maxWidth,
                      ),
                    ),
                    child: AnimatedBuilder(
                      animation: _shimmer,
                      builder: (context, _) => DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusCard + 4,
                          ),
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.45 + _shimmer.value * 0.35),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Nothing below the card. The indicator lives inside the carousel
            // now, so there is no rail to reserve space for -- and reserving
            // some would put back the gap this change removed.
          ],
        );
      },
    );
  }
}
