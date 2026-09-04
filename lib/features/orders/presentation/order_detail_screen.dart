import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../cart/data/cart_store.dart';
import '../../cart/widgets/cart_summary.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/order_store.dart';
import '../data/orders_repository.dart';
import '../widgets/order_request_sheets.dart';
import '../widgets/order_status_chip.dart';
import '../../../core/time_format.dart';
import '../widgets/order_timeline.dart';

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

        return Scaffold(
          appBar: AppBar(title: Text(order.displayReference)),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _StatusHeader(order: order, now: _now),
              _Section(
                title: 'Progress',
                child: OrderTimeline(order: order, now: _now),
              ),
              _TrackingSection(order: order, now: _now),
              _UpdatesSection(order: order),
              _Section(
                title: 'Items',
                child: Column(
                  children: [
                    for (final line in order.lines) _ItemRow(line: line),
                  ],
                ),
              ),
              _Section(
                title: 'Payment',
                child: _PaymentBlock(order: order),
              ),
              _Section(
                title: 'Delivery address',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.recipient,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.address,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'Order summary',
                child: CartSummary(totals: order.totals),
              ),
              // What has already been raised against this order, with the
              // shop's own status on it.
              for (final request in OrderStore.instance.requestsFor(order.id))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: OrderRequestCard(
                    request: request,
                    busy: _submitting,
                    // Only a pending cancellation can be taken back, which is
                    // the shop's own rule.
                    onWithdraw: !request.isReturn && request.status == 'pending'
                        ? () => _withdraw(request)
                        : null,
                  ),
                ),
              if (_action(order) case final action?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: OutlinedButton(
                    // Off while a request is in flight: two taps must not
                    // become two requests.
                    onPressed: _submitting ? null : action.onPressed,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: action.destructive
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : Text(action.label),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The one line a shopper opened this screen to read.
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.order, required this.now});

  final Order order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settled = order.isSettled(now);
    final outcome = order.outcome;

    final String detail;
    if (outcome == OrderOutcome.cancelled) {
      detail =
          'Cancelled ${formatWhen(order.outcomeAt ?? order.placedAt)}. '
          'Nothing will be delivered.';
    } else if (outcome == OrderOutcome.returned) {
      detail =
          'Return requested ${formatWhen(order.outcomeAt ?? order.placedAt)}. '
          'A courier will collect it.';
    } else if (outcome == OrderOutcome.failed) {
      detail = 'The payment did not go through, so this order was not placed.';
    } else {
      // The carrier's window, or an honest silence. A date invented here is
      // one the shop has not promised and cannot be held to.
      final eta = order.estimatedDelivery;
      if (settled) {
        detail = eta == null ? 'Delivered.' : 'Delivered ${formatWhen(eta)}.';
      } else if (eta == null) {
        detail = 'A delivery date will appear here once the courier has one.';
      } else if (order.isBehindSchedule) {
        detail = 'Running late. Now expected ${formatDay(eta)}.';
      } else {
        detail = order.deliveryIsEstimate
            ? 'Estimated to arrive ${formatDay(eta)}.'
            : 'Arriving ${formatDay(eta)}.';
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          color: theme.colorScheme.primary.withValues(alpha: 0.07),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OrderStatusChip(order: order, now: now),
            const SizedBox(height: 10),
            Text(
              detail,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

/// The carrier's running log of what has happened to this order.
///
/// `updates[]` has been decoded off the wire since tracking was added and was
/// never drawn -- the one part of the payload written as prose, thrown away
/// while the screen rendered six labels this app made up instead.
///
/// Newest first, verbatim. `type` chooses an icon and nothing else: an
/// unfamiliar type gets a neutral dot rather than being dropped, because the
/// carrier's vocabulary is the carrier's to grow.
class _UpdatesSection extends StatelessWidget {
  const _UpdatesSection({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updates = order.tracking?.updates ?? const <TrackingUpdate>[];
    final shown = updates.where((u) => u.title.isNotEmpty).toList()
      ..sort((a, b) {
        final left = a.at;
        final right = b.at;
        if (left == null || right == null) return 0;
        return right.compareTo(left);
      });

    if (shown.isEmpty) return const SizedBox.shrink();

    return _Section(
      title: 'Updates',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final update in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _icon(update.type),
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(update.title, style: theme.textTheme.bodyMedium),
                        // Only where the carrier timed it.
                        if (update.at != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            formatRelative(update.at!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static IconData _icon(String type) => switch (type.toLowerCase()) {
    'delivered' => Icons.check_circle_outline,
    'shipped' || 'transit' || 'dispatch' => Icons.local_shipping_outlined,
    'delay' || 'delayed' || 'exception' => Icons.error_outline,
    'cancelled' || 'cancel' => Icons.cancel_outlined,
    _ => Icons.circle_outlined,
  };
}

/// Courier and consignment number, once there is a parcel to track.
class _TrackingSection extends StatelessWidget {
  const _TrackingSection({required this.order, required this.now});

  final Order order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracking = order.trackingNumber(now);

    // Nothing has been handed to a courier yet, so there is nothing to track.
    // An empty "Tracking" heading would read as information that failed to
    // load rather than information that does not exist yet.
    if (tracking == null) return const SizedBox.shrink();

    return _Section(
      title: 'Tracking',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.local_shipping_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // Named by the carrier, or described plainly. Inventing a
                      // courier name would be a claim about who has the parcel.
                      order.courier ?? 'On its way',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tracking,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 18),
                tooltip: 'Copy tracking number',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: tracking));
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(content: Text('Tracking number copied')),
                    );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentBlock extends StatelessWidget {
  const _PaymentBlock({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = order.paymentState;
    final colour = switch (state) {
      PaymentState.paid => AppColors.successInk,
      PaymentState.failed => theme.colorScheme.error,
      PaymentState.pending => AppColors.warning,
      PaymentState.cashOnDelivery => theme.colorScheme.onSurfaceVariant,
    };

    return Row(
      children: [
        Icon(Icons.payments_outlined, size: 20, color: colour),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colour,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                state.detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text(
          formatRupees(order.totals.total),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: ArtworkPanel(
              icon: Icons.checkroom,
              tint: theme.colorScheme.primary,
              imageUrl: line.imageUrl,
              iconScale: 0.4,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (line.variantLabel != null) line.variantLabel!,
                    'Qty ${line.quantity}',
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatRupees(line.lineTotal),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
