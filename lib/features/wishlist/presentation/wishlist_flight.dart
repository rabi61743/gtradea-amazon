import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/motion/motion_curves.dart';

/// The heart that flies from a product card to the wishlist destination.
///
/// The destination is whatever widget last called [bindTarget] -- in this app
/// the Saved tab of the bottom bar, which is where the real wishlist count
/// already lives. Nothing here knows a coordinate: both ends are measured
/// from the live render boxes at the moment of the tap, so the arc is right
/// while the page is scrolled, on any screen size, and after a rotation.
///
/// If no destination is on screen -- a product grid pushed over the bar, say
/// -- there is simply no flight. The card's own heart still pops, and the
/// save still happens: the animation is never what performs the action.
class WishlistFlight {
  WishlistFlight._();

  static GlobalKey? _targetKey;
  static VoidCallback? _onArrive;

  /// Registers the wishlist icon as the place hearts fly to.
  ///
  /// [onArrive] is called just before the heart lands, which is what makes the
  /// destination react while the heart is still in the air rather than after
  /// it has gone.
  static void bindTarget(GlobalKey key, VoidCallback onArrive) {
    _targetKey = key;
    _onArrive = onArrive;
  }

  /// Lets go of a destination, if it is still the registered one. A screen
  /// that replaces the bar must not leave a dead key behind.
  static void unbindTarget(GlobalKey key) {
    if (!identical(_targetKey, key)) return;
    _targetKey = null;
    _onArrive = null;
  }

  /// Whether a destination is mounted and laid out right now.
  static bool get hasTarget => _targetRect() != null;

  static Rect? _rectOf(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  static Rect? _targetRect() => _rectOf(_targetKey?.currentContext);

  /// Sends a heart from [source] to the wishlist icon.
  ///
  /// Returns when the heart has landed and been taken off the overlay, so a
  /// caller can hold its button locked for exactly as long as its own heart
  /// is away. A missing end, a missing overlay or an unmounted source all
  /// return immediately: there is nothing to draw, and nothing to wait for.
  static Future<void> launch(
    BuildContext source, {
    required bool reducedMotion,
  }) async {
    final from = _rectOf(source);
    final to = _targetRect();
    if (from == null || to == null) return;

    // The root overlay, so the heart is above the page, its app bar and its
    // bottom bar -- and above a sheet, if the card is on one.
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
      builder: (_) => _FlyingHeart(
        from: from,
        to: to,
        reducedMotion: reducedMotion,
        onArrive: () => _onArrive?.call(),
        onDone: finish,
      ),
    );
    overlay.insert(entry);
    return done.future;
  }
}

/// One heart in flight. Owns its own controller, and takes itself off the
/// overlay when it is finished -- including if it is disposed early, so a
/// route popped mid-flight cannot leave it hanging.
class _FlyingHeart extends StatefulWidget {
  const _FlyingHeart({
    required this.from,
    required this.to,
    required this.reducedMotion,
    required this.onArrive,
    required this.onDone,
  });

  final Rect from;
  final Rect to;
  final bool reducedMotion;
  final VoidCallback onArrive;
  final VoidCallback onDone;

  @override
  State<_FlyingHeart> createState() => _FlyingHeartState();
}

class _FlyingHeartState extends State<_FlyingHeart>
    with SingleTickerProviderStateMixin {
  /// Long enough to read as a throw rather than a jump, short enough that a
  /// shopper saving a run of products is never waiting on it.
  static const _flight = Duration(milliseconds: 720);

  /// Reduced motion keeps the same beats -- a move, a fade, a destination
  /// that reacts -- in a fraction of the distance and time.
  static const _plain = Duration(milliseconds: 260);

  /// Where in the flight the destination is told to react: late enough to be
  /// nearly there, early enough that the two overlap.
  static const _arriveAt = 0.85;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.reducedMotion ? _plain : _flight,
  );

  /// The rotation this heart happens to take, within the 20-25 degrees the
  /// interaction is drawn to. Varied a little per flight so saving several
  /// products in a row does not look like one clip replayed.
  late final double _spin =
      (20 + math.Random().nextDouble() * 5) * math.pi / 180;

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

  /// The apex of the arc: 60-80 above whichever end is higher, so the heart
  /// always rises out of the page before it comes down on the icon.
  double get _apex => math.min(widget.from.top, widget.to.top) - 70;

  Offset _pointAt(double t) {
    final start = widget.from.center;
    final end = widget.to.center;
    // The full horizontal distance, evenly: the arc is in the height.
    final x = start.dx + (end.dx - start.dx) * t;

    if (widget.reducedMotion) {
      // No arc: a short drift towards the icon, not the whole journey.
      return Offset.lerp(start, end, t * 0.35)!;
    }

    // Up on power2.out, down on power2.in, which is what makes the top of the
    // arc float and the landing arrive.
    final double y;
    if (t <= 0.5) {
      final p = power2Out.transform(t / 0.5);
      y = start.dy + (_apex - start.dy) * p;
    } else {
      final p = power2In.transform((t - 0.5) / 0.5);
      y = _apex + (end.dy - _apex) * p;
    }
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    // The heart is positioned against the whole viewport, so it needs a Stack
    // of its own: an overlay entry's child is not one.
    return IgnorePointer(
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final at = _pointAt(t);
              // Gone over the last 15%, so it is spent by the time the
              // destination has finished reacting.
              final fade = t < 0.85 ? 1.0 : 1.0 - (t - 0.85) / 0.15;
              final scale = widget.reducedMotion ? 1.0 : 1.0 - 0.65 * t;

              return Positioned(
                left: at.dx - 12,
                top: at.dy - 12,
                child: Opacity(
                  opacity: fade.clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: widget.reducedMotion ? 0 : _spin * t,
                    child: Transform.scale(
                      scale: scale,
                      child: const Icon(
                        Icons.favorite,
                        size: 24,
                        color: AppColors.accent,
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
