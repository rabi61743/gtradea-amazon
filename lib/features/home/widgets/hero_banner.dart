import 'dart:async';

import 'package:flutter/material.dart';

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

/// Full-width hero carousel that advances on its own, with indicators.
///
/// Auto-advance stops the moment the customer touches it and does not resume:
/// a banner that keeps moving under a finger is how people tap the wrong offer.
/// It also stays still when the platform asks for reduced motion, which is what
/// `MediaQuery.disableAnimations` reports.
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

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  final _controller = PageController();
  Timer? _timer;
  int _index = 0;
  bool _userTookOver = false;

  /// Drives the parallax. Kept separate from [_index] because it updates on
  /// every frame of a drag, not once per settled page.
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
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
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion || _userTookOver || widget.items.length < 2) {
      _stop();
    } else {
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
    }
  }

  void _start() {
    _timer ??= Timer.periodic(widget.interval, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % widget.items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Jumps to a banner the shopper picked off the indicator.
  ///
  /// Counts as taking over, exactly as a swipe does: someone who has said which
  /// banner they want should not have it slide away from under them three
  /// seconds later. A tap is not a UserScrollNotification, so the listener on
  /// the PageView never sees this one.
  void _goTo(int index) {
    if (!_controller.hasClients || index == _index) return;
    _userTookOver = true;
    _stop();
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _stop();
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

        return Column(
          children: [
            SizedBox(
              height: height,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is UserScrollNotification) {
                    _userTookOver = true;
                    _stop();
                  }
                  return false;
                },
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.items.length,
                  onPageChanged: (i) {
                    setState(() => _index = i);
                    // Warm the one after this, so a swipe lands on artwork
                    // that is already there.
                    _warm();
                  },
                  itemBuilder: (context, i) => _BannerCard(
                    item: widget.items[i],
                    // How far this card is from resting in the middle, -1 to 1.
                    // The card uses it to drift its artwork and settle its
                    // words, which is what makes the swipe feel like depth
                    // rather than a slide show.
                    offset: (i - _page).clamp(-1.0, 1.0),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _Indicator(
              count: widget.items.length,
              index: _index,
              onSelected: _goTo,
            ),
          ],
        );
      },
    );
  }
}

/// Where you are in the carousel, and how to get somewhere else.
///
/// A rail of dots that slides to keep the current one centred, rather than a
/// row of twelve. Twelve dots is a line of specks nobody can count or aim at,
/// and the static "2 / 12" that replaced them told you where you were but let
/// you do nothing about it.
///
/// Three jobs at once:
///
///   * **position** -- the active dot is a wide pill, and the count beside it
///     says which of how many, because a windowed rail cannot show that a
///     twelfth exists.
///   * **progress** -- the dots behind the current one are tinted, so the rail
///     reads left-to-right as ground covered rather than as an undifferentiated
///     row.
///   * **control** -- every dot is a button, and the rail can be swiped.
class _Indicator extends StatefulWidget {
  const _Indicator({
    required this.count,
    required this.index,
    required this.onSelected,
  });

  final int count;
  final int index;
  final ValueChanged<int> onSelected;

  /// Past this the rail scrolls rather than showing everything at once.
  static const maxVisible = 7;

  /// Taller than the dots it draws, because each one is a tap target and an
  /// 8pt circle is far under any sane one.
  static const railHeight = 22.0;

  static const _dot = 8.0;
  static const _pill = 26.0;
  static const _gap = 6.0;

  @override
  State<_Indicator> createState() => _IndicatorState();
}

class _IndicatorState extends State<_Indicator> {
  /// How far the rail must slide to keep the active dot in the middle.
  double _offsetFor(double viewport) {
    const step = _Indicator._dot + _Indicator._gap;
    // Everything before the active one, plus half the pill itself.
    final centreOfActive = widget.index * step + _Indicator._pill / 2;
    final full = (widget.count - 1) * step + _Indicator._pill;
    if (full <= viewport) return 0;
    // Clamped so the ends sit flush rather than leaving a gap at either edge.
    return (centreOfActive - viewport / 2).clamp(0.0, full - viewport);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.count < 2) return const SizedBox.shrink();

    const step = _Indicator._dot + _Indicator._gap;
    final full = (widget.count - 1) * step + _Indicator._pill;
    final viewport = widget.count > _Indicator.maxVisible
        ? (_Indicator.maxVisible - 1) * step + _Indicator._pill
        : full;

    return Semantics(
      // One phrase for the whole rail. A screen reader announcing twelve
      // unlabelled dots is worse than no indicator at all -- and this is now
      // the only place the position is said in words, since the "2/12" caption
      // that used to sit beside the dots has gone. Removing it from the screen
      // is a look; removing it from here would take the position away from
      // anyone who cannot see the dots at all.
      label: 'Banner ${widget.index + 1} of ${widget.count}',
      container: true,
      child: Center(
        child: SizedBox(
          width: viewport,
          height: _Indicator.railHeight,
          child: ClipRect(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: _offsetFor(viewport)),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              builder: (context, offset, child) =>
                  Transform.translate(offset: Offset(-offset, 0), child: child),
              // The rail is wider than the window it slides behind -- that is
              // the point of it -- so it has to be let out of the SizedBox's
              // width. Without this the Row is squeezed to the viewport and
              // reports an overflow instead of scrolling.
              child: OverflowBox(
                maxWidth: double.infinity,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < widget.count; i++)
                      _Dot(
                        active: i == widget.index,
                        // Everything up to here reads as ground covered, so
                        // the rail is a progress bar as well as a position.
                        seen: i < widget.index,
                        theme: theme,
                        label: 'Go to banner ${i + 1}',
                        onTap: () => widget.onSelected(i),
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

/// One dot: a tap target, and a mark of how far along the set it sits.
class _Dot extends StatelessWidget {
  const _Dot({
    required this.active,
    required this.seen,
    required this.theme,
    required this.label,
    required this.onTap,
  });

  final bool active;

  /// Behind the current position. Tinted rather than grey, so the rail reads
  /// left-to-right as progress instead of as an undifferentiated row.
  final bool seen;

  final ThemeData theme;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = active ? _Indicator._pill : _Indicator._dot;
    final colour = active
        ? theme.colorScheme.primary
        : seen
        ? theme.colorScheme.primary.withValues(alpha: 0.45)
        : theme.colorScheme.outlineVariant;

    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        // Opaque, and taller than the dot it draws: an 8pt circle is far under
        // any sane tap target, so the hit area is the full height of the rail
        // with the dot centred in it.
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: _Indicator.railHeight,
          width: width + _Indicator._gap,
          child: Center(
            child: AnimatedContainer(
              // Width and colour both animate, so moving between banners is a
              // pill sliding along the rail rather than one dot blinking off
              // and another on.
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              width: width,
              height: _Indicator._dot,
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.item, this.offset = 0});

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
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
            // The same gap and rail height the indicator occupies, so nothing
            // below moves when the real banners replace this. The rail is
            // taller than the dots it draws because each one is a tap target.
            const SizedBox(height: 10),
            const SizedBox(height: _Indicator.railHeight),
          ],
        );
      },
    );
  }
}
