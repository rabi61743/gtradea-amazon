/// The two easings this app's micro-interactions are specified in that
/// Flutter's own catalogue does not carry at the right strength.
///
/// Flutter has `Curves.easeOutBack` and `Curves.elasticOut`, but both are
/// fixed: the first overshoots at 1.70158, the second runs on a 0.4 period.
/// The wishlist interaction is drawn to `back.out(3)` and
/// `elastic.out(1, 0.55)`, which are stronger and slower to settle. These are
/// the same formulae with the constant left open.
library;

import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// Overshoots past the end and comes back, like `back.out(s)`.
///
/// `overshoot` is the `s` of the standard back easing: 1.70158 is the usual
/// one, and the 3 this app uses is a distinctly springier pop.
class BackOutCurve extends Curve {
  const BackOutCurve(this.overshoot);

  final double overshoot;

  @override
  double transformInternal(double t) {
    final u = t - 1.0;
    return u * u * ((overshoot + 1) * u + overshoot) + 1.0;
  }

  @override
  String toString() => 'BackOutCurve($overshoot)';
}

/// Settles with a decaying wobble, like `elastic.out(amplitude, period)`.
///
/// The period is what Flutter's [Curves.elasticOut] pins at 0.4; a longer one
/// swings fewer, slower times, which is the settle this interaction asks for.
class ElasticOutCurve extends Curve {
  const ElasticOutCurve({this.amplitude = 1.0, this.period = 0.55});

  final double amplitude;
  final double period;

  @override
  double transformInternal(double t) {
    // The phase offset that makes the curve leave 0 cleanly, as in the
    // reference implementation.
    final s = period / (2 * math.pi) * math.asin(1 / math.max(amplitude, 1));
    return amplitude *
            math.pow(2.0, -10 * t) *
            math.sin((t - s) * (2 * math.pi) / period) +
        1.0;
  }

  @override
  String toString() => 'ElasticOutCurve($amplitude, $period)';
}

/// `power2.out` and `power2.in`: the quadratic pair the flight's rise and fall
/// are drawn to. Named here so the call sites read as the spec does.
const Curve power2Out = Curves.easeOutQuad;
const Curve power2In = Curves.easeInQuad;

/// `power1.out`, which the glow fades on.
const Curve power1Out = Curves.easeOut;

/// The pop, and the settle after it.
const Curve backOut3 = BackOutCurve(3);
const Curve elasticOutSoft = ElasticOutCurve(amplitude: 1, period: 0.55);
