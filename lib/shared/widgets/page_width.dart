import 'package:flutter/widgets.dart';

/// The measure the page's sections share: 97% of the screen, centred.
///
/// A share of the width rather than a fixed inset, so the margin is the same
/// fraction of a 360pt phone, a tablet and a desktop window -- 5.4, 8.2 and
/// more, rather than the flat 16 every block used to carry regardless.
///
/// One place for it because the point is consistency: the hero, the flash sale,
/// the promotional blocks and the rails all have to line up down the page, and
/// they cannot if each keeps its own number.
abstract final class PageWidth {
  /// How much of the screen a section takes.
  static const factor = 0.97;

  /// What is left on each side of it: 1.5% of the width.
  static double marginOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width * (1 - factor) / 2;

  /// That margin as insets, for the blocks that lay themselves out with
  /// padding rather than by being wrapped.
  static EdgeInsets insets(
    BuildContext context, {
    double top = 0,
    double bottom = 0,
  }) {
    final side = marginOf(context);
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }
}
