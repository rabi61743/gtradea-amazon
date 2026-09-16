import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../shared/motion/motion_curves.dart';
import '../../home/widgets/product_rail.dart' show formatGrouped;

/// A rise in the points balance, as the animation needs to hear about it.
///
/// Nothing here knows where the numbers came from. Today the only source is
/// [PointsCelebration.preview], a demonstration; once the points API exists
/// the same object carries the server's figures and the animation does not
/// change.
@immutable
class PointsIncrease {
  const PointsIncrease({
    required this.previous,
    required this.next,
    this.preview = false,
  });

  final int previous;
  final int next;

  /// True for a demonstration of the animation. A preview never changes the
  /// balance, and it is labelled on screen so it cannot be read as a reward.
  final bool preview;

  /// How much the balance rose by.
  int get amount => next - previous;
}

/// Where a change in the points balance is announced to the coin and figure.
///
/// The animation's only entry points. The real one, [play], is what the points
/// API will call when it reports a new balance -- nothing calls it yet,
/// because that API does not exist. The demonstration, [preview], is separate
/// on purpose, and is not reachable from a release build.
class PointsCelebration {
  PointsCelebration._();

  static final ValueNotifier<PointsIncrease?> _events = ValueNotifier(null);

  /// What the coin and the figure listen to.
  static ValueListenable<PointsIncrease?> get events => _events;

  /// Announces a real rise in the balance, from the points API.
  ///
  /// [newBalance] is the server's figure; [previousBalance] is what was shown
  /// before it. A fall or no change plays nothing -- this celebrates earning.
  static void play({required int previousBalance, required int newBalance}) {
    if (newBalance <= previousBalance) return;
    _events.value = PointsIncrease(previous: previousBalance, next: newBalance);
  }

  /// Plays the animation over the current balance, as a demonstration only.
  ///
  /// The figure rolls up by [amount], the badge says "preview", and the figure
  /// rolls back to the real balance afterwards. Nothing is stored, sent or
  /// credited.
  static void preview({required int balance, int amount = previewAmount}) {
    if (!previewEnabled) return;
    _events.value = PointsIncrease(
      previous: balance,
      next: balance + amount,
      preview: true,
    );
  }

  /// The example rise the preview uses.
  static const previewAmount = 50;

  /// The preview is for building and reviewing the animation. A release build
  /// has no way to reach it.
  static bool get previewEnabled => !kReleaseMode;

  /// Whether the coin's arrival has already played in this run of the app.
  ///
  /// Held here rather than in a widget, so it survives the header being
  /// rebuilt, recreated or scrolled away and back: the arrival belongs to the
  /// app opening, not to the widget happening to be built again.
  static bool _arrived = false;

  @visibleForTesting
  static void resetForTest() {
    _arrived = false;
    _events.value = null;
  }
}

/// The coin, taught to arrive and to celebrate.
///
/// Wraps whatever coin the card already draws -- its colour, border, letter
/// and size are the card's. At rest this adds nothing: no glow, no particles,
/// no scale. It moves once when the app opens, and again each time the balance
/// rises.
class AnimatedPointsCoin extends StatefulWidget {
  const AnimatedPointsCoin({
    super.key,
    required this.size,
    required this.child,
  });

  /// The coin's diameter, which the glow and sparkles are measured from.
  final double size;

  /// How long after the coin is first built the app-open arrival starts: just
  /// past the loading screen's 220 ms cross-fade into the page.
  static const arrivalDelay = Duration(milliseconds: 320);
  final Widget child;

  @override
  State<AnimatedPointsCoin> createState() => _AnimatedPointsCoinState();
}

class _AnimatedPointsCoinState extends State<AnimatedPointsCoin>
    with SingleTickerProviderStateMixin {
  static const _gold = Color(0xFFF5B301);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  );

  /// True while the arrival plays, which starts from a smaller, fainter coin
  /// rather than from the coin's resting size.
  bool _arriving = false;

  @override
  void initState() {
    super.initState();
    PointsCelebration.events.addListener(_onIncrease);
    if (!PointsCelebration._arrived) {
      PointsCelebration._arrived = true;
      // The home page is only built once loading has finished, and it then
      // cross-fades in over 220 ms. Waiting a beat past that means the pop is
      // seen whole on a page that is fully there, rather than half of it
      // playing under the fade.
      _arrival = Timer(AnimatedPointsCoin.arrivalDelay, _arrive);
    }
  }

  Timer? _arrival;

  bool get _reduced => MediaQuery.of(context).disableAnimations;

  void _arrive() {
    if (!mounted || _reduced) return;
    setState(() => _arriving = true);
    _c.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _arriving = false);
    });
  }

  void _onIncrease() {
    if (!mounted || PointsCelebration.events.value == null || _reduced) return;
    setState(() => _arriving = false);
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _arrival?.cancel();
    PointsCelebration.events.removeListener(_onIncrease);
    _c.dispose();
    super.dispose();
  }

  /// Pops past its size on back.out, then settles on elastic.out.
  double _scale(double t) {
    final from = _arriving ? 0.55 : 0.85;
    if (t <= 0.32) {
      return from + (1.18 - from) * backOut3.transform(t / 0.32);
    }
    return 1 + 0.18 * (1 - elasticOutSoft.transform((t - 0.32) / 0.68));
  }

  /// A small wobble that dies away.
  double _rotation(double t) => 0.22 * math.sin(t * math.pi * 5) * (1 - t);

  /// The gold bloom behind the coin: up quickly, then fading out.
  double _glow(double t) {
    if (t < 0.18) return t / 0.18;
    return (1 - (t - 0.18) / 0.62).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final resting = t >= 1;
        if (resting) return child!;

        final glow = _glow(t);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Behind the coin, larger than it, and gone by the settle.
            Positioned(
              left: -size * 0.6,
              top: -size * 0.6,
              width: size * 2.2,
              height: size * 2.2,
              child: IgnorePointer(
                child: Opacity(
                  opacity: glow * 0.9,
                  child: Transform.scale(
                    scale: 0.6 + 0.6 * t,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0x99FFD54F), Color(0x00FFD54F)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Opacity(
              opacity: _arriving ? (t / 0.2).clamp(0.0, 1.0) : 1,
              child: Transform.rotate(
                angle: _rotation(t),
                child: Transform.scale(scale: _scale(t), child: child),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: size,
              height: size,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SparklePainter(progress: t, color: _gold),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Small gold particles thrown out from the coin's centre, shrinking and
/// fading as they go. Drawn, not built: nothing is left in the tree when the
/// burst ends, because the painter is only there while the animation runs.
class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const _count = 8;

  @override
  void paint(Canvas canvas, Size size) {
    // The burst takes the first two thirds of the animation.
    final p = (progress / 0.66).clamp(0.0, 1.0);
    if (p >= 1) return;
    final eased = Curves.easeOutCubic.transform(p);
    final centre = size.center(Offset.zero);
    final reach = size.width * 0.55 + size.width * 0.85 * eased;
    final paint = Paint()..color = color.withValues(alpha: 1 - p);

    for (var i = 0; i < _count; i++) {
      final angle = (i / _count) * 2 * math.pi + 0.3;
      final at = centre + Offset(math.cos(angle), math.sin(angle)) * reach;
      final radius = size.width * 0.075 * (1 - 0.7 * p);
      canvas.drawCircle(at, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.progress != progress;
}

/// The balance figure, taught to count up to a new value.
///
/// Shows [balance] -- the real one, from the card -- whenever it is not in the
/// middle of an animation. A rise rolls the number up like an odometer,
/// overshoots a little, settles with a brief gold flash, and sends a "+N" up
/// from the coin. A preview does the same and then rolls back to [balance], so
/// the figure never stays on a number the account does not have.
class AnimatedPointsFigure extends StatefulWidget {
  const AnimatedPointsFigure({
    super.key,
    required this.balance,
    required this.style,
  });

  final int balance;
  final TextStyle? style;

  @override
  State<AnimatedPointsFigure> createState() => _AnimatedPointsFigureState();
}

class _AnimatedPointsFigureState extends State<AnimatedPointsFigure>
    with TickerProviderStateMixin {
  static const _gold = Color(0xFFFFD54F);

  /// The count itself.
  late final AnimationController _roll = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// The landing: a quick swell and a gold highlight.
  late final AnimationController _land = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// After a preview: a hold on the example figure, then the walk back to the
  /// real balance. One timeline, so the pause is part of the animation rather
  /// than a gap in it.
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  /// Where in [_back] the hold ends and the walk down begins.
  static const _holdFraction = 0.7;

  /// A slight overshoot past the target before easing back to it.
  static const _overshoot = BackOutCurve(1.2);

  PointsIncrease? _playing;
  OverlayEntry? _badge;

  @override
  void initState() {
    super.initState();
    PointsCelebration.events.addListener(_onIncrease);
  }

  Future<void> _onIncrease() async {
    final rise = PointsCelebration.events.value;
    if (!mounted || rise == null) return;

    _back.value = 0;
    setState(() => _playing = rise);
    _showBadge(rise);

    if (MediaQuery.of(context).disableAnimations) {
      _roll.value = 1;
    } else {
      await _roll.forward(from: 0).orCancel.catchError((_) {});
      if (!mounted) return;
      await _land.forward(from: 0).orCancel.catchError((_) {});
      _land.value = 0;
    }
    if (!mounted || !identical(_playing, rise)) return;

    if (rise.preview) {
      // A preview hands the figure back: it was never the balance. The hold
      // on the example figure is the first part of this same animation.
      await _back.forward(from: 0).orCancel.catchError((_) {});
    }
    if (mounted && identical(_playing, rise)) setState(() => _playing = null);
  }

  /// What the figure reads at this moment.
  int get _shown {
    final rise = _playing;
    if (rise == null) return widget.balance;
    final rolled =
        rise.previous + rise.amount * _overshoot.transform(_roll.value);
    if (!rise.preview || _back.value == 0) return rolled.round();
    // Back down to what the account really holds.
    final returning = Curves.easeInOut.transform(
      ((_back.value - _holdFraction) / (1 - _holdFraction)).clamp(0.0, 1.0),
    );
    return (rise.next + (widget.balance - rise.next) * returning).round();
  }

  void _showBadge(PointsIncrease rise) {
    _badge?.remove();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final box = context.findRenderObject();
    if (overlay == null || box is! RenderBox || !box.hasSize) return;
    final at = box.localToGlobal(Offset.zero);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FloatingReward(
        anchor: at,
        amount: rise.amount,
        preview: rise.preview,
        reducedMotion: MediaQuery.of(context).disableAnimations,
        onDone: () {
          if (identical(_badge, entry)) _badge = null;
          entry.remove();
        },
      ),
    );
    _badge = entry;
    overlay.insert(entry);
  }

  @override
  void dispose() {
    PointsCelebration.events.removeListener(_onIncrease);
    _badge?.remove();
    _roll.dispose();
    _land.dispose();
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_roll, _land, _back]),
      builder: (context, _) {
        final land = _land.value;
        // Up and back within the landing, peaking a third of the way in.
        final swell = land == 0
            ? 0.0
            : math.sin(math.pi * Curves.easeOut.transform(land));
        final style = widget.style;

        return Transform.scale(
          scale: 1 + 0.14 * swell,
          alignment: Alignment.centerLeft,
          child: Text(
            formatGrouped(_shown),
            key: const ValueKey('points-figure'),
            maxLines: 1,
            style: style?.copyWith(
              color: Color.lerp(style.color, _gold, swell),
            ),
          ),
        );
      },
    );
  }
}

/// The "+N" that rises from the figure and fades.
class _FloatingReward extends StatefulWidget {
  const _FloatingReward({
    required this.anchor,
    required this.amount,
    required this.preview,
    required this.reducedMotion,
    required this.onDone,
  });

  final Offset anchor;
  final int amount;
  final bool preview;
  final bool reducedMotion;
  final VoidCallback onDone;

  @override
  State<_FloatingReward> createState() => _FloatingRewardState();
}

class _FloatingRewardState extends State<_FloatingReward>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              // Pops in on a bounce, then drifts up and fades.
              final pop = widget.reducedMotion
                  ? 1.0
                  : backOut3.transform((t / 0.22).clamp(0.0, 1.0));
              final drift = widget.reducedMotion
                  ? 0.0
                  : 34 * Curves.easeOut.transform(t);
              final fade = t < 0.55 ? 1.0 : 1 - (t - 0.55) / 0.45;

              return Positioned(
                left: widget.anchor.dx,
                top: widget.anchor.dy - 22 - drift,
                child: Opacity(
                  opacity: fade.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: pop,
                    alignment: Alignment.bottomLeft,
                    child: _Badge(
                      amount: widget.amount,
                      preview: widget.preview,
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

class _Badge extends StatelessWidget {
  const _Badge({required this.amount, required this.preview});

  final int amount;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    // The badge is drawn in the overlay, above any Material. Without one its
    // text has no style to inherit, and Flutter marks that with the yellow
    // double underline -- which is what the phone showed.
    return Material(type: MaterialType.transparency, child: _badge());
  }

  Widget _badge() {
    return Semantics(
      // Said plainly, so a screen reader does not announce a reward either.
      excludeSemantics: true,
      label: preview
          ? 'Animation preview. No points were added.'
          : 'Plus $amount points',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF5B301),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '+$amount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            if (preview) ...[
              const SizedBox(width: 5),
              Text(
                'preview',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
