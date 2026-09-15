import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../data/order_store.dart';

/// The colour each stage of an order is drawn in.
///
/// One map, so a badge, a timeline dot, a progress line and an icon cannot
/// disagree about what "Shipped" looks like. The values are the ones the brand
/// specifies for order status, to the byte.
///
/// ## Two colours per stage, and why
///
/// [markFor] is the specified hex, used wherever the colour is a *shape*: a
/// dot, a tick, an icon, the line joining two steps, the tint and edge of a
/// badge. [inkFor] is the same colour at a lightness that can be read as
/// *text*, because three of the specified values cannot be:
///
///   * Success Green `#22C55E` on white measures **2.28:1**
///   * Warm Amber `#F59E0B` measures **2.15:1**
///   * Delivered Green `#16A34A` measures **3.30:1**
///
/// Small text needs 4.5:1. Printing a status label in those would make the one
/// word that says where an order is the hardest thing on the card to read, so
/// the label takes the ink and everything else takes the mark. Where the
/// specified colour is already legible -- Trust Blue, Deep Blue -- the two are
/// the same colour and nothing is substituted.
class OrderStatusPalette {
  OrderStatusPalette._();

  /// Warm Amber. RGB 245, 158, 11.
  static const Color warmAmber = Color(0xFFF59E0B);

  /// The green a delivered order is marked in. RGB 22, 163, 74.
  static const Color deliveredGreen = Color(0xFF16A34A);

  /// Nothing has happened here yet: Mountain Grey, the brand's own line
  /// colour, which is what an inactive step should look like.
  static const Color upcoming = AppColors.mountainGrey;

  /// The dot, the tick, the icon, the line.
  static Color markFor(OrderStage stage) => switch (stage) {
    OrderStage.placed => AppColors.trustBlue,
    OrderStage.confirmed => AppColors.successGreen,
    OrderStage.packed => warmAmber,
    OrderStage.shipped => AppColors.shipLand,
    OrderStage.outForDelivery => AppColors.commerceOrange,
    OrderStage.delivered => deliveredGreen,
  };

  /// The same status, in a tone that can carry words.
  ///
  /// Measured against white: Trust Blue 5.09-5.89:1 across the set -- Trust
  /// Blue 5.34, the green ink 5.89, the amber ink 5.09, Deep Blue 5.17.
  /// Commerce Orange stays at 3.90:1, which clears AA for the bold 12pt
  /// label it is used on and nothing smaller.
  static Color inkFor(OrderStage stage) => switch (stage) {
    OrderStage.placed => AppColors.trustBlue,
    OrderStage.confirmed => AppColors.successInk,
    OrderStage.packed => amberInk,
    OrderStage.shipped => AppColors.shipLand,
    OrderStage.outForDelivery => AppColors.commerceOrange,
    OrderStage.delivered => AppColors.successInk,
  };

  /// Warm Amber taken down until it can be read: hue 37.3 against the brand
  /// amber's 37.7, and **5.09:1 on white**. Derived rather than picked, the
  /// same way [AppColors.successInk] is derived from the brand green.
  static const Color amberInk = Color(0xFF9A6206);
}
