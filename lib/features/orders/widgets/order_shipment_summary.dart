import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../data/order_store.dart';
import '../data/orders_repository.dart';
import 'order_detail_cards.dart';
import 'order_status_colors.dart';

/// How many of an order's pieces are where.
///
/// Counted, never guessed. Where the server says which items travel in which
/// parcel -- [TrackingShipment.itemCount] -- each parcel's own stage decides
/// its bucket. Where it does not, every piece follows the order's own stage,
/// which is the server's aggregate answer rather than one worked out here.
class OrderItemTally {
  const OrderItemTally({
    required this.ordered,
    required this.delivered,
    required this.inTransit,
    required this.processing,
    required this.perParcel,
  });

  final int ordered;
  final int delivered;
  final int inTransit;
  final int processing;

  /// True when the split came from the server's own item assignment rather
  /// than from the order's overall stage.
  final bool perParcel;

  /// Which bucket a stage falls in.
  static ({bool delivered, bool inTransit}) _bucket(OrderStage stage) => (
    delivered: stage == OrderStage.delivered,
    inTransit:
        stage == OrderStage.shipped || stage == OrderStage.outForDelivery,
  );

  static OrderItemTally of(Order order, DateTime now) {
    final ordered = order.lines.fold<int>(
      0,
      (sum, line) => sum + line.quantity,
    );

    final shipments = order.tracking?.shipments ?? const <TrackingShipment>[];
    final counted = shipments.where((s) => (s.itemCount ?? 0) > 0).toList();

    // The server assigned items to parcels, so each parcel answers for its
    // own.
    if (counted.length == shipments.length && counted.isNotEmpty) {
      var delivered = 0;
      var inTransit = 0;
      var processing = 0;

      for (final shipment in counted) {
        final count = shipment.itemCount!;
        final stage = _stageOf(shipment) ?? order.stage(now);
        final bucket = _bucket(stage);
        if (bucket.delivered) {
          delivered += count;
        } else if (bucket.inTransit) {
          inTransit += count;
        } else {
          processing += count;
        }
      }

      return OrderItemTally(
        ordered: ordered,
        delivered: delivered,
        inTransit: inTransit,
        processing: processing,
        perParcel: true,
      );
    }

    // Nobody said which parcel holds what, so the order speaks for all of it.
    final bucket = _bucket(order.stage(now));
    return OrderItemTally(
      ordered: ordered,
      delivered: bucket.delivered ? ordered : 0,
      inTransit: bucket.inTransit ? ordered : 0,
      processing: bucket.delivered || bucket.inTransit ? 0 : ordered,
      perParcel: false,
    );
  }

  /// The furthest stage this parcel's own steps have reached.
  static OrderStage? _stageOf(TrackingShipment shipment) {
    OrderStage? furthest;
    for (final step in shipment.timeline) {
      if (step.state == TrackingStepState.upcoming) continue;
      final mapped = Order.stageForStep(code: step.stage, label: step.label);
      if (mapped == null) continue;
      if (furthest == null || mapped.index > furthest.index) furthest = mapped;
    }
    return furthest;
  }
}

/// The four counts, two by two, as the reference draws them.
class OrderCountsGrid extends StatelessWidget {
  const OrderCountsGrid({super.key, required this.order, required this.now});

  final Order order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final tally = OrderItemTally.of(order, now);
    if (tally.ordered == 0) return const SizedBox.shrink();

    final tiles = [
      (
        icon: Icons.shopping_bag_outlined,
        colour: AppColors.himalayanSlate,
        count: tally.ordered,
        label: tally.ordered == 1 ? 'Item Ordered' : 'Items Ordered',
      ),
      (
        icon: Icons.check_circle_outline,
        colour: OrderStatusPalette.markFor(OrderStage.delivered),
        count: tally.delivered,
        label: tally.delivered == 1 ? 'Item Delivered' : 'Items Delivered',
      ),
      (
        icon: Icons.local_shipping_outlined,
        colour: OrderStatusPalette.markFor(OrderStage.shipped),
        count: tally.inTransit,
        label: tally.inTransit == 1 ? 'Item in Transit' : 'Items in Transit',
      ),
      (
        icon: Icons.schedule,
        colour: OrderStatusPalette.markFor(OrderStage.outForDelivery),
        count: tally.processing,
        label: tally.processing == 1 ? 'Item Processing' : 'Items Processing',
      ),
    ];

    return OrderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeading(title: 'Order Summary'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              // Two across on a phone, four on anything wide enough to read
              // them in a row.
              final columns = constraints.maxWidth >= 560 ? 4 : 2;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final tile in tiles)
                    SizedBox(
                      width: width,
                      child: _CountTile(
                        icon: tile.icon,
                        colour: tile.colour,
                        count: tile.count,
                        label: tile.label,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.icon,
    required this.colour,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final Color colour;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
