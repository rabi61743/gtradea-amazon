import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/widgets/header_action_tile.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../data/order_store.dart';
import 'orders_screen.dart';

/// Where an order has got to, one tap from the home page.
///
/// Sits beside the notification bell and behaves the same way, deliberately:
/// both are "something moved while you were away" chrome, and a pair of
/// controls that badge differently or open differently would read as two
/// unrelated things that happen to share a row.
///
/// Before this, orders were reachable from exactly one place -- Account, then
/// the Orders tile -- which is three taps for the question shoppers ask most
/// often while they are waiting for something.
class OrderTrackerButton extends StatelessWidget {
  const OrderTrackerButton({
    super.key,
    this.color,
    this.size = 24,
    this.onOpened,
    this.label,
  });

  /// The word to draw under the glyph, in the header's labelled group.
  ///
  /// Null keeps the bare [IconButton] this has always been, for every caller
  /// that is not that group. The destination, the badge and the answer for a
  /// guest are the same either way -- only the drawing differs, which is why
  /// this is a flag here rather than a second button somewhere else.
  final String? label;

  /// Pinned by the header, which draws this on the teal band where an
  /// inherited colour would vanish.
  final Color? color;

  /// The glyph size. See [SupportButton.size] -- the header's inset is derived
  /// from the same number.
  final double size;

  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Auth as well as orders: a guest and a customer get different
      // destinations from the same button, so it has to repaint when somebody
      // signs in without waiting for a navigation.
      listenable: Listenable.merge([OrderStore.instance, AuthStore.instance]),
      builder: (context, _) {
        final inFlight = OrderStore.instance.inFlightCount();
        final icon = inFlight > 0
            ? Icons.local_shipping
            : Icons.local_shipping_outlined;
        final tooltip = switch (inFlight) {
          0 => 'Your orders',
          1 => '1 order on the way',
          final n => '$n orders on the way',
        };

        if (label case final word?) {
          return HeaderActionTile(
            icon: icon,
            label: word,
            count: inFlight,
            tooltip: tooltip,
            color: color ?? AppColors.onPrimary,
            iconSize: size,
            onTap: () => _open(context),
          );
        }

        return IconButton(
          icon: Badge.count(
            count: inFlight,
            isLabelVisible: inFlight > 0,
            child: Icon(
              // Filled while something is on its way, outline when nothing is.
              // The same switch the bell makes, and for the same reason: the
              // state has to read without depending on the badge alone.
              icon,
              size: size,
              color: color,
            ),
          ),
          tooltip: tooltip,
          onPressed: () => _open(context),
        );
      },
    );
  }

  /// Where the button goes, drawn either way.
  void _open(BuildContext context) {
    onOpened?.call();
    // A guest has no orders, so sending them to the orders page would be a
    // promise of something that could never have anything in it for them. Same
    // call the Account tile makes.
    final destination = AuthStore.instance.isSignedIn
        ? const OrdersScreen()
        : const AuthScreen(initialMode: AuthMode.signIn);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => destination));
  }
}
