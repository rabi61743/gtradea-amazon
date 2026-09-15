import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/widgets/cart_summary.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/order_store.dart';
import '../data/orders_repository.dart';
import '../widgets/order_request_sheets.dart';
import '../widgets/order_detail_cards.dart';
import '../widgets/order_document_button.dart';
import '../widgets/order_shipment_summary.dart';
import '../widgets/order_timeline.dart';
import '../../support/presentation/support_tickets_screen.dart';
import 'track_order_screen.dart';
import 'reorder_sheet.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../checkout/presentation/checkout_screen.dart';

import 'package:share_plus/share_plus.dart';

/// One order: where it has got to, what is in it, and what was paid.
///
/// Takes an id rather than an [Order] so that cancelling or returning updates
/// this screen in place -- the store is the record, and a copy handed in at
/// push time would go stale the moment it changed.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  /// Whether the items card is showing everything it has.
  bool _allItems = false;

  /// Captured once, as on the list.
  ///
  /// There used to be a `Timer.periodic(1s)` here calling `setState` on the
  /// whole page for as long as an order was unsettled. It was left over from a
  /// build where the stage was derived from elapsed time; the stage now comes
  /// from the carrier, so the ticker rebuilt the timeline, every item row and
  /// every product image once a second in order to change nothing at all.
  final DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    OrderStore.instance.load();
    // The carrier's view is a separate request that fails on its own, so it is
    // asked for here rather than folded into the order fetch.
    unawaited(OrderStore.instance.loadTracking(widget.orderId));
  }

  /// True while a request is in flight, so nothing can be sent twice.
  bool _submitting = false;

  Future<void> _confirmCancel(Order order) async {
    if (_submitting) return;

    final draft = await CancelOrderSheet.show(context);
    if (draft == null || !mounted) return;

    setState(() => _submitting = true);
    // The server decides, not this screen: between opening the sheet and
    // confirming, the parcel may have gone out.
    final done = await OrderStore.instance.requestCancellation(
      order.id,
      reason: draft.reason,
      details: draft.details,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    _report(
      done,
      good: 'Cancellation requested. Our team will review it shortly.',
      bad: 'This order could not be cancelled',
    );
  }

  Future<void> _requestReturn(Order order) async {
    if (_submitting) return;

    final lines = [
      for (final item in order.server?.items ?? const <ServerOrderItem>[])
        (id: item.id, title: item.name, quantity: item.quantity),
    ];
    if (lines.isEmpty) {
      _report(false, good: '', bad: 'This order has nothing to return');
      return;
    }

    final draft = await ReturnRequestSheet.show(context, items: lines);
    if (draft == null || !mounted) return;

    setState(() => _submitting = true);
    final done = await OrderStore.instance.requestReturnFor(
      order.id,
      reason: draft.reason,
      details: draft.details,
      items: draft.items,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    _report(
      done,
      good: 'Return requested. We will email you once it is reviewed.',
      bad: 'This return could not be requested',
    );
  }

  Future<void> _withdraw(OrderRequest request) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final done = await OrderStore.instance.withdrawCancellation(request.id);
    if (!mounted) return;
    setState(() => _submitting = false);

    _report(
      done,
      good: 'Request withdrawn',
      bad: 'This request could not be withdrawn',
    );
  }

  /// The order number, on the clipboard.
  ///
  /// The one thing support asks for first, and the one thing that is hard
  /// to read off a screen and type into a chat correctly.
  void _copyReference(Order order) {
    Clipboard.setData(ClipboardData(text: order.displayReference));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Order number copied')));
  }

  /// Hands the order number to whatever the shopper shares with.
  ///
  /// The number and nothing else: an address, a phone number and a list of
  /// what somebody bought are not things to put on a clipboard bound for a
  /// group chat.
  Future<void> _shareOrder(Order order) async {
    await SharePlus.instance.share(
      ShareParams(
        text: 'My gtradea.com order ${order.displayReference}',
        subject: 'gtradea.com order ${order.displayReference}',
      ),
    );
  }

  /// The tracking screen, which is where the carrier's own words live.
  void _openTracking() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TrackOrderScreen()));
  }

  /// Support, through the app's own tickets rather than a mail link.
  void _openSupport() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SupportTicketsScreen()));
  }

  /// Puts this order back in the cart, once the catalogue has been asked.
  ///
  /// An order is the record of a purchase, not evidence about what is for sale
  /// today. This used to add the order's own lines straight to the cart, which
  /// meant a withdrawn product, a sold-out colourway or a price that had moved
  /// was discovered at checkout -- with the old figure already on screen and
  /// the goods apparently bought. Every line is checked first now, and what
  /// the catalogue said is shown before anything is added. See [ReorderSheet].
  Future<void> _reorder(Order order) => _openReorder(order.lines);

  /// The same, for one line of it: the shopper who wants the shoe cleaner
  /// again and none of the rest.
  Future<void> _buyAgain(CartLine line) =>
      _openReorder([line], title: 'Buy again');

  Future<void> _openReorder(
    List<CartLine> lines, {
    String title = 'Reorder',
  }) async {
    if (lines.isEmpty) return;

    final outcome = await ReorderSheet.show(
      context,
      lines: lines,
      title: title,
    );
    // Dismissed, or the screen went away while the sheet was open. Nothing was
    // added in either case: the sheet writes to the cart only on confirmation.
    if (outcome == null || !mounted) return;

    // Both ways out are the screens the rest of the app uses. Nothing here is
    // a checkout of this feature's own -- the cart, its totals, its coupon and
    // the server's recalculation are all the existing ones.
    if (outcome.checkout) {
      final store = CartStore.instance;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              CheckoutScreen(lines: store.lines, totals: store.totals),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CartScreen()),
    );
  }

  /// One place for both answers, so a failure always says the server's own
  /// words rather than a guess at what went wrong.
  void _report(bool done, {required String good, required String bad}) {
    final message = done ? good : OrderStore.instance.error?.message ?? bad;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Which action this order is up for, or none.
  ///
  /// Eligibility is the order's -- see [Order.canCancel] and
  /// [Order.canReturn] -- narrowed by what the shop already has in hand: an
  /// order awaiting a decision offers nothing further, and the server would
  /// refuse a second request anyway.
  ({String label, bool destructive, VoidCallback onPressed})? _action(
    Order order,
  ) {
    final store = OrderStore.instance;

    if (order.canCancel(_now)) {
      if (store.openRequestFor(order.id, isReturn: false) != null) return null;
      return (
        label: 'Cancel order',
        destructive: true,
        onPressed: () => _confirmCancel(order),
      );
    }
    if (order.canReturn(_now)) {
      if (store.openRequestFor(order.id, isReturn: true) != null) return null;
      return (
        label: 'Request a return',
        destructive: false,
        onPressed: () => _requestReturn(order),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OrderStore.instance,
      builder: (context, _) {
        final order = OrderStore.instance.byId(widget.orderId);

        if (order == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Order')),
            body: const Center(
              child: Text('This order is no longer available'),
            ),
          );
        }

        final requests = OrderStore.instance.requestsFor(order.id);
        final action = _action(order);
        final updates = order.tracking?.updates ?? const <TrackingUpdate>[];
        final shipments = order.tracking?.shipments ?? const [];

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Order Details'),
                // The number the shopper quotes to support, with the one
                // control that makes quoting it easy.
                InkWell(
                  onTap: () => _copyReference(order),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            order.displayReference,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.headset_mic_outlined),
                tooltip: 'Contact support',
                onPressed: _openSupport,
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (value) {
                  switch (value) {
                    case 'share':
                      _shareOrder(order);
                    case 'track':
                      _openTracking();
                    case 'copy':
                      _copyReference(order);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'share', child: Text('Share order')),
                  PopupMenuItem(value: 'track', child: Text('Track order')),
                  PopupMenuItem(
                    value: 'copy',
                    child: Text('Copy order number'),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
            children: [
              OrderStatusHero(order: order, now: _now),
              OrderStageRail(order: order, now: _now),
              OrderQuickActions(
                actions: [
                  OrderAction(
                    icon: Icons.location_on_outlined,
                    label: 'Track order',
                    onTap: _openTracking,
                  ),
                  OrderAction(
                    icon: Icons.ios_share,
                    label: 'Share order',
                    onTap: () => _shareOrder(order),
                  ),
                  OrderAction(
                    icon: Icons.headset_mic_outlined,
                    label: 'Contact support',
                    onTap: _openSupport,
                  ),
                ],
              ),
              OrderTrackingCard(order: order, now: _now),
              // The rail above is the six stages the reference draws. This is
              // the carrier's own step list, in the carrier's own words --
              // which grow, and which no six-word ladder can hold. A step like
              // "At customs" belongs to exactly one of these two, and it is
              // not the ladder.
              if (order.tracking?.timeline.isNotEmpty ?? false)
                OrderCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CardHeading(title: 'Journey'),
                      const SizedBox(height: 10),
                      OrderTimeline(order: order, now: _now),
                    ],
                  ),
                ),
              OrderUpdatesCard(updates: updates, onViewAll: _openTracking),
              OrderItemsCard(
                lines: order.lines,
                expanded: _allItems,
                onToggle: () => setState(() => _allItems = !_allItems),
                onBuyAgain: (line) => unawaited(_buyAgain(line)),
              ),
              // How many pieces are where, then the parcels themselves.
              OrderCountsGrid(order: order, now: _now),
              OrderShipmentsCard(shipments: shipments),
              // Side by side where there is room for two columns, stacked
              // where there is not: both carry a name and an address, and
              // squeezing those into half a phone wraps every line.
              LayoutBuilder(
                builder: (context, constraints) {
                  final payment = OrderPaymentCard(order: order);
                  final address = OrderAddressCard(order: order);
                  if (constraints.maxWidth < 520) {
                    return Column(
                      children: [
                        OrderCard(child: payment),
                        OrderCard(child: address),
                      ],
                    );
                  }
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: OrderCard(child: payment)),
                        Expanded(child: OrderCard(child: address)),
                      ],
                    ),
                  );
                },
              ),
              OrderCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: CardHeading(title: 'Order summary'),
                        ),
                        Text(
                          'All amounts in NPR',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 11.5,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    CartSummary(totals: order.totals),
                    if (order.discount > 0) ...[
                      const SizedBox(height: 12),
                      _SavedBanner(saved: order.discount),
                    ],
                  ],
                ),
              ),
              // What has already been raised against this order, with the
              // shop's own status on it.
              for (final request in requests)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: OrderRequestCard(
                    request: request,
                    busy: _submitting,
                    // Only a pending cancellation can be taken back, which
                    // is the shop's own rule.
                    onWithdraw: !request.isReturn && request.status == 'pending'
                        ? () => _withdraw(request)
                        : null,
                  ),
                ),
              // The paperwork: an invoice once the server says the order is
              // delivered, a receipt until then. Last on the page, so nothing
              // that was already here moves to make room for it.
              if (OrderDocumentButton.availableFor(order))
                OrderCard(child: OrderDocumentButton(order: order)),
            ],
          ),
          bottomNavigationBar: _OrderActionBar(
            busy: _submitting,
            action: action,
            onReorder: () => unawaited(_reorder(order)),
          ),
        );
      },
    );
  }
}

/// The two buttons the reference pins to the bottom of the page.
///
/// The left one is whatever this order is actually up for -- cancel, or a
/// return once it has arrived -- and is simply absent when it is up for
/// neither. The right one is always available: anything that was bought
/// once can be bought again.
class _OrderActionBar extends StatelessWidget {
  const _OrderActionBar({
    required this.busy,
    required this.action,
    required this.onReorder,
  });

  final bool busy;
  final ({String label, bool destructive, VoidCallback onPressed})? action;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(
            children: [
              if (action case final action?) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : action.onPressed,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: action.destructive
                          ? theme.colorScheme.error
                          : null,
                      side: BorderSide(
                        color: action.destructive
                            ? theme.colorScheme.error.withValues(alpha: 0.5)
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : Icon(
                            action.destructive
                                ? Icons.delete_outline
                                : Icons.assignment_return_outlined,
                            size: 18,
                          ),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(action.label, maxLines: 1),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onReorder,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Reorder', maxLines: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a coupon took off this order.
///
/// Drawn only when there is something to celebrate: "You saved Rs. 0" is a
/// banner about nothing.
class _SavedBanner extends StatelessWidget {
  const _SavedBanner({required this.saved});

  final num saved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.commerceOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.star, size: 15, color: AppColors.commerceOrange),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              'You saved ${formatRupees(saved)} on this order',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
