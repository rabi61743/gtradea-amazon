import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../data/order_store.dart';

/// The order's status as a coloured pill.
///
/// Colour carries meaning here, so it is never the only cue -- the label is
/// always spelled out. A shopper who cannot tell the amber from the green must
/// still be able to read "Out for delivery".
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.order, required this.now});

  final Order order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (colour, icon) = _tone(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colour.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colour),
          const SizedBox(width: 5),
          Text(
            order.statusLabel(now),
            style: theme.textTheme.labelMedium?.copyWith(
              color: colour,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  (Color, IconData) _tone(BuildContext context) {
    final theme = Theme.of(context);

    switch (order.outcome) {
      case OrderOutcome.cancelled:
        return (theme.colorScheme.error, Icons.cancel_outlined);
      case OrderOutcome.failed:
        return (theme.colorScheme.error, Icons.error_outline);
      case OrderOutcome.returned:
        return (AppColors.warning, Icons.assignment_return_outlined);
      case null:
        break;
    }

    return switch (order.stage(now)) {
      OrderStage.delivered => (
        AppColors.successInk,
        Icons.check_circle_outline,
      ),
      OrderStage.outForDelivery => (
        AppColors.inProgress,
        Icons.local_shipping_outlined,
      ),
      OrderStage.shipped => (AppColors.shipLand, Icons.local_shipping_outlined),
      OrderStage.packed => (AppColors.shipLand, Icons.inventory_2_outlined),
      OrderStage.confirmed => (theme.colorScheme.primary, Icons.task_alt),
      OrderStage.placed => (
        theme.colorScheme.primary,
        Icons.receipt_long_outlined,
      ),
    };
  }
}
