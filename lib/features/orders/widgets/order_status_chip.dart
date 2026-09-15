import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../data/order_store.dart';
import 'order_status_colors.dart';

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
    final (mark, ink, icon) = _tone(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        // The status's own colour, as the ground and the edge.
        color: mark.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: mark.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: mark),
          const SizedBox(width: 5),
          Text(
            order.statusLabel(now),
            style: theme.textTheme.labelMedium?.copyWith(
              // The readable tone of the same colour: the one word that
              // says where an order is must not be the hardest thing on
              // the card to read.
              color: ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// The mark, the ink and the glyph for whatever state this order is in.
  (Color, Color, IconData) _tone(BuildContext context) {
    final theme = Theme.of(context);

    switch (order.outcome) {
      case OrderOutcome.cancelled:
        return (
          theme.colorScheme.error,
          theme.colorScheme.error,
          Icons.cancel_outlined,
        );
      case OrderOutcome.failed:
        return (
          theme.colorScheme.error,
          theme.colorScheme.error,
          Icons.error_outline,
        );
      case OrderOutcome.returned:
        return (
          AppColors.warning,
          AppColors.warning,
          Icons.assignment_return_outlined,
        );
      case null:
        break;
    }

    // The stage decides the colour; this only chooses the glyph.
    final stage = order.stage(now);
    final icon = switch (stage) {
      OrderStage.delivered => Icons.check_circle_outline,
      OrderStage.outForDelivery => Icons.local_shipping_outlined,
      OrderStage.shipped => Icons.local_shipping_outlined,
      OrderStage.packed => Icons.inventory_2_outlined,
      OrderStage.confirmed => Icons.task_alt,
      OrderStage.placed => Icons.receipt_long_outlined,
    };

    return (
      OrderStatusPalette.markFor(stage),
      OrderStatusPalette.inkFor(stage),
      icon,
    );
  }
}
