import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/widgets/header_action_tile.dart';
import '../data/cart_store.dart';
import 'cart_flight.dart';
import 'cart_screen.dart';

/// The cart in the home header, beside orders and notifications.
///
/// The same destination the bottom bar's cart reaches and the same count
/// behind it -- [CartStore.count] -- so the two can never disagree about how
/// many things are in there. It is here as well as there because a shopper
/// reading the top of the page should not have to look to the bottom of it to
/// see what they have already picked up.
///
/// Filled while there is something in it, outline when there is not, matching
/// the pair it sits with: the state has to read without depending on the badge
/// alone.
class CartHeaderButton extends StatelessWidget {
  const CartHeaderButton({
    super.key,
    this.color = AppColors.onPrimary,
    this.size = 20,
    this.label = 'Shopping Cart',
    this.onOpened,
  });

  final Color color;
  final double size;
  final String label;
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartStore.instance,
      builder: (context, _) {
        final count = CartStore.instance.count;

        return CartFlightTarget(
          child: HeaderActionTile(
            icon: count > 0
                ? Icons.shopping_cart
                : Icons.shopping_cart_outlined,
            label: label,
            count: count,
            tooltip: switch (count) {
              0 => 'Your cart is empty',
              1 => '1 item in your cart',
              final n => '$n items in your cart',
            },
            color: color,
            iconSize: size,
            onTap: () {
              onOpened?.call();
              // A guest keeps a cart on the device, so this needs no sign-in
              // gate -- unlike orders, there is something here for them either
              // way.
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const CartScreen()));
            },
          ),
        );
      },
    );
  }
}
