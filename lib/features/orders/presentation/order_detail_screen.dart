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

  Future<void> _confirmCancel(Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text(
          'It has not been dispatched yet, so it can still be stopped. This '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    // Between opening the dialog and confirming, the parcel may have shipped.
    // The store re-checks, and says so rather than silently doing nothing.
    // The server decides, not this screen: between opening the dialog and
    // confirming, the parcel may have gone out.
    final done = await OrderStore.instance.requestCancellation(order.id);
    if (!mounted) return;
    if (!done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            OrderStore.instance.error?.message ??
                'This order could not be cancelled',
          ),
        ),
      );
    }
  }

  Future<void> _requestReturn(Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Return this order?'),
        content: const Text(
          'A courier will collect it. Refunds are issued once it arrives back '
          'at the warehouse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Request return'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    final done = await OrderStore.instance.requestReturnFor(order.id);
    if (!mounted) return;
    if (!done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            OrderStore.instance.error?.message ??
                'This return could not be requested',
          ),
        ),
      );
    }
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
              if (order.canCancel(_now) || order.canReturn(_now))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: OutlinedButton(
                    onPressed: order.canCancel(_now)
                        ? () => _confirmCancel(order)
                        : () => _requestReturn(order),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: order.canCancel(_now)
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    child: Text(
                      order.canCancel(_now)
                          ? 'Cancel order'
                          : 'Request a return',
                    ),
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
