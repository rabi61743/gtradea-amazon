import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// The product page's Add to cart, with the drop-into-the-cart interaction.
///
/// Only the product page uses this. Every other add-to-cart in the app keeps
/// its own plain button.
///
/// At rest it is the same outlined pill as before -- cart icon, label, the
/// theme's style -- with nothing moving. A tap plays one short sequence: a
/// folded shirt appears above the cart, lifts, drops into it, a faint ring
/// marks the impact and the cart springs and wobbles. The button only turns
/// to "Added to cart" once that has settled **and** [onAdd] has confirmed the
/// line is really in the cart; if [onAdd] says it is not, the button quietly
/// returns to rest.
///
/// Everything moves by transform and opacity inside its own repaint layer, so
/// it costs a frame nothing beyond the button itself and never touches layout
/// or the page's scroll.
class AnimatedAddToCartButton extends StatefulWidget {
  const AnimatedAddToCartButton({
    super.key,
    required this.onAdd,
    this.enabled = true,
    this.label = 'Add to cart',
    this.addedLabel = 'Added to cart',
    this.textStyle,
  });

  /// Adds to the cart and completes with whether the cart really has it.
  ///
  /// True only once the add is confirmed; false when it was refused before or
  /// after the request (a sold-out option, a failed save), in which case the
  /// caller has already told the shopper why.
  final Future<bool> Function() onAdd;

  final bool enabled;
  final String label;
  final String addedLabel;
  final TextStyle? textStyle;

  /// The whole drop, from the tap to the cart settling.
  static const dropDuration = Duration(milliseconds: 1000);

  /// The swap to the success content.
  static const successDuration = Duration(milliseconds: 360);

  /// How long "Added to cart" stays before the button is ready again.
  ///
  /// Four seconds rather than two and a half: long enough to be read without
  /// looking for it, and short enough that the button is ready for the next
  /// add without anybody waiting on it.
  static const holdSuccess = Duration(seconds: 4);

  /// The success tint and its ink: the design system's success green, pale.
  static final Color successFill = AppColors.successGreen.withValues(
    alpha: 0.14,
  );
  static const Color successInk = AppColors.successInk;

  @override
  State<AnimatedAddToCartButton> createState() =>
      _AnimatedAddToCartButtonState();
}

enum _Phase { idle, busy, success }

class _AnimatedAddToCartButtonState extends State<AnimatedAddToCartButton>
    with TickerProviderStateMixin {
  late final AnimationController _drop = AnimationController(
    vsync: this,
    duration: AnimatedAddToCartButton.dropDuration,
  );
  late final AnimationController _success = AnimationController(
    vsync: this,
    duration: AnimatedAddToCartButton.successDuration,
  );

  _Phase _phase = _Phase.idle;
  Timer? _reset;

  /// Bumped on every tap, so an answer from an earlier tap cannot settle a
  /// later one.
  int _run = 0;

  @override
  void dispose() {
    _reset?.cancel();
    _drop.dispose();
    _success.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    // One add at a time: taps during the drop, while the save is pending or
    // while "Added" is showing do nothing, so nothing is sent twice.
    if (_phase != _Phase.idle) return;
    final run = ++_run;
    final reduced = MediaQuery.of(context).disableAnimations;

    setState(() => _phase = _Phase.busy);
    _success.value = 0;

    // The drop and the real add start together; neither waits for the other
    // to begin. Reduced motion skips the drop entirely.
    final dropped = reduced
        ? Future<void>.value()
        : _drop.forward(from: 0).orCancel.catchError((_) {});
    final added = widget.onAdd();

    final bool confirmed;
    try {
      confirmed = await added;
    } catch (_) {
      if (mounted && run == _run) _backToIdle();
      return;
    }
    await dropped;
    if (!mounted || run != _run) return;

    if (!confirmed) {
      _backToIdle();
      return;
    }

    setState(() => _phase = _Phase.success);
    if (reduced) {
      _success.value = 1;
    } else {
      unawaited(_success.forward(from: 0));
    }
    _reset?.cancel();
    _reset = Timer(AnimatedAddToCartButton.holdSuccess, () {
      if (mounted && run == _run) _backToIdle();
    });
  }

  void _backToIdle() {
    _drop.value = 0;
    _success.value = 0;
    setState(() => _phase = _Phase.idle);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = _phase == _Phase.success;
    final ink = success
        ? AnimatedAddToCartButton.successInk
        : theme.colorScheme.primary;

    return RepaintBoundary(
      child: Semantics(
        button: true,
        liveRegion: true,
        label: success ? widget.addedLabel : null,
        child: AnimatedBuilder(
          animation: Listenable.merge([_drop, _success]),
          builder: (context, _) {
            final t = _drop.value;
            return Transform.scale(
              scale: _press(t),
              child: OutlinedButton(
                // Held enabled while busy or showing success so the pill keeps
                // its colours; the tap handler is what ignores the taps.
                onPressed: widget.enabled || _phase != _Phase.idle
                    ? _tap
                    : null,
                style: OutlinedButton.styleFrom(
                  textStyle: widget.textStyle,
                  backgroundColor: success
                      ? Color.lerp(
                          Colors.transparent,
                          AnimatedAddToCartButton.successFill,
                          _success.value.clamp(0, 1),
                        )
                      : null,
                  foregroundColor: success ? ink : null,
                  side: success
                      ? BorderSide(
                          color: Color.lerp(
                            theme.colorScheme.outline,
                            AppColors.successGreen.withValues(alpha: 0.45),
                            _success.value.clamp(0, 1),
                          )!,
                        )
                      : null,
                ),
                child: success ? _successContent() : _restingContent(t),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The resting pill, with the shirt, the ring and the cart's spring drawn
  /// over the icon while the drop plays.
  Widget _restingContent(double t) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 18,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (t > 0 && t < 1) _ring(t),
              _cart(t),
              if (t > 0 && t < 0.46) _shirt(t),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(widget.label, maxLines: 1),
          ),
        ),
      ],
    );
  }

  Widget _successContent() {
    final v = _success.value.clamp(0.0, 1.0);
    // First the cart and its label fade out together, then the check and
    // "Added" scale up with a small overshoot over the pale-green fill.
    final out = 1 - _seg(v, 0, 0.35);
    final inT = _seg(v, 0.3, 1);
    final s = Curves.easeOutBack.transform(inT);
    return Stack(
      alignment: Alignment.center,
      children: [
        if (out > 0)
          Opacity(
            opacity: out,
            child: ExcludeSemantics(child: _restingContent(1)),
          ),
        Opacity(
          opacity: inT,
          child: Transform.scale(scale: 0.7 + 0.3 * s, child: _addedRow()),
        ),
      ],
    );
  }

  Widget _addedRow() {
    return Row(
      key: const ValueKey('add-to-cart-success'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.check_rounded,
          size: 18,
          color: AnimatedAddToCartButton.successInk,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(widget.addedLabel, maxLines: 1),
          ),
        ),
      ],
    );
  }

  // ---- The sequence, as fractions of [dropDuration] ----
  //
  //   0.00-0.18  anticipation: shirt fades in, lifts, stretches; button presses
  //   0.18-0.38  drop: accelerating fall, longer and narrower
  //   0.38-0.46  impact: shirt flattens, shrinks and fades into the cart
  //   0.38-0.62  ring expands and fades from the contact point
  //   0.38-1.00  cart squashes, springs past its size, wobbles and settles

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  /// The quick press-in at the tap.
  double _press(double t) {
    if (t <= 0 || t >= 0.2) return 1;
    final p = _seg(t, 0, 0.2);
    return 1 - 0.04 * math.sin(p * math.pi);
  }

  Widget _shirt(double t) {
    double y;
    double sx;
    double sy;
    double opacity;
    if (t < 0.18) {
      final p = Curves.easeOut.transform(_seg(t, 0, 0.18));
      y = -16 - 6 * p;
      sx = 1 - 0.12 * p;
      sy = 1 + 0.15 * p;
      opacity = _seg(t, 0, 0.08);
    } else if (t < 0.38) {
      final p = Curves.easeIn.transform(_seg(t, 0.18, 0.38));
      y = -22 + 20 * p;
      sx = 0.88 - 0.1 * p;
      sy = 1.15 + 0.2 * p;
      opacity = 1;
    } else {
      final p = _seg(t, 0.38, 0.46);
      y = -2 + 2 * p;
      final flat = math.sin(math.min(p * 2, 1) * math.pi / 2);
      final shrink = 1 - Curves.easeIn.transform(p);
      sx = (0.78 + 0.5 * flat) * shrink;
      sy = (1.35 - 0.85 * flat) * shrink;
      opacity = 1 - p;
    }
    return Positioned(
      top: y,
      child: Opacity(
        opacity: opacity.clamp(0, 1),
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.diagonal3Values(sx, sy, 1),
          child: const CustomPaint(
            size: Size(12, 10),
            painter: _FoldedShirtPainter(color: AppColors.commerceOrange),
          ),
        ),
      ),
    );
  }

  Widget _ring(double t) {
    if (t < 0.38 || t > 0.62) return const SizedBox.shrink();
    final p = Curves.easeOut.transform(_seg(t, 0.38, 0.62));
    return Positioned(
      top: -2,
      child: IgnorePointer(
        child: Opacity(
          opacity: (0.35 * (1 - p)).clamp(0, 1),
          child: Transform.scale(
            scale: 0.4 + 1.4 * p,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cart(double t) {
    var sx = 1.0;
    var sy = 1.0;
    var angle = 0.0;
    if (t >= 0.38 && t < 1) {
      final p = _seg(t, 0.38, 1);
      // Squash on contact, then a damped spring back through its size.
      final spring = math.exp(-5 * p) * math.cos(p * math.pi * 3.2);
      sy = 1 - 0.18 * spring;
      sx = 1 + 0.12 * spring;
      // A side-to-side wobble that loses strength with every swing.
      angle = 0.16 * math.exp(-4 * p) * math.sin(p * math.pi * 5);
    }
    return Transform.rotate(
      angle: angle,
      alignment: Alignment.bottomCenter,
      child: Transform(
        alignment: Alignment.bottomCenter,
        transform: Matrix4.diagonal3Values(sx, sy, 1),
        child: const Icon(Icons.add_shopping_cart, size: 18),
      ),
    );
  }
}

/// A small folded shirt: a body with sleeves folded in and a collar notch.
class _FoldedShirtPainter extends CustomPainter {
  const _FoldedShirtPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = Paint()..color = color;
    final fold = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;

    final shape = Path()
      ..moveTo(0, h * 0.28)
      ..lineTo(w * 0.32, 0)
      ..lineTo(w * 0.42, h * 0.12)
      ..lineTo(w * 0.58, h * 0.12)
      ..lineTo(w * 0.68, 0)
      ..lineTo(w, h * 0.28)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(shape, body);
    // The folds: sleeves tucked in down each side.
    canvas.drawLine(
      Offset(w * 0.22, h * 0.34),
      Offset(w * 0.22, h * 0.92),
      fold,
    );
    canvas.drawLine(
      Offset(w * 0.78, h * 0.34),
      Offset(w * 0.78, h * 0.92),
      fold,
    );
  }

  @override
  bool shouldRepaint(_FoldedShirtPainter old) => old.color != color;
}
