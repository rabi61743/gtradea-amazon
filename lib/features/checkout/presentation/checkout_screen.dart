import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../auth/data/auth_store.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/widgets/cart_summary.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../orders/data/order_store.dart';
import '../../orders/presentation/order_detail_screen.dart';

/// Review and place the order.
///
/// The lines and totals arrive as constructor arguments rather than being read
/// back off [CartStore]: what is being paid for is what the shopper saw when
/// they tapped Checkout. If the cart changes in another screen while this one
/// is open, this order is unaffected -- which is the point.
///
/// **Nothing is submitted anywhere.** There is no orders API in this app; the
/// button empties the cart and confirms. The swap point is [_placeOrder].
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.lines,
    required this.totals,
  });

  final List<CartLine> lines;
  final CartTotals totals;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  _Payment _payment = _Payment.cashOnDelivery;
  bool _placing = false;

  static const _address = 'Lalitpur, Bagmati';

  Future<void> _placeOrder() async {
    if (_placing) return;
    setState(() => _placing = true);

    final account = AuthStore.instance.account;
    final order = OrderStore.instance.place(
      lines: widget.lines,
      // The delivery agreed now, frozen onto the order: changing the rule
      // later must not rewrite what this order cost.
      delivery: widget.totals.delivery,
      recipient: account?.displayName ?? 'Guest',
      address: _address,
      paymentState: _payment == _Payment.cashOnDelivery
          ? PaymentState.cashOnDelivery
          // Prepaid methods stay pending until a gateway says otherwise.
          // There is no gateway here, so claiming "Paid" would be a lie.
          : PaymentState.pending,
    );

    // Only the lines this screen was handed are cleared. Anything added to the
    // cart from another screen after checkout opened is not part of this order
    // and must survive it.
    for (final line in widget.lines) {
      CartStore.instance.remove(line.key);
    }

    if (!mounted) return;
    final track = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppColors.success, size: 40),
        title: const Text('Order placed'),
        content: Text(
          '${widget.totals.itemCount} '
          '${widget.totals.itemCount == 1 ? 'item' : 'items'} for '
          '${formatRupees(widget.totals.total)}. '
          '${_payment == _Payment.cashOnDelivery ? 'Pay the courier on delivery.' : 'Payment confirmation will follow.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Done'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Track order'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    // Back to wherever the shopper was before the cart: the order is done and
    // the cart behind this screen is now empty.
    Navigator.of(context).pop();

    if ((track ?? false) && mounted) {
      // Pushed after the pop so Back from tracking lands on the storefront
      // rather than on a checkout screen for an order already placed.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderDetailScreen(orderId: order.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totals = widget.totals;
    final account = AuthStore.instance.account;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Section(
            title: 'Deliver to',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account?.displayName ?? 'Guest',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _address,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (account == null) ...[
                  const SizedBox(height: 6),
                  // Guests can order -- cash on delivery does not need an
                  // account -- but they are told what signing in buys them
                  // rather than being blocked at the last step.
                  Text(
                    'Ordering as a guest. Sign in to track this order later.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _Section(
            title: 'Payment',
            child: RadioGroup<_Payment>(
              groupValue: _payment,
              onChanged: (value) =>
                  setState(() => _payment = value ?? _payment),
              child: Column(
                children: [
                  for (final option in _Payment.values)
                    RadioListTile<_Payment>(
                      value: option,
                      title: Text(option.label),
                      subtitle: Text(option.detail),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          ),
          _Section(
            title: 'Order summary',
            child: Column(
              children: [
                for (final line in widget.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                [
                                  if (line.variantLabel != null)
                                    line.variantLabel!,
                                  'Qty ${line.quantity}',
                                ].join(' · '),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          formatRupees(line.lineTotal),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 18),
                // The same widget the cart renders. If these two screens each
                // had their own version, they could disagree about the total
                // for one order, and a shopper who noticed would be right to
                // stop trusting both.
                CartSummary(totals: totals),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: ElevatedButton(
              onPressed: _placing ? null : _placeOrder,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text('Place order · ${formatRupees(totals.total)}'),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Payment {
  cashOnDelivery(
    'Cash on delivery',
    'Pay the courier when it arrives',
  ),
  esewa('eSewa', 'Pay now from your eSewa wallet'),
  card('Card', 'Visa or Mastercard');

  const _Payment(this.label, this.detail);

  final String label;
  final String detail;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

