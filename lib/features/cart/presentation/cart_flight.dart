import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/images/app_images.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/motion/motion_curves.dart';

/// The product that flies from a card's cart button to the cart itself.
///
/// The twin of the wishlist's flight, and deliberately a separate one: the
/// wishlist throws a heart at the Saved tab, this carries the product's own
/// picture to whichever cart icon is on screen. Sharing one class would mean
/// one set of choices for two different journeys.
///
/// Every position is measured from the live render boxes at the moment of the
/// tap, so the arc is right while the page is scrolled, at any window size,
/// and after a rotation. Nothing here knows a coordinate.
class CartFlight {
  CartFlight._();

  /// Every cart icon currently mounted, newest last. A screen can carry two --
  /// the header's button and the bottom bar's tab -- and the one the product
  /// should fly to is whichever is actually laid out, preferring the one bound
  /// most recently, which is the one on the screen in front.
  static final List<_Target> _targets = [];

  static void bindTarget(GlobalKey key, VoidCallback onArrive) {
    _targets.removeWhere((t) => identical(t.key, key));
    _targets.add(_Target(key, onArrive));
  }

  static void unbindTarget(GlobalKey key) {
    _targets.removeWhere((t) => identical(t.key, key));
  }

  static Rect? _rectOf(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    // A target scrolled off the page, or one belonging to a route underneath
    // the current one, is not somewhere to throw anything.
    return rect.width > 0 && rect.height > 0 ? rect : null;
  }

  static _Target? _live() {
    for (final target in _targets.reversed) {
      if (_rectOf(target.key.currentContext) != null) return target;
    }
    return null;
  }

  /// Whether there is a cart icon on screen to fly to.
  static bool get hasTarget => _live() != null;

  /// The button the current tap came from.
  ///
  /// The card's cart button knows where it is; the screen's handler, which is
  /// what actually adds the product, does not -- it holds the page's context,
  /// and flying from the page means flying from the middle of the screen.
  /// The button lends its own context for the length of the tap.
  static BuildContext? pendingSource;

  /// Runs [action] with [source] as the place any flight leaves from.
  static Future<T> from<T>(
    BuildContext source,
    Future<T> Function() action,
  ) async {
    final previous = pendingSource;
    pendingSource = source;
    try {
      return await action();
    } finally {
      pendingSource = previous;
    }
  }

  /// Sends [imageUrl] -- the product's own picture -- from [source] to the
  /// cart.
  ///
  /// Resolves when the flight is over and the overlay has been cleared, so the
  /// caller can hold its button locked for exactly that long. No target, no
  /// overlay or an unmounted source all return at once: there is nothing to
  /// draw and nothing to wait for.
  static Future<void> launch(
    BuildContext source, {
    required bool reducedMotion,
    String? imageUrl,
  }) async {
    // The button that was tapped, where one lent its context; the caller's
    // own otherwise.
    final from = _rectOf(pendingSource) ?? _rectOf(source);
    final target = _live();
    final to = target == null ? null : _rectOf(target.key.currentContext);
    if (from == null || to == null) return;

    final overlay = Overlay.maybeOf(source, rootOverlay: true);
    if (overlay == null) return;

    final done = Completer<void>();
    late OverlayEntry entry;
    var removed = false;
    void finish() {
      if (removed) return;
      removed = true;
      entry.remove();
      if (!done.isCompleted) done.complete();
    }

    entry = OverlayEntry(
      builder: (_) => _FlyingProduct(
        from: from,
        to: to,
        imageUrl: imageUrl,
        reducedMotion: reducedMotion,
        onArrive: target!.onArrive,
        onDone: finish,
      ),
    );
    overlay.insert(entry);
    return done.future;
  }
}

class _Target {
  const _Target(this.key, this.onArrive);

  final GlobalKey key;
  final VoidCallback onArrive;
}

class _FlyingProduct extends StatefulWidget {
  const _FlyingProduct({
    required this.from,
    required this.to,
    required this.imageUrl,
    required this.reducedMotion,
    required this.onArrive,
    required this.onDone,
  });

  final Rect from;
  final Rect to;
  final String? imageUrl;
  final bool reducedMotion;
  final VoidCallback onArrive;
  final VoidCallback onDone;

  @override
  State<_FlyingProduct> createState() => _FlyingProductState();
}

class _FlyingProductState extends State<_FlyingProduct>
    with SingleTickerProviderStateMixin {
  static const _flight = Duration(milliseconds: 760);
  static const _plain = Duration(milliseconds: 260);

  /// Where the cart is told to brace itself: late enough to be nearly there,
  /// early enough that the two movements overlap.
  static const _arriveAt = 0.85;

  /// The size the picture leaves at and the size it lands at.
  static const _startSize = 56.0;
  static const _endScale = 0.3;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.reducedMotion ? _plain : _flight,
  );

  bool _announced = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_maybeAnnounce);
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  void _maybeAnnounce() {
    if (_announced || _c.value < _arriveAt) return;
    _announced = true;
    widget.onArrive();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// The top of the arc.
  ///
  /// A curve, not a loop: the rise is a fraction of the distance travelled and
  /// capped at [_maxRise], so a product thrown across the page arcs gently and
  /// one thrown a short way barely leaves the straight line. It was a flat 80
  /// above the higher end, which on a card near the cart read as the picture
  /// flying up the screen before coming back down.
  double get _apex {
    final start = widget.from.center;
    final end = widget.to.center;
    final distance = (end - start).distance;
    final rise = (distance * 0.06).clamp(10.0, _maxRise);
    // Measured from the centres the path is drawn through, so the rise is the
    // number it says it is rather than that plus half a button.
    return math.min(start.dy, end.dy) - rise;
  }

  static const _maxRise = 34.0;

  Offset _pointAt(double t) {
    final start = widget.from.center;
    final end = widget.to.center;

    if (widget.reducedMotion) return Offset.lerp(start, end, t * 0.35)!;

    final x = start.dx + (end.dx - start.dx) * t;
    final double y;
    if (t <= 0.5) {
      // Up on the quadratic ease-out, which is what makes the top float.
      y = start.dy + (_apex - start.dy) * power2Out.transform(t / 0.5);
    } else {
      // And down on its mirror, so the landing arrives rather than drifts.
      y = _apex + (end.dy - _apex) * power2In.transform((t - 0.5) / 0.5);
    }
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IgnorePointer(
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final at = _pointAt(t);
              // Spent by the time the cart has finished reacting.
              final fade = t < 0.8 ? 1.0 : 1.0 - (t - 0.8) / 0.2;
              final scale = widget.reducedMotion
                  ? 1.0
                  : 1.0 - (1 - _endScale) * t;
              final side = _startSize * scale;

              return Positioned(
                left: at.dx - side / 2,
                top: at.dy - side / 2,
                width: side,
                height: side,
                child: Opacity(
                  opacity: fade.clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: widget.reducedMotion ? 0 : 0.35 * t,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                      child: widget.imageUrl == null
                          ? Container(
                              color: theme.colorScheme.surface,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.shopping_cart,
                                size: side * 0.6,
                                color: AppColors.trustBlue,
                              ),
                            )
                          : Image(
                              image: AppImages.of(
                                widget.imageUrl!,
                                width: _startSize,
                                devicePixelRatio: MediaQuery.devicePixelRatioOf(
                                  context,
                                ),
                              ),
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Wraps a cart icon so products can be thrown at it.
///
/// Drawn around whatever icon the screen already has rather than replacing it:
/// the header's button and the bottom bar's tab keep their own appearance,
/// their own count and their own tap. This adds the anchor the flight aims at
/// and the squash-and-pop it answers with.
class CartFlightTarget extends StatefulWidget {
  const CartFlightTarget({super.key, required this.child});

  final Widget child;

  @override
  State<CartFlightTarget> createState() => _CartFlightTargetState();
}

class _CartFlightTargetState extends State<CartFlightTarget>
    with SingleTickerProviderStateMixin {
  final GlobalKey _anchor = GlobalKey();

  late final AnimationController _land = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    CartFlight.bindTarget(_anchor, _react);
  }

  void _react() {
    if (!mounted) return;
    if (MediaQuery.of(context).disableAnimations) return;
    _land.forward(from: 0);
  }

  @override
  void dispose() {
    CartFlight.unbindTarget(_anchor);
    _land.dispose();
    super.dispose();
  }

  /// Squashed, popped past its size, then settling back on to it.
  double get _scale {
    final t = _land.value;
    if (t == 0 || _land.isCompleted) return 1;
    if (t <= 0.15) return 1 - 0.18 * power2Out.transform(t / 0.15);
    if (t <= 0.45) return 0.82 + 0.36 * backOut3.transform((t - 0.15) / 0.3);
    return 1 + 0.18 * (1 - elasticOutSoft.transform((t - 0.45) / 0.55));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _land,
      builder: (context, child) =>
          Transform.scale(scale: _scale, child: child),
      child: KeyedSubtree(key: _anchor, child: widget.child),
    );
  }
}
