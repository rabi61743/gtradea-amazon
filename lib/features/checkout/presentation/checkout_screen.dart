import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/payment_strings.dart';
import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../address/data/address_store.dart';
import '../../address/presentation/address_picker_sheet.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/widgets/cart_summary.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../notifications/data/notification_store.dart';
import '../../orders/data/order_store.dart';
import '../../promo/data/coupon_store.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../data/checkout_models.dart';
import '../data/card_details.dart';
import '../data/checkout_repository.dart';
import '../data/payment_gateway.dart';
import '../data/payment_method.dart';
import '../data/payment_outcome.dart';
import '../data/payment_settings_repository.dart';
import '../data/saved_payment_store.dart';
import 'card_form_sheet.dart';
import 'payment_methods_section.dart';
import 'payment_pending_screen.dart';
import 'payment_result_screen.dart';
import 'payment_webview_screen.dart';

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
  /// The ways this shop currently accepts money. Empty until the server says.
  List<PaymentMethod> _methods = const [];
  PaymentMethod? _selected;
  bool _loadingMethods = true;
  ApiError? _methodsError;

  /// The saved card chosen, if any. Null means a card will be typed in.
  String? _selectedCardId;

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
      if (mounted) {
        setState(() => _address ??= AddressStore.instance.defaultAddress);
      }
    });
    SavedPaymentStore.instance.load();
    unawaited(_loadMethods());
  }

  /// Asks the shop which methods it takes.
  ///
  /// Not a fixed list in the app. Whether this storefront accepts cash on
  /// delivery this week is an operational decision, and offering a method the
  /// server has switched off means a shopper picks it, commits, and is refused
  /// by a gateway that was never going to accept them.
  Future<void> _loadMethods() async {
    try {
      final methods = await PaymentSettingsRepository.instance.methods();
      if (!mounted) return;

      final userId = AuthStore.instance.account?.id;
      final visible =
          methods.where((m) => m.isVisibleTo(userId)).toList(growable: false);

      setState(() {
        _methods = visible;
        _methodsError = null;
        _loadingMethods = false;
        _selected = visible.where((m) => m.isDefault).firstOrNull ??
            visible.firstOrNull;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _methodsError = e;
        _loadingMethods = false;
      });
    }
  }

  Future<void> _chooseAddress() async {
    final chosen = await AddressPickerSheet.show(
      context,
      selectedId: _address?.id,
    );
    if (chosen != null && mounted) setState(() => _address = chosen);
  }

  PaymentStrings get _strings => LanguageStore.instance.strings.payment;

  /// Runs the payment, whatever kind it is.
  Future<void> _pay() async {
    if (_placing) return;

    // An order with nowhere to go is not an order. Asked for rather than
    // guessed at, and the sheet opens straight away so the shopper is one step
    // from finishing rather than being told off.
    if (_address == null) {
      await _chooseAddress();
      if (!mounted || _address == null) return;
    }

    // The server holds the cart the order is built from, and it only holds one
    // for a signed-in shopper.
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

    final method = _selected;
    if (method == null) return;

    // A card is collected before anything is sent, so a mistyped number costs
    // a correction rather than a declined order.
    CardDetails? card;
    if (method.kind == PaymentKind.card && _selectedCardId == null) {
      final entry = await CardFormSheet.show(context, strings: _strings);
      if (!mounted || entry == null) return;
      card = entry.card;
      if (entry.remember) {
        // Only the brand, last four and expiry. Never the number, never the
        // security code -- see SavedPaymentMethod.
        SavedPaymentStore.instance.save(SavedPaymentMethod.fromCard(card));
      }
    }

    setState(() {
      _placing = true;
      _failure = null;
    });

    final outcome = ValueNotifier<PaymentOutcome>(
      PaymentInProgress(_strings.creatingOrder),
    );
    // Pushed before the work starts, so the loading state is a screen rather
    // than a spinner on a button the shopper is still looking past.
    final resultRoute = MaterialPageRoute<void>(
      builder: (_) => PaymentResultScreen(
        outcome: outcome,
        onRetry: () {
          Navigator.of(context).pop();
          unawaited(_pay());
        },
        onChooseAnother: () => Navigator.of(context).pop(),
        onDone: () {
          // Twice: off the result screen, then off the checkout behind it.
          // The order is placed, so there is nothing left to check out.
          Navigator.of(context).pop();
          Navigator.of(context).pop();
        },
      ),
    );
    unawaited(Navigator.of(context).push(resultRoute));

    try {
      await _submit(method, outcome, card);
    } finally {
      // The card leaves memory here whatever happened. Nothing writes it
      // anywhere, and holding it after the request is pointless risk.
      card = null;
      if (mounted) setState(() => _placing = false);
    }
  }

  Future<void> _submit(
    PaymentMethod method,
    ValueNotifier<PaymentOutcome> outcome,
    CardDetails? card,
  ) async {
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
      final isCod = method.kind == PaymentKind.cashOnDelivery;
      if (!isCod) {
        outcome.value = PaymentInProgress(_strings.contactingGateway);
      }

      final placed = isCod
          ? await CheckoutRepository.instance.placeCashOnDelivery(input)
          : await CheckoutRepository.instance.initiatePayment(method.id, input);

      await _afterOrder(placed);

      // Store credit can cover the whole thing, in which case there is no
      // gateway payload at all whichever method was chosen -- so this is
      // checked before reaching for one.
      if (isCod || placed.paidByWallet) {
        outcome.value = PaymentSucceeded(
          order: placed,
          methodLabel: method.label,
          payableNow: placed.advanceAmount ?? widget.totals.total,
          paidNow: !isCod,
        );
        return;
      }

      await _runGateway(method, placed, outcome);
    } on ApiError catch (e) {
      outcome.value = PaymentFailed(
        message: e.isNetwork
            ? 'No connection, so the order was not placed. Nothing has been '
                'charged.'
            : e.message,
      );
      if (mounted) setState(() => _failure = e.message);
    }
  }

  /// Sends the shopper to the provider and reports what came back.
  ///
  /// The order already exists at this point, which is why every failure below
  /// carries its number: a shopper who is told only that the payment failed
  /// cannot tell whether to order again, and ordering again is how people pay
  /// twice.
  Future<void> _runGateway(
    PaymentMethod method,
    PlacedOrder placed,
    ValueNotifier<PaymentOutcome> outcome,
  ) async {
    final orderNumber =
        placed.orderNumber.isEmpty ? null : placed.orderNumber;

    final gateway = PaymentGateway.forId(method.id);
    if (gateway == null) {
      // A method the shop enabled that this app has no handshake for. The
      // order stands and can be paid from the order page.
      outcome.value = PaymentFailed(
        message: '${method.label} cannot be completed in the app yet.',
        orderNumber: orderNumber,
        canRetry: false,
      );
      return;
    }

    final GatewayLaunch launch;
    try {
      launch = gateway.launch(placed);
    } on ApiError catch (e) {
      outcome.value = PaymentFailed(
        message: e.message,
        orderNumber: orderNumber,
        canRetry: false,
      );
      return;
    }

    if (!mounted) return;
    final returned = await PaymentWebViewScreen.show(
      context,
      title: method.label,
      redirectUrl: launch.url,
      actionUrl: launch.actionUrl,
      formFields: launch.formFields,
    );
    if (!mounted) return;

    GatewayVerdict? verdict;
    try {
      if (returned != null) {
        outcome.value = PaymentInProgress(_strings.creatingOrder);
        verdict = await gateway.confirm(placed, returned);
      } else {
        // Closed the page without coming back. That is not a refusal -- the
        // payment may have gone through in a banking app -- so the server is
        // asked rather than assumed.
        final probe = gateway.poll(placed) ??
            () => pollOrderPayment(placed.orderId);
        verdict = await PaymentPendingScreen.show(
          context,
          gatewayLabel: method.label,
          orderNumber: placed.orderNumber,
          poll: probe,
        );
      }
    } on ApiError catch (e) {
      outcome.value = PaymentFailed(
        message: e.message,
        orderNumber: orderNumber,
      );
      return;
    }

    if (!mounted) return;

    if (verdict == null) {
      // Gave up waiting. Nothing is known either way, so nothing is claimed.
      outcome.value = PaymentCancelled(orderNumber: orderNumber);
      return;
    }

    // Refresh before reporting: the order's own payment status is what the
    // rest of the app will show, and it should agree with this screen.
    await OrderStore.instance.refreshFromServer();
    NotificationStore.instance.syncFromOrders(OrderStore.instance.orders);

    if (verdict.paid) {
      outcome.value = PaymentSucceeded(
        order: placed,
        methodLabel: method.label,
        payableNow: placed.advanceAmount ?? widget.totals.total,
      );
      return;
    }

    if (verdict.abandoned) {
      outcome.value = PaymentCancelled(orderNumber: orderNumber);
      return;
    }

    outcome.value = PaymentFailed(
      message: verdict.underReview
          ? 'Your payment was received and is being checked. You will be '
              'notified once it clears -- do not pay again.'
          : (verdict.message ?? 'The payment did not go through.'),
      orderNumber: orderNumber,
      // Money has already been taken when a payment is under review. Offering
      // a retry would take it twice.
      canRetry: !verdict.underReview,
    );
  }

  /// Everything that follows an order existing.
  ///
  /// The notification comes from the order itself rather than being written
  /// here: payment notifications are derived from what the server says about
  /// an order, and a second path would announce a payment the server had not
  /// recorded.
  Future<void> _afterOrder(PlacedOrder placed) async {
    final code = widget.totals.couponCode;
    if (code != null) CouponStore.instance.redeem(code);

    // The server consumed the ordered rows, so this device's copy is stale.
    // Only the ordered lines are dropped: anything added from another screen
    // after checkout opened is not part of this order and must survive it.
    for (final line in widget.lines) {
      CartStore.instance.remove(line.key);
    }

    await OrderStore.instance.refreshFromServer();
    NotificationStore.instance.syncFromOrders(OrderStore.instance.orders);
  }

  /// Removing a saved card is confirmed. Putting it back means having the card
  /// to hand, which a shopper on a bus does not.
  Future<void> _confirmRemoveCard(SavedPaymentMethod card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_strings.removeCardConfirm),
        content: Text('${card.brand.label} ${card.maskedNumber}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_strings.done),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_strings.removeCard),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    SavedPaymentStore.instance.remove(card.id);
    if (mounted && _selectedCardId == card.id) {
      setState(() => _selectedCardId = null);
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
            title: _strings.title,
            child: _loadingMethods
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    ),
                  )
                : _methodsError != null
                    ? LoadFailed(
                        compact: true,
                        message: _methodsError!.isNetwork
                            ? 'No connection, so we could not check which '
                                'payment methods are available.'
                            : _methodsError!.message,
                        onRetry: _loadMethods,
                      )
                    : ListenableBuilder(
                        listenable: SavedPaymentStore.instance,
                        builder: (context, _) => PaymentMethodsSection(
                          strings: _strings,
                          methods: _methods,
                          selected: _selected,
                          enabled: !_placing,
                          onSelected: (method) => setState(() {
                            _selected = method;
                            // A card chosen for one method means nothing for
                            // another.
                            _selectedCardId = null;
                          }),
                          savedCards: SavedPaymentStore.instance.cards,
                          selectedCardId: _selectedCardId,
                          onCardSelected: (card) =>
                              setState(() => _selectedCardId = card.id),
                          onUseNewCard: () =>
                              setState(() => _selectedCardId = null),
                          onRemoveCard: _confirmRemoveCard,
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
                onRetry: _pay,
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
              onPressed: _placing ? null : _pay,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              // "Pay" when money is about to move, "Place order" when it is
              // not. A wallet button labelled "Place order" understates what
              // the next tap does.
              child: Text(
                '${_selected == null ||
                        _selected!.kind == PaymentKind.cashOnDelivery
                    ? _strings.placeOrder
                    : _strings.payNow}'
                ' · ${formatRupees(totals.total)}',
              ),
            ),
          ),
        ),
      ),
    );
  }
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

