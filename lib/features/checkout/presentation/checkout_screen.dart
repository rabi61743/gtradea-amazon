import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../address/data/address_store.dart';
import '../../address/presentation/address_picker_sheet.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/widgets/cart_summary.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../orders/data/order_store.dart';
import '../../promo/data/coupon_store.dart';
import '../../orders/presentation/order_detail_screen.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../data/checkout_models.dart';
import '../data/checkout_repository.dart';

/// Review and place the order.
///
/// The lines and totals arrive as constructor arguments rather than being read
/// back off [CartStore]: what is being paid for is what the shopper saw when
/// they tapped Checkout. If the cart changes in another screen while this one
/// is open, this order is unaffected -- which is the point.
///
/// Placing an order is a real POST to /checkout. The figures shown are the
/// app's own, and the server recomputes them -- so what it returns is what is
/// actually charged, and this screen defers to it.
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

  /// Why the last attempt did not become an order. Shown on the screen rather
  /// than in a snack bar: this is the moment a shopper most needs to know what
  /// happened and whether they were charged.
  String? _failure;

  Address? _address;

  @override
  void initState() {
    super.initState();
    AddressStore.instance.load().then((_) {
      if (mounted) setState(() => _address ??= AddressStore.instance.defaultAddress);
    });
  }

  Future<void> _chooseAddress() async {
    final chosen = await AddressPickerSheet.show(
      context,
      selectedId: _address?.id,
    );
    if (chosen != null && mounted) setState(() => _address = chosen);
  }

  Future<void> _placeOrder() async {
    if (_placing) return;

    // An order with nowhere to go is not an order. Asked for rather than
    // guessed at, and the sheet opens straight away so the shopper is one
    // step from finishing rather than being told off.
    if (_address == null) {
      await _chooseAddress();
      if (!mounted || _address == null) return;
    }

    // The server holds the cart the order is built from, and it only holds one
    // for a signed-in shopper. Sending them to sign in beats a refusal from
    // the gateway that says nothing about what to do next.
    if (!AuthStore.instance.isSignedIn) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      if (!mounted) return;
      if (!AuthStore.instance.isSignedIn) {
        _say('Sign in to place this order.');
        return;
      }
    }

    setState(() {
      _placing = true;
      _failure = null;
    });

    final input = CheckoutOrderInput(
      shippingAddress: CheckoutAddress.fromAddress(_address!),
      // Only the lines this screen was handed. An empty list would mean
      // "everything in the cart", which is not what was on screen.
      selectedCartItemIds: [
        for (final line in widget.lines)
          if (line.serverId != null) line.serverId!,
      ],
      promoCode: widget.totals.couponCode,
      termsAccepted: true,
    );

    try {
      final placed = _payment == _Payment.cashOnDelivery
          ? await CheckoutRepository.instance.placeCashOnDelivery(input)
          : await CheckoutRepository.instance
              .initiatePayment(_gatewayFor(_payment), input);

      if (!mounted) return;

      // Store credit can cover the whole thing, in which case there is no
      // gateway payload at all whichever method was chosen -- so this is
      // checked before reaching for one.
      if (_payment != _Payment.cashOnDelivery && !placed.paidByWallet) {
        // The gateway handshake needs an in-app browser, which this build does
        // not carry yet. The order exists either way; saying so beats leaving
        // the shopper on a spinner.
        _finish(
          placed,
          message: 'Order ${placed.orderNumber} created. Finish paying from '
              'your order page.',
        );
        return;
      }

      _finish(
        placed,
        message: _payment == _Payment.cashOnDelivery
            ? 'Pay the courier when it arrives.'
            : 'Paid in full with store credit.',
      );
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _placing = false;
        _failure = e.isNetwork
            ? 'No connection, so the order was not placed. Nothing has been '
                'charged.'
            : e.message;
      });
    }
  }

  /// Which gateway path a chosen method maps to.
  String _gatewayFor(_Payment payment) => switch (payment) {
        _Payment.khalti => 'khalti',
        _Payment.esewa => 'esewa',
        _Payment.cashOnDelivery => 'cod',
      };

  /// Everything that happens once the server has an order.
  Future<void> _finish(PlacedOrder placed, {required String message}) async {
    // The code is spent. Done here rather than on apply, so a coupon tried and
    // abandoned is still available next time.
    final code = widget.totals.couponCode;
    if (code != null) CouponStore.instance.redeem(code);

    // The server consumed the ordered rows, so this device's copy of them is
    // stale. Only the ordered lines are dropped: anything added from another
    // screen after checkout opened is not part of this order and must survive
    // it -- which is exactly what clearing the whole cart would destroy.
    for (final line in widget.lines) {
      CartStore.instance.remove(line.key);
    }
    unawaited(OrderStore.instance.refreshFromServer());

    if (!mounted) return;
    setState(() => _placing = false);

    final track = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppColors.success, size: 40),
        title: Text(placed.orderNumber.isEmpty
            ? 'Order placed'
            : 'Order ${placed.orderNumber} placed'),
        content: Text(
          '${widget.totals.itemCount} '
          '${widget.totals.itemCount == 1 ? 'item' : 'items'} for '
          '${formatRupees(widget.totals.total)}. $message',
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

    if ((track ?? false) && mounted && placed.orderId.isNotEmpty) {
      // Pushed after the pop so Back from tracking lands on the storefront
      // rather than on a checkout screen for an order already placed.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderDetailScreen(orderId: placed.orderId),
        ),
      );
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
                if (_address == null)
                  // No address on file. Asked for before the order rather
                  // than after, and this is the only thing standing between
                  // the shopper and Place order.
                  OutlinedButton.icon(
                    onPressed: _chooseAddress,
                    icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                    label: const Text('Add a delivery address'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                  )
                else
                  InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    onTap: _chooseAddress,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _address!.label.icon,
                            size: 19,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _address!.fullName,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _address!.full,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                                if (_address!.phone.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    _address!.phone,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _chooseAddress,
                            child: const Text('Change'),
                          ),
                        ],
                      ),
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
          if (_failure != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: LoadFailed(
                compact: true,
                message: _failure!,
                onRetry: _placeOrder,
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
  khalti('Khalti', 'Pay now from your Khalti wallet');

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

