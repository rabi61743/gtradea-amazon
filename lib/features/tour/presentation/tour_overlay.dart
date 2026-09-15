import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_theme.dart';
import '../data/tour_step.dart';
import '../data/tour_store.dart';

/// The guided tour, drawn over whatever screen mounted it.
///
/// A dimmed sheet with a hole cut where the step's own widget is, and the
/// instruction written on the dim beside it -- a mark, a line of type, nothing
/// behind it. Deliberately not a card: a panel over the storefront hides the
/// thing being pointed at and turns a walkthrough into a stack of dialogs.
///
/// Nothing about the storefront moves. The overlay is painted on top, so the
/// header, the strip and the bar under it are the real ones the shopper will
/// use a moment later rather than pictures of them.
///
/// **It never invents a target.** Each step names a [TourAnchor]; the anchor's
/// key is resolved at paint time, and a step whose widget is not on this screen
/// -- not built yet, hidden at this width, on a page that is not open -- is
/// skipped rather than drawn against a rectangle nobody can see. That is the
/// spec's "safely skip an unavailable element", and it is also what keeps the
/// tour honest on a narrow phone where fewer things fit.
class TourOverlay extends StatefulWidget {
  const TourOverlay({super.key, required this.steps, required this.onFinished});

  /// The steps to walk, in order. Already filtered to the unseen versions by
  /// the caller -- see [TourStore.unseenFrom].
  final List<TourStep> steps;

  /// Called once, with how it ended.
  final ValueChanged<TourOutcome> onFinished;

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay> {
  int _index = 0;

  /// Whether the screen underneath has been laid out.
  ///
  /// Nothing can be measured before it. On the overlay's first build the
  /// anchors exist as elements but have no boxes yet, so every target resolves
  /// to null -- which would dim the whole screen and, worse, leave the barrier
  /// with no hole to let the shopper's touch through. So the first frame draws
  /// nothing and the one after it draws the real thing.
  bool _ready = false;

  /// Steps whose widget is not on this screen, by index.
  ///
  /// Probed for every step up front rather than discovered on the way past:
  /// the counter has to be able to say "2 of 2" on the first step instead of
  /// promising a third that will turn out to have nothing to point at.
  final _missing = <int>{};

  /// True while a probe is already booked for the next frame.
  bool _probeQueued = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _probeAll();
      setState(() => _ready = true);
      _settleOnVisible(1);
    });
  }

  /// Asks, for every step, whether it has something to point at.
  void _probeAll() {
    _missing.clear();
    for (var i = 0; i < widget.steps.length; i++) {
      final step = widget.steps[i];
      // A step that speaks for itself always has somewhere to be.
      if (step.anchor == TourAnchor.none) continue;
      if (_rectFor(step) == null) _missing.add(i);
    }
  }

  /// Re-asks after the frame, and rebuilds if the answer has changed.
  ///
  /// Probing once was not enough. On a cold start the screen underneath is
  /// still the brand loader when the overlay first lays out, so *none* of the
  /// anchors have boxes yet and every step with a target would be written off
  /// as unavailable -- which is how a five step tour announced itself as
  /// "1 of 1". The storefront arrives a frame or two later; this notices.
  ///
  /// Not a timer and not a poll: it is one callback per frame this widget
  /// builds, and it only calls setState when a step has actually appeared or
  /// gone away, so it settles the moment the page does.
  void _queueProbe() {
    if (_probeQueued) return;
    _probeQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _probeQueued = false;
      if (!mounted) return;
      final before = Set<int>.of(_missing);
      _probeAll();
      // Same answer as the last frame: nothing has appeared or gone away, so
      // there is nothing to redraw. Compared by hand -- `setEquals` lives in
      // foundation and is not in scope here, and for at most a handful of
      // indices this is the whole of it.
      if (before.length == _missing.length && before.containsAll(_missing)) {
        return;
      }
      setState(() {});
      _settleOnVisible(1);
    });
  }

  /// The steps that actually have something to point at, in order.
  List<int> get _usable => [
    for (var i = 0; i < widget.steps.length; i++)
      if (!_missing.contains(i)) i,
  ];

  /// Where this step sits in what the shopper will actually be shown.
  int get _position => _usable.indexOf(_index) + 1;
  int get _total => _usable.length;

  bool get _isLast => _index == (_usable.isEmpty ? -1 : _usable.last);

  TourStep get _step => widget.steps[_index];

  /// Moves [by] steps, stepping over anything with no target on screen.
  ///
  /// Not a timer and not a retry loop: it asks each candidate once, in the
  /// direction of travel, and stops at the first one that can be shown.
  void _settleOnVisible(int by) {
    if (!mounted) return;
    var i = _index;
    while (i >= 0 && i < widget.steps.length) {
      if (!_missing.contains(i)) {
        if (i != _index) setState(() => _index = i);
        return;
      }
      i += by == 0 ? 1 : by.sign;
    }
    // Walked off the end with nothing left to show. A tour with no visible
    // targets is not a tour, and holding a dimmed screen over the storefront
    // would be worse than never opening.
    widget.onFinished(TourOutcome.completed);
  }

  /// Where this step's widget is on screen, or null if it is not.
  Rect? _rectFor(TourStep step) {
    final key = TourAnchors.instance.keyFor(step.anchor);
    final context = key?.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final origin = box.localToGlobal(Offset.zero);
    final rect = origin & box.size;
    if (rect.width <= 0 || rect.height <= 0) return null;
    return rect;
  }

  void _next() {
    if (_isLast) {
      widget.onFinished(TourOutcome.completed);
      return;
    }
    setState(() => _index += 1);
    _settleOnVisible(1);
  }

  void _back() {
    final usable = _usable;
    final at = usable.indexOf(_index);
    if (at <= 0) return;
    setState(() => _index = usable[at - 1]);
    _settleOnVisible(-1);
  }

  void _skip() => widget.onFinished(TourOutcome.skipped);

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();
    // The page underneath can still be arriving -- a cold start shows the
    // brand loader first -- so every build books a re-check for after the
    // frame. It stops mattering as soon as the storefront has settled.
    _queueProbe();
    // Before the first layout there is nothing to measure, so there is nothing
    // honest to draw. One frame, and never a timer.
    if (!_ready) return const SizedBox.shrink();

    final step = _step;
    final rect = _rectFor(step);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // The dim, with the target cut out of it.
          //
          // It absorbs taps on the dimmed part -- a tour that vanished on a
          // stray touch would lose the shopper their place with no way back --
          // but the hole is left alone, so the control being described still
          // answers the finger. That is the point of ringing the real widget
          // rather than drawing a picture of one.
          Positioned.fill(
            child: _SpotlightBarrier(
              hole: rect,
              // Clipped to everything *except* the target, so the blur and the
              // dim stop at the edge of the spotlight. A BackdropFilter across
              // the whole screen would soften the very element the step is
              // pointing at, which is the opposite of highlighting it.
              child: ClipPath(
                clipper: _HoleClipper(rect),
                child: BackdropFilter(
                  // Enough to stop the page's own headlines competing with the
                  // instruction, and no more. At 6 the storefront went to
                  // mush; the point is a premium softening that still leaves
                  // the interface recognisable behind the step, so the shopper
                  // can see what they are about to be shown.
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: CustomPaint(
                    // Sized explicitly. A CustomPaint with no child and no size
                    // collapses to zero under loose constraints and paints
                    // nothing -- which is how the scrim came to be silently
                    // absent for several builds while the ring around the
                    // target still drew and made the overlay look deliberate.
                    size: Size.infinite,
                    painter: _SpotlightPainter(
                      hole: rect,
                      // Lighter than it was, because the blur is doing the work
                      // now. At 0.74 with no blur the page was a dark smear;
                      // blurred, a softer wash keeps the storefront readable as
                      // context while the sharp type sits clearly on top.
                      colour: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The ring around the real widget, so the thing being described is
          // unmistakably the thing on the page.
          //
          // White rather than the brand teal: the ring is drawn on the dim, and
          // the reference's own highlight reads as light falling on the element
          // rather than as a coloured border added to it.
          if (rect != null)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              left: rect.left - 4,
              top: rect.top - 4,
              width: rect.width + 8,
              height: rect.height + 8,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.85),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          _StepCaption(
            step: step,
            position: _position,
            total: _total,
            isLast: _isLast,
            canGoBack: _usable.indexOf(_index) > 0,
            target: rect,
            onNext: _next,
            onBack: _back,
            onSkip: _skip,
          ),
        ],
      ),
    );
  }
}

/// Everything but the spotlight, as a clip.
///
/// What keeps the highlighted element sharp: the blur and the dim are drawn
/// inside this, so neither reaches the hole. Null leaves the whole screen
/// clipped in -- the welcome step, which has nothing to point at.
class _HoleClipper extends CustomClipper<Path> {
  const _HoleClipper(this.hole);

  final Rect? hole;

  @override
  Path getClip(Size size) {
    final screen = Path()..addRect(Offset.zero & size);
    final cut = hole;
    if (cut == null) return screen;
    return Path.combine(
      PathOperation.difference,
      screen,
      Path()..addRRect(
        RRect.fromRectAndRadius(
          cut.inflate(4),
          const Radius.circular(AppTheme.radiusCard),
        ),
      ),
    );
  }

  @override
  bool shouldReclip(_HoleClipper old) => old.hole != hole;
}

/// Swallows pointers on the dimmed area, and only there.
///
/// A plain opaque `GestureDetector` over the whole screen was the first
/// attempt, and it stopped the feed underneath from scrolling at all -- the
/// overlay ate every drag before the list saw it. This lets the hole through,
/// which is both what the spec asks for and what makes the highlight mean
/// anything.
class _SpotlightBarrier extends SingleChildRenderObjectWidget {
  const _SpotlightBarrier({required this.hole, required super.child});

  final Rect? hole;

  @override
  _RenderSpotlightBarrier createRenderObject(BuildContext context) =>
      _RenderSpotlightBarrier(hole);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSpotlightBarrier renderObject,
  ) => renderObject.hole = hole;
}

class _RenderSpotlightBarrier extends RenderProxyBox {
  _RenderSpotlightBarrier(this._hole);

  Rect? _hole;

  Rect? get hole => _hole;

  set hole(Rect? value) {
    if (_hole == value) return;
    _hole = value;
    markNeedsPaint();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final cut = _hole;
    // Inside the spotlight: not ours. The widget underneath -- the real search
    // bar, the real strip -- takes the touch.
    if (cut != null && cut.inflate(4).contains(localToGlobal(position))) {
      return false;
    }
    // Anywhere else on the dim: absorbed, so a stray tap cannot scroll the
    // page out from under the step that is describing it.
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

/// The dim, with a rounded hole where the target is.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.hole, required this.colour});

  final Rect? hole;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Offset.zero & size;
    final paint = Paint()..color = colour;

    if (hole == null) {
      // A step with nothing to point at -- the welcome -- dims the whole
      // screen rather than cutting a hole in nothing.
      canvas.drawRect(screen, paint);
      return;
    }

    final cut = RRect.fromRectAndRadius(
      hole!.inflate(4),
      const Radius.circular(AppTheme.radiusCard),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(screen),
        Path()..addRRect(cut),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.colour != colour;
}

/// The mark that suits an anchor, when a step does not name its own.
IconData _iconFor(TourAnchor anchor) => switch (anchor) {
  TourAnchor.none => Icons.waving_hand_outlined,
  TourAnchor.header => Icons.storefront_outlined,
  TourAnchor.search => Icons.search,
  TourAnchor.categories => Icons.grid_view_outlined,
  TourAnchor.cart => Icons.shopping_cart_outlined,
  TourAnchor.account => Icons.receipt_long_outlined,
  TourAnchor.wishlist => Icons.favorite_border,
  TourAnchor.newForYou => Icons.auto_awesome_outlined,
  TourAnchor.messages => Icons.chat_bubble_outline,
  TourAnchor.orders => Icons.local_shipping_outlined,
  TourAnchor.coins => Icons.monetization_on_outlined,
};

/// What the step says, written straight onto the dim.
///
/// Deliberately not a card. A white sheet over the storefront hides the very
/// thing the step is pointing at and turns a guided tour into a stack of
/// dialogs; the reference puts its words on the scrim itself -- a mark, a line
/// of type, nothing behind it -- so the app stays visible underneath and the
/// eye goes to the lit element rather than to a panel.
///
/// Everything here is therefore chrome-less: no surface, no border, no
/// elevation. The only weight it carries is a soft shadow under the type, which
/// is what keeps white legible over a pale part of the page.
class _StepCaption extends StatelessWidget {
  const _StepCaption({
    required this.step,
    required this.position,
    required this.total,
    required this.isLast,
    required this.canGoBack,
    required this.target,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final TourStep step;
  final int position;
  final int total;
  final bool isLast;
  final bool canGoBack;
  final Rect? target;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  /// The type is white on a dark scrim, so it is shadowed rather than boxed.
  static const _ink = Colors.white;
  static const _shadow = [
    Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    // Which side of the target has the room, rather than a fixed rule about
    // halves. A step whose element sits just past the midpoint still has most
    // of the screen below it, and putting the words above it there pushed them
    // up onto the header; measuring both gaps puts them where the space is.
    final padding = MediaQuery.of(context).padding;
    final spaceBelow = target == null
        ? size.height
        : size.height - target!.bottom - padding.bottom;
    final spaceAbove = target == null ? 0.0 : target!.top - padding.top;
    final below = target == null || spaceBelow >= spaceAbove;

    // A readable measure on a tablet or a desktop window rather than a line of
    // type running the full width of the glass.
    final width = size.width < 520 ? size.width - 48 : 420.0;

    final gap = target == null ? 0.0 : 28.0;

    // Held clear of the very edges, so a caption beside a target near the top
    // or the bottom of the glass cannot run off it.
    const margin = 16.0;
    final top = target == null
        ? size.height * 0.42
        : (target!.bottom + gap).clamp(padding.top + margin, size.height);
    final bottom = target == null
        ? 0.0
        : (size.height - target!.top + gap).clamp(
            padding.bottom + margin,
            size.height,
          );

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      left: (size.width - width) / 2,
      top: below ? top : null,
      bottom: below ? null : bottom,
      width: width,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Column(
          key: ValueKey(step.title),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              step.icon ?? _iconFor(step.anchor),
              size: 34,
              color: _ink,
              shadows: _shadow,
            ),
            const SizedBox(height: 10),
            Text(
              step.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: _ink,
                fontWeight: FontWeight.w700,
                height: 1.2,
                shadows: _shadow,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              step.body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _ink.withValues(alpha: 0.88),
                height: 1.35,
                shadows: _shadow,
              ),
            ),
            const SizedBox(height: 14),
            // Compact and unobtrusive, as the reference keeps them: plain words
            // on the dim, with the one that carries the tour forward given a
            // little weight so the thumb knows where to go.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CaptionAction(label: 'Skip', onTap: onSkip, quiet: true),
                const Spacer(),
                Text(
                  '$position of $total',
                  key: const ValueKey('tour-progress'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _ink.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                    shadows: _shadow,
                  ),
                ),
                const Spacer(),
                if (canGoBack) ...[
                  _CaptionAction(label: 'Back', onTap: onBack, quiet: true),
                  const SizedBox(width: 14),
                ],
                _CaptionAction(
                  label: isLast ? 'Get Started' : 'Next',
                  onTap: onNext,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One word on the dim, with a tap target big enough for a thumb.
class _CaptionAction extends StatelessWidget {
  const _CaptionAction({
    required this.label,
    required this.onTap,
    this.quiet = false,
  });

  final String label;
  final VoidCallback onTap;

  /// Skip and Back are said quietly; the way forward is not.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // The words are small; the target is not.
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: quiet ? Colors.white.withValues(alpha: 0.75) : Colors.white,
            fontWeight: quiet ? FontWeight.w600 : FontWeight.w800,
            shadows: _StepCaption._shadow,
          ),
        ),
      ),
    );
  }
}
