import 'package:flutter/material.dart';

/// Scroll physics that land a flick on a card rather than between two.
///
/// A horizontal rail without this drifts to a stop wherever momentum runs out,
/// which leaves a card half off the edge and makes the row read as a strip that
/// slid rather than a set of things. Snapping is most of what separates a rail
/// that feels built from one that feels like an overflowing `Row`.
///
/// Not [PageScrollPhysics]: that snaps to viewport widths, and these rails show
/// two and a bit cards at a time. The step is one card plus one gap.
class SnapPhysics extends ScrollPhysics {
  const SnapPhysics({required this.step, super.parent});

  /// One card plus the gap after it. The caller owns both numbers, so this
  /// cannot drift out of step with the layout the way a copied constant would.
  final double step;

  @override
  SnapPhysics applyTo(ScrollPhysics? ancestor) =>
      SnapPhysics(step: step, parent: buildParent(ancestor));

  double _target(ScrollMetrics position, double velocity) {
    final page =
        (position.pixels / step) +
        // A flick carries you on rather than snapping back to where the finger
        // left. Half a card's worth of intent is enough to count as "next".
        (velocity / 1000).clamp(-1.0, 1.0);
    return (page.roundToDouble() * step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Out of bounds: let the parent bounce it back first.
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final target = _target(position, velocity);
    final tol = toleranceFor(position);
    if ((target - position.pixels).abs() < tol.distance) return null;

    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tol,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
