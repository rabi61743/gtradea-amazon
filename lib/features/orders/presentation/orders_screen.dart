import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/order_store.dart';
import '../widgets/order_document_button.dart';
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
    final store = OrderStore.instance;
    // The first visit loads, and loading fetches. Every visit after that has
    // to ask again: `load()` returns immediately once it has run, so an order
    // placed on the website after this session started never appeared here
    // until the app was restarted -- the list was not stale in the cache, it
    // was simply never asked for a second time.
    if (store.isLoaded) {
      // After this frame, not during it. refreshFromServer notifies its
      // listeners synchronously before its first await, and notifying while
      // the widget that asked is still building is what the framework refuses
      // -- load() only gets away with it because it reads the disk first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(store.refreshFromServer());
      });
    } else {
      store.load();
    }
    // Without this the rows show a status read off the bare order and no
    // arrival date at all -- the card has always been able to draw both, and
    // never had the data to.
    unawaited(OrderStore.instance.loadTrackingForVisible());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OrderStore.instance,
      builder: (context, _) {
        final orders = OrderStore.instance.orders;
        final error = OrderStore.instance.error;

        return Scaffold(
          appBar: AppBar(title: const Text('Your orders')),
          body: RefreshIndicator(
            // The carrier's view is refreshed with the orders, or a pull would
            // update the list and leave every arrival date as it was.
            onRefresh: () async {
              await OrderStore.instance.refreshFromServer();
              await OrderStore.instance.loadTrackingForVisible();
            },
            child: orders.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      // The store has always recorded why the fetch failed and
                      // this screen has never read it: a refused or unreachable
                      // account drew "No orders yet", which is not a loading
                      // state but a claim about the account -- and the one
                      // claim most likely to be wrong. Said plainly instead,
                      // with the way to try again.
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: LoadFailed(
                            message: error.isNetwork
                                ? 'No connection, so your orders could not be '
                                      'loaded. They are safe on your account.'
                                : 'Your orders could not be loaded: '
                                      '${error.message}',
                            onRetry: () => unawaited(
                              OrderStore.instance.refreshFromServer(),
                            ),
                          ),
                        )
                      else
                        const _NoOrders(),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: orders.length,
                    itemBuilder: (context, i) => _OrderCard(
                      order: orders[i],
                      now: _now,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              OrderDetailScreen(orderId: orders[i].id),
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
              // Straight from the list, without opening the order first.
              if (OrderDocumentButton.availableFor(order))
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: OrderDocumentButton(order: order, compact: true),
                  ),
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
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Anything you order will show up here, with tracking.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
