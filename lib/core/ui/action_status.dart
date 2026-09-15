import 'package:flutter/material.dart';

import '../theme/colors.dart';

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
  /// The words for an add. Shared by the rich card and by anything that
  /// still says it in one line, so there is one phrase for the event.
  static const addedToCartLabel = 'Added to Cart';
  static const removedFromCart = 'Removed from Cart';
  static const addedToWishlist = 'Added to Wishlist';
  static const removedFromWishlist = 'Removed from Wishlist';

  /// The confirmation a shopper gets after a product reaches the cart.
  ///
  /// Richer than the one-line status the other three events use, because it
  /// answers the two questions an add raises: *which* thing went in -- a
  /// listing sold in twenty-one colourways needs its variant named -- and how
  /// many of it are now there.
  ///
  /// Called only once the add has happened, and given the count the cart
  /// itself returned rather than one worked out here.
  static void addedToCart(
    BuildContext context, {
    required String title,
    required int inCart,
    required VoidCallback onViewCart,
    String? variant,
  }) {
    final theme = Theme.of(context);
    // On the brand's Trust Blue rather than the platform's grey bar, so the
    // card is the shop's own and stands clear of whatever page it floats
    // over, in either theme. White on it clears 5:1.
    const onBar = Colors.white;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.trustBlue,
          closeIconColor: onBar,
          // Tighter than the default 16/14: the card is three short lines,
          // and the padding was most of its height.
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          // Longer than the default: there are three things to read here
          // rather than one.
          duration: const Duration(seconds: 4),
          // Material's own dismiss, rather than a second one drawn by hand.
          showCloseIcon: true,
          content: Row(
            children: [
              const _AddedMark(ink: onBar),
              const SizedBox(width: 10),
              // The rule the reference draws between the mark and the words.
              SizedBox(
                width: 1,
                height: 34,
                child: ColoredBox(color: onBar.withValues(alpha: 0.25)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // One line rather than a Row: a Row of two Texts
                    // overflowed by 166px the first time a long variant name
                    // met a narrow phone, because the label could not shrink.
                    Text.rich(
                      TextSpan(
                        children: [
                          // White, not an accent: Commerce Orange on Trust
                          // Blue is barely 1.3:1. The weight carries it.
                          const TextSpan(
                            text: addedToCartLabel,
                            style: TextStyle(
                              color: onBar,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (variant != null && variant.isNotEmpty)
                            TextSpan(
                              text: ' · $variant',
                              style: TextStyle(
                                color: onBar.withValues(alpha: 0.80),
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontSize: 12.5,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onBar,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // The reference sets the action beside the words. That is
                    // a wide card; on a 406dp phone it left the chip 93dp to
                    // live in and it overflowed by 86. Under the words, on the
                    // same line as the count, both fit and nothing is lost.
                    // A Wrap rather than a Row: side by side when they
                    // fit, the action dropping to its own line when they do
                    // not. A Row overflowed by 74px on a 406dp phone, because
                    // the snack bar's margin, padding and close icon leave the
                    // content about 216dp to work in.
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _InCartChip(count: inCart, ink: onBar),
                        _ViewCartButton(onPressed: onViewCart),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

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

/// The cart mark with its tick, from the reference.
class _AddedMark extends StatelessWidget {
  const _AddedMark({required this.ink});

  final Color ink;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ink.withValues(alpha: 0.16),
            ),
            child: Icon(Icons.shopping_cart_outlined, size: 17, color: ink),
          ),
          // The tick in Commerce Orange, the brand's accent, ringed in the
          // card's own blue so it sits cleanly on the circle behind it.
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.commerceOrange,
                border: Border.all(color: AppColors.trustBlue, width: 1.5),
              ),
              child: const Icon(Icons.check, size: 9, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// "2 in cart" -- the count the cart itself reported.
class _InCartChip extends StatelessWidget {
  const _InCartChip({required this.count, required this.ink});

  final int count;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 13, color: ink),
          const SizedBox(width: 5),
          Text(
            '$count in cart',
            style: theme.textTheme.labelMedium?.copyWith(
              color: ink,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// The one action on the card.
class _ViewCartButton extends StatelessWidget {
  const _ViewCartButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The call to action in Commerce Orange: the brand's accent is what its
    // buttons wear, and it stands off the blue card at a glance.
    return Material(
      color: AppColors.commerceOrange,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // The bar goes with the tap: leaving it over the cart it just
          // opened is a status about a page the shopper is now looking at.
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          onPressed();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'View cart',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Icon(Icons.chevron_right, size: 16, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
