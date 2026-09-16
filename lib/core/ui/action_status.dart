import 'package:flutter/material.dart';

/// What the app says back when a shopper changes their cart or their list.
///
/// Four events, four phrases, one place. They were written six times over --
/// "added to your cart", "Added to your cart. 3 in cart.", "Moved to your
/// cart.", "Saved to your list", "Removed from your list", "Removed <title>"
/// -- so the same event read differently depending on which screen it was
/// done from, and there was nowhere to change the wording once.
///
/// The status is deliberately the same whichever screen raised it: a shopper
/// learns four phrases, not six, and recognises them without reading.
abstract final class ActionStatus {
  /// The words for an add, for anything that says it in one line.
  static const addedToCartLabel = 'Added to Cart';
  static const removedFromCart = 'Removed from Cart';
  static const addedToWishlist = 'Added to Wishlist';
  static const removedFromWishlist = 'Removed from Wishlist';

  /// Shows a status, replacing whatever is already up.
  ///
  /// Replacing rather than queueing is what keeps a fast hand from building a
  /// backlog of identical messages: five taps leave one status on screen, not
  /// five waiting their turn. It is also why this is a function rather than a
  /// line copied into each caller -- the hide is easy to forget, and every
  /// place that forgot it queued.
  ///
  /// [detail] is appended after a separator where a screen has something worth
  /// adding, such as how many are now in the cart.
  static void show(
    BuildContext context,
    String status, {
    String? detail,
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(detail == null ? status : '$status · $detail'),
          behavior: SnackBarBehavior.floating,
          action: action,
        ),
      );
  }
}
