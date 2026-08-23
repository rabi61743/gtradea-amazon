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
import '../widgets/order_status_chip.dart';
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
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    OrderStore.instance.load();
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// See OrdersScreen: the clock runs only while this order can still move.
  void _syncTicker() {
    final order = OrderStore.instance.byId(widget.orderId);
    if (order == null || order.isSettled(_now)) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _syncTicker();
    });
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
    final done = OrderStore.instance.cancel(order.id);
    if (!mounted) return;
    if (!done) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This order has already been dispatched'),
        ),
      );
    }
    _syncTicker();
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

    OrderStore.instance.requestReturn(order.id);
    if (mounted) _syncTicker();
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
            body: const Center(child: Text('This order is no longer available')),
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text(order.id)),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _StatusHeader(order: order, now: _now),
              _Section(
                title: 'Progress',
                child: OrderTimeline(order: order, now: _now),
              ),
              _TrackingSection(order: order, now: _now),
              _Section(
                title: 'Items',
                child: Column(
                  children: [
                    for (final line in order.lines)
                      _ItemRow(line: line),
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
                      order.canCancel(_now) ? 'Cancel order' : 'Request a return',
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
      detail = 'Cancelled ${formatWhen(order.outcomeAt ?? order.placedAt)}. '
          'Nothing will be delivered.';
    } else if (outcome == OrderOutcome.returned) {
      detail = 'Return requested ${formatWhen(order.outcomeAt ?? order.placedAt)}. '
          'A courier will collect it.';
    } else if (outcome == OrderOutcome.failed) {
      detail = 'The payment did not go through, so this order was not placed.';
    } else if (settled) {
      detail = 'Delivered ${formatWhen(order.estimatedDelivery)}.';
    } else {
      detail = 'Arriving ${formatDay(order.estimatedDelivery)}, by '
          '${formatWhen(order.estimatedDelivery).split(', ').last}.';
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
                      order.courier,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
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
      PaymentState.paid => AppColors.success,
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
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
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
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w700),
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
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
