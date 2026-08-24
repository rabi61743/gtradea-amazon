import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/order_store.dart';
import '../widgets/order_status_chip.dart';
import '../../../core/time_format.dart';
import 'order_detail_screen.dart';

/// Every order the shopper has placed, newest first.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    OrderStore.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OrderStore.instance,
      builder: (context, _) {
        final orders = OrderStore.instance.orders;

        return Scaffold(
          appBar: AppBar(title: const Text('Your orders')),
          body: RefreshIndicator(
            onRefresh: OrderStore.instance.refreshFromServer,
            child: orders.isEmpty
              ? ListView(children: const [SizedBox(height: 120), _NoOrders()])
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: orders.length,
                  itemBuilder: (context, i) => _OrderCard(
                    order: orders[i],
                    now: _now,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrderDetailScreen(orderId: orders[i].id),
                      ),
                    ),
                  ),
                ),
          ),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.now,
    required this.onTap,
  });

  final Order order;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totals = order.totals;
    final settled = order.isSettled(now);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.displayReference,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OrderStatusChip(order: order, now: now),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // One thumbnail per line, capped: three photos say what the
                  // order was, a dozen say nothing and cost a scroll.
                  for (final line in order.lines.take(3))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: ArtworkPanel(
                          icon: Icons.checkroom,
                          tint: theme.colorScheme.primary,
                          imageUrl: line.imageUrl,
                          iconScale: 0.4,
                        ),
                      ),
                    ),
                  if (order.lines.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusControl,
                          ),
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                        child: Text(
                          '+${order.lines.length - 3}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${totals.itemCount} '
                          '${totals.itemCount == 1 ? 'item' : 'items'} · '
                          '${formatRupees(totals.total)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Placed ${formatWhen(order.placedAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        // Only once the courier has actually given a date.
                        if (!settled && order.estimatedDelivery != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Arriving ${formatDay(order.estimatedDelivery!)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoOrders extends StatelessWidget {
  const _NoOrders();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No orders yet',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Anything you order will show up here, with tracking.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
