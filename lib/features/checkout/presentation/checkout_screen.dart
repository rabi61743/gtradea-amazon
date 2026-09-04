import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/audio/app_sounds.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/payment_strings.dart';
import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../address/data/address_store.dart';
import '../../address/presentation/address_picker_sheet.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../cart/data/cart_store.dart';
import '../../profile/data/profile_store.dart';
import '../../cart/widgets/cart_summary.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../notifications/data/notification_store.dart';
import '../../orders/data/order_store.dart';
import '../../promo/data/coupon_store.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../../legal/presentation/terms_sheet.dart';
import 'bill_to_section.dart';
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
  const CheckoutScreen({super.key, required this.lines, required this.totals});

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

  /// Whether the shopper has agreed to the shop's terms.
  ///
  /// Starts false, always. `CheckoutOrderInput.termsAccepted` was hardcoded to
  /// `true` here, so every order this app has ever placed told the server the
  /// customer had accepted terms they were never shown and never asked about.
  bool _termsAccepted = false;

  /// Who the invoice is for.
  ///
  /// `CheckoutOrderInput` has sent `billingType`, `companyName` and `taxId` to
  /// the server since it was written, and nothing ever set them -- so every
  /// order, wholesale ones included, has been billed to an individual.
  bool _isBusiness = false;
  String _companyName = '';
  String _taxId = '';

  /// Set once an order has been attempted, so the company name is not marked
  /// wrong before it has been asked for.
  bool _billingAttempted = false;

  /// Whether the order summary is showing its line items.
  ///
  /// Closed to begin with. The lines are a recap of the cart a shopper has
  /// just come from; the payment choice below them is the thing they are here
  /// to make, and expanded lines push it off the screen.
  bool _summaryExpanded = false;

  /// A business invoice needs a name on it.
  bool get _billingReady => !_isBusiness || _companyName.trim().isNotEmpty;

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
    // For the phone the order needs. A shopper who came straight here from the
    // cart may never have opened Account, so the profile is not loaded yet;
    // this is a no-op when it already is.
    unawaited(ProfileStore.instance.load());
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
      final visible = methods
          .where((m) => m.isVisibleTo(userId))
          .toList(growable: false);

      setState(() {
        _methods = visible;
        _methodsError = null;
        _loadingMethods = false;
        _selected =
            visible.where((m) => m.isDefault).firstOrNull ??
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

    // Checked here as well as on the button. A rule that lives only in an
    // `onPressed` is one the next entry point walks straight around.
    if (!_billingReady) {
      setState(() => _billingAttempted = true);
      _say('Add the company name this invoice is for.');
      return;
    }

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
      await Navigator.of(context)
          .push<void>(MaterialPageRoute(builder: (_) => const AuthScreen()));
      if (!mounted) return;
      if (!AuthStore.instance.isSignedIn) {
        _say('Sign in to place this order.');
        return;
      }
    }

    final method = _selected;
    if (method == null) return;

    // Caught here rather than at the server, which answers "Phone is required"
    // and leaves the shopper with no idea where to put one -- no screen in the
    // checkout asks for it. Said before a card is collected or a gateway opens,
    // so nothing is charged against an order that cannot be created.
    if (_contactPhone().isEmpty) {
      setState(
        () => _failure =
            'Add a phone number in Account > Profile settings so the courier '
            'can reach you.',
      );
      return;
    }

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

  /// The number the order will carry: the address's own, or the account's.
  String _contactPhone() {
    final onAddress = _address?.phone.trim() ?? '';
    if (onAddress.isNotEmpty) return onAddress;
    return ProfileStore.instance.profile?.phone?.trim() ?? '';
  }

  Future<void> _submit(
    PaymentMethod method,
    ValueNotifier<PaymentOutcome> outcome,
    CardDetails? card,
  ) async {
    final input = CheckoutOrderInput(
      shippingAddress: CheckoutAddress.fromAddress(
        _address!,
        // The account's number, for an address saved without one. See the
        // factory: the server refuses an order that carries no phone.
        fallbackPhone: ProfileStore.instance.profile?.phone,
      ),
      // Only the lines this screen was handed. An empty list would mean
      // "everything in the cart", which is not what was on screen.
      selectedCartItemIds: [
        for (final line in widget.lines)
          if (line.serverId != null) line.serverId!,
      ],
      promoCode: widget.totals.couponCode,
      // The shopper's actual answer. The button cannot be pressed without it.
      termsAccepted: _termsAccepted,
      // Likewise: what they chose, not a default nobody was asked about.
      billingType: _isBusiness ? 'business' : 'individual',
      companyName: _isBusiness ? _companyName.trim() : null,
      taxId: _isBusiness ? _taxId.trim() : null,
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
    final orderNumber = placed.orderNumber.isEmpty ? null : placed.orderNumber;

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
        final probe =
            gateway.poll(placed) ?? () => pollOrderPayment(placed.orderId);
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
      // The provider confirmed it, which is the only thing that counts as
      // paid. A shopper who backed out, or whose money is still being
      // checked, does not reach this branch.
      unawaited(AppSounds.paymentSuccessful.play());
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

    // Refused, and not merely unfinished. Under review is money taken and
    // being checked, so it is not a failure to announce as one.
    if (!verdict.underReview) unawaited(AppSounds.paymentFailed.play());

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
    // The order exists and has a number: the server said so. Sounded here
    // rather than at the button, so it follows the result of the call and not
    // the tap -- and here rather than in the outcome, because this runs once
    // per order however the order is then paid for.
    unawaited(AppSounds.orderConfirmed.play());

    final code = widget.totals.couponCode;
    if (code != null) CouponStore.instance.redeem(code);

    // The server consumed the ordered rows, so this device's copy is stale.
    // Only the ordered lines are dropped: anything added from another screen
    // after checkout opened is not part of this order and must survive it.
    //
    // Silently: this is the app tidying up after an order, not the shopper
    // deleting anything, and a cart of six lines would otherwise fire six
    // removal sounds at the moment the order was confirmed.
    for (final line in widget.lines) {
      CartStore.instance.remove(line.key, announce: false);
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
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Checkout'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  // True of the app rather than a slogan: payment runs over the
                  // gateways, and no card number is ever stored here.
                  '100% Secure',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Section(
            title: 'Deliver to',
            icon: Icons.location_on_outlined,
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
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
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
            title: 'Bill To',
            icon: Icons.sell_outlined,
            child: BillToSection(
              isBusiness: _isBusiness,
              companyName: _companyName,
              taxId: _taxId,
              enabled: !_placing,
              showCompanyError: _billingAttempted,
              onChanged: (value) => setState(() {
                _isBusiness = value;
                if (!value) _billingAttempted = false;
              }),
              onCompanyName: (value) => setState(() => _companyName = value),
              onTaxId: (value) => _taxId = value,
            ),
          ),
          _Section(
            title: 'Order summary',
            icon: Icons.shopping_bag_outlined,
            // The reference puts a collapse control here, and it earns its
            // place: with the lines expanded, Payment -- which now sits below
            // this section -- is pushed off the bottom of a 412x915 phone
            // entirely. Measured: it was not even built. Collapsed by default,
            // so the section a shopper has to act on is reachable, and the
            // lines are one tap away for anyone who wants to check them.
            trailing: InkWell(
              onTap: () => setState(() => _summaryExpanded = !_summaryExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${totals.itemCount} '
                      '${totals.itemCount == 1 ? 'item' : 'items'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Icon(
                      _summaryExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            child: Column(
              children: [
                if (_summaryExpanded)
                  for (final line in widget.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The line's own photograph, off the field the cart
                          // has always carried. The same panel the cart tile
                          // and the order lines use, so a missing, slow or
                          // failed picture lands on the tinted icon rather than
                          // a broken-image glyph -- and smaller than any of
                          // them, because this block is two short lines of type
                          // rather than a row of its own.
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: ArtworkPanel(
                              icon: Icons.checkroom,
                              tint: theme.colorScheme.primary,
                              imageUrl: line.imageUrl,
                              iconScale: 0.4,
                              // Known here, so the panel skips the
                              // LayoutBuilder it would otherwise need to size
                              // its decode.
                              knownWidth: 44,
                            ),
                          ),
                          const SizedBox(width: 10),
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
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
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
          _Section(
            title: _strings.title,
            icon: Icons.account_balance_wallet_outlined,
            subtitle: 'Choose a secure payment option',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
            child: TermsAcceptance(
              accepted: _termsAccepted,
              enabled: !_placing,
              onChanged: (value) => setState(() => _termsAccepted = value),
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
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Total payable',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            formatRupees(totals.total),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          // The VAT already inside that figure, never added on
                          // top of it.
                          Text(
                            'Includes ${formatRupees(totals.vatIncluded.round())} VAT',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          // Gated on the terms. The field was already being
                          // sent to the server as `true`; now it is only true
                          // when somebody said so.
                          onPressed: (_placing || !_termsAccepted)
                              ? null
                              : _pay,
                          icon: const Icon(Icons.lock_outline, size: 18),
                          // "Pay" when money is about to move, "Place order"
                          // when it is not. A wallet button labelled "Place
                          // order" understates what the next tap does.
                          label: Text(
                            _selected == null ||
                                    _selected!.kind ==
                                        PaymentKind.cashOnDelivery
                                ? _strings.placeOrder
                                : _strings.payNow,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Three claims that are true of this app: payment runs over the
                // gateways, returns are a real flow, and every listing is the
                // supplier's own record.
                const _TrustRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One block of the checkout, as the reference draws them: a bordered card
/// with an icon, a heading, an optional sub-line, and an optional action on the
/// right.
///
/// The order these appear in is the requirement -- address, billing, summary,
/// payment -- so a shopper says where it goes and who it is billed to, sees
/// what it comes to, and only then chooses how to pay. There is a test on the
/// vertical positions, not on the widget list, so a reshuffle fails.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.icon,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final String? subtitle;

  /// A control on the right of the heading -- the summary's collapse toggle.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard + 2),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// The reassurance strip under the pay button.
///
/// Each of the three is something this app can stand behind: payment is handed
/// to Khalti, eSewa or a bank rather than collected here; returns are a real
/// flow with its own endpoint; and every listing is the supplier's own record
/// rather than a description written by the shop.
class _TrustRow extends StatelessWidget {
  const _TrustRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget mark(IconData icon, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );

    // Wrap, not Row: at a large text size three marks and their separators are
    // wider than a phone, and a second line beats shrinking them.
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 4,
      children: [
        mark(Icons.shield_outlined, 'Secure payments'),
        mark(Icons.autorenew, 'Easy returns'),
        mark(Icons.verified_outlined, 'Quality assured'),
      ],
    );
  }
}
