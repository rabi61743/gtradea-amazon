import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/time_format.dart';
import '../../cart/data/cart_store.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/order_store.dart';
import '../data/orders_repository.dart';
import 'order_status_colors.dart';

/// The cards the order page is built from.
///
/// One file because they share a shape -- white, 16-cornered, hairline-edged,
/// 14 inside -- and a shape kept in nine places drifts in nine directions.
/// Every one of them draws the order it is given and nothing else: there is no
/// state here and no fetching, so a card cannot show something the order does
/// not actually say.

/// The card every section on this page sits in.
class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.tinted = false,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Trust Blue at a fraction of its strength, for the one card that is a
  /// statement rather than a list.
  final bool tinted;

  static const radius = 16.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: tinted
              ? theme.colorScheme.primary.withValues(alpha: 0.05)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: tinted
                ? theme.colorScheme.primary.withValues(alpha: 0.14)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// A card's heading, with the link the reference puts opposite it.
class CardHeading extends StatelessWidget {
  const CardHeading({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The tinted card at the top: what is happening, and when it lands.
class OrderStatusHero extends StatelessWidget {
  const OrderStatusHero({super.key, required this.order, required this.now});

  final Order order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final outcome = order.outcome;
    final stage = order.stage(now);

    // The shop's own word for the state, never one invented here.
    final label = outcome?.label ?? stage.label;
    final headline = switch (outcome) {
      OrderOutcome.cancelled => 'This order was cancelled',
      OrderOutcome.returned => 'This order is being returned',
      OrderOutcome.failed => 'This order was not placed',
      null => switch (stage) {
        OrderStage.delivered => 'Your order has been delivered',
        OrderStage.outForDelivery => 'Your order is out for delivery',
        OrderStage.shipped => 'Your order is on its way',
        OrderStage.packed => 'Your order has been packed',
        OrderStage.confirmed => 'Your order is confirmed',
        OrderStage.placed => 'Your order is being processed',
      },
    };

    final eta = order.estimatedDelivery;

    // The stage decides the pill. An order that ended somewhere else keeps
    // the error and warning tones, which are about the ending rather than
    // about progress.
    final mark = outcome == null
        ? OrderStatusPalette.markFor(stage)
        : outcome == OrderOutcome.returned
        ? AppColors.warning
        : theme.colorScheme.error;
    final ink = outcome == null ? OrderStatusPalette.inkFor(stage) : mark;

    return OrderCard(
      tinted: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              outcome == null
                  ? Icons.inventory_2_outlined
                  : Icons.report_gmailerrorred_outlined,
              size: 24,
              color: primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: mark.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  headline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                if (eta != null && outcome == null) ...[
                  const SizedBox(height: 8),
                  Text(
                    order.deliveryIsEstimate
                        ? 'Estimated delivery'
                        : 'Delivered',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          formatDay(eta),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (order.isBehindSchedule) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Running behind the window the courier gave.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The six stages across the card, as the reference draws them.
///
/// The ladder is the app's own [OrderStage], which is what the reference
/// shows. The carrier's own words -- which grow, and which no six-word ladder
/// can hold -- are not lost: they are the updates card below, verbatim.
class OrderStageRail extends StatelessWidget {
  const OrderStageRail({super.key, required this.order, required this.now});

  final Order order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // An order that left the happy path has no onward stages: drawing Packed
    // and Shipped ahead of a cancelled order says it is still coming. The
    // hero above states where it actually ended.
    if (order.outcome != null) return const SizedBox.shrink();

    final reached = order.stage(now);
    final stages = OrderStage.values;

    return OrderCard(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Six nodes across a phone leaves about 55 points each, which is a
          // two-line label and no more.
          final cell = constraints.maxWidth / stages.length;

          return Column(
            children: [
              Row(
                children: [
                  for (final stage in stages) ...[
                    if (stage != stages.first)
                      Expanded(
                        child: Container(
                          height: 2,
                          // The line into a stage is that stage's own
                          // colour once it has been reached, and Mountain
                          // Grey while it has not.
                          color: stage.index <= reached.index
                              ? OrderStatusPalette.markFor(stage)
                              : OrderStatusPalette.upcoming,
                        ),
                      ),
                    _Node(
                      stage: stage,
                      reached: reached,
                      outcome: order.outcome,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final stage in stages)
                    SizedBox(
                      width: cell,
                      child: Column(
                        children: [
                          Text(
                            stage.label,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10.5,
                              height: 1.2,
                              fontWeight: stage == reached
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              // The stage the order is actually on is
                              // named in that status's own ink; the ones
                              // behind it stay in the page foreground so
                              // the current one is the prominent word.
                              color: stage == reached
                                  ? OrderStatusPalette.inkFor(stage)
                                  : stage.index < reached.index
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (order.whenStageReached(stage) case final at?) ...[
                            const SizedBox(height: 3),
                            Text(
                              formatDay(at),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 9.5,
                                height: 1.2,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({
    required this.stage,
    required this.reached,
    required this.outcome,
  });

  final OrderStage stage;
  final OrderStage reached;
  final OrderOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = stage.index < reached.index;
    final current = stage == reached;
    // Its own status colour once it is reached, Mountain Grey until then.
    final mark = done || current
        ? OrderStatusPalette.markFor(stage)
        : OrderStatusPalette.upcoming;

    return Semantics(
      label: done
          ? '${stage.label}, done'
          : current
          ? '${stage.label}, current'
          : stage.label,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // Filled once done, ringed while current, hollow until then --
          // so the stage the order is on is the one that stands out.
          color: done ? mark : theme.colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: mark, width: current ? 2 : 1.6),
        ),
        child: done
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : current
            ? Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(color: mark, shape: BoxShape.circle),
              )
            : Icon(
                _icons[stage],
                size: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
      ),
    );
  }

  static const _icons = {
    OrderStage.placed: Icons.receipt_long_outlined,
    OrderStage.confirmed: Icons.task_alt,
    OrderStage.packed: Icons.inventory_2_outlined,
    OrderStage.shipped: Icons.local_shipping_outlined,
    OrderStage.outForDelivery: Icons.delivery_dining_outlined,
    OrderStage.delivered: Icons.home_outlined,
  };
}

/// One thing a shopper can do about this order.
class OrderAction {
  const OrderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// The row of actions under the progress rail.
class OrderQuickActions extends StatelessWidget {
  const OrderQuickActions({super.key, required this.actions});

  final List<OrderAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (actions.isEmpty) return const SizedBox.shrink();

    return OrderCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final action in actions) ...[
              if (action != actions.first)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 12,
                  endIndent: 12,
                  color: theme.colorScheme.outlineVariant,
                ),
              Expanded(
                child: InkWell(
                  onTap: action.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 14,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          action.icon,
                          size: 21,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          action.label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the carrier has said lately, in its own words.
class OrderUpdatesCard extends StatelessWidget {
  const OrderUpdatesCard({
    super.key,
    required this.updates,
    required this.onViewAll,
  });

  final List<TrackingUpdate> updates;
  final VoidCallback? onViewAll;

  /// Two, as the reference shows. The rest are one tap away.
  static const shown = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (updates.isEmpty) return const SizedBox.shrink();

    // Newest first, whatever order the feed arrived in. What happened last is
    // what a shopper opened this card to read, and the server does not promise
    // an order here.
    final sorted = [...updates]
      ..sort((a, b) {
        final left = a.at, right = b.at;
        if (left == null || right == null) return 0;
        return right.compareTo(left);
      });
    final visible = sorted.take(shown).toList(growable: false);

    return OrderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(
            title: 'Latest updates',
            actionLabel: updates.length > shown ? 'View all' : null,
            onAction: updates.length > shown ? onViewAll : null,
          ),
          const SizedBox(height: 12),
          for (final update in visible)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 11,
                        height: 11,
                        margin: const EdgeInsets.only(top: 3),
                        decoration: BoxDecoration(
                          color: update == visible.first
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 1.4,
                          ),
                        ),
                      ),
                      if (update != visible.last)
                        Expanded(
                          child: Container(
                            width: 1.2,
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: update == visible.last ? 0 : 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            update.title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                          if (update.at case final at?) ...[
                            const SizedBox(height: 2),
                            Text(
                              formatWhen(at),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
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

/// What was ordered.
class OrderItemsCard extends StatelessWidget {
  const OrderItemsCard({
    super.key,
    required this.lines,
    required this.expanded,
    required this.onToggle,
    this.onBuyAgain,
  });

  final List<CartLine> lines;
  final bool expanded;
  final VoidCallback onToggle;

  /// Buying one line of the order again, on its own.
  ///
  /// Optional: this card is drawn in places that have nowhere to send such a
  /// tap, and a button that does nothing is worse than no button. Where it is
  /// given, the action sits beside the price rather than under it -- the row
  /// is already dense and this must not add a line of height to every item.
  final ValueChanged<CartLine>? onBuyAgain;

  /// One, as the reference shows, with the rest behind the link.
  static const compact = 1;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();

    final shown = expanded
        ? lines
        : lines.take(compact).toList(growable: false);
    final pieces = lines.fold<int>(0, (sum, line) => sum + line.quantity);

    return OrderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(
            title: 'Items ($pieces)',
            actionLabel: lines.length > compact
                ? (expanded ? 'Show less' : 'View all items')
                : null,
            onAction: lines.length > compact ? onToggle : null,
          ),
          const SizedBox(height: 10),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                for (final line in shown)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: line == shown.last ? 0 : 12,
                    ),
                    child: _ItemRow(line: line, onBuyAgain: onBuyAgain),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.line, this.onBuyAgain});

  final CartLine line;
  final ValueChanged<CartLine>? onBuyAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 62,
            height: 62,
            child: line.imageUrl == null
                ? Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Image.network(
                    line.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
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
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              if (line.variantLabel case final variant?) ...[
                const SizedBox(height: 3),
                Text(
                  variant,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 3),
              Text(
                'Qty: ${line.quantity}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatRupees(line.unitPrice * line.quantity),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            // Stacked under the figure it belongs to, inside the column that
            // was already there, so the row keeps its height.
            if (onBuyAgain case final buyAgain?) ...[
              const SizedBox(height: 2),
              TextButton.icon(
                key: const ValueKey('buy-again'),
                onPressed: () => buyAgain(line),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.commerceOrange,
                  textStyle: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: const Icon(Icons.refresh, size: 13),
                label: const Text('Buy again'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The legs of the journey, when the carrier splits an order across several.
class OrderShipmentsCard extends StatelessWidget {
  const OrderShipmentsCard({super.key, required this.shipments});

  final List<TrackingShipment> shipments;

  @override
  Widget build(BuildContext context) {
    // One parcel is the ordinary case, and the journey below already tells
    // its story step by step. A card listing a single shipment beside it says
    // the same thing twice; the reference shows this section for an order
    // split across several.
    if (shipments.length < 2) return const SizedBox.shrink();

    return OrderCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeading(title: 'Shipments'),
          const SizedBox(height: 10),
          for (final shipment in shipments)
            Padding(
              padding: EdgeInsets.only(
                bottom: shipment == shipments.last ? 0 : 10,
              ),
              child: _ShipmentRow(shipment: shipment),
            ),
        ],
      ),
    );
  }
}

class _ShipmentRow extends StatelessWidget {
  const _ShipmentRow({required this.shipment});

  final TrackingShipment shipment;

  static const _modes = {
    'air': Icons.flight,
    'sea': Icons.directions_boat_outlined,
    'land': Icons.local_shipping_outlined,
  };

  static const _tints = {
    'air': AppColors.shipAir,
    'sea': AppColors.shipSea,
    'land': AppColors.shipLand,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = _tints[shipment.mode] ?? theme.colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A summary of the parcel, not a second copy of its steps: those
          // are the journey below, in the carrier's own words, and one page
          // does not need two step lists.
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: shipment.delayed
                        ? theme.colorScheme.error.withValues(alpha: 0.10)
                        : tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _modes[shipment.mode] ?? Icons.inventory_2_outlined,
                    size: 19,
                    color: shipment.delayed ? theme.colorScheme.error : tint,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              shipment.shipmentNo.isEmpty
                                  ? 'Shipment'
                                  : shipment.shipmentNo,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (shipment.modeLabel.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                shipment.modeLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (shipment.itemCount case final count?) ...[
                        const SizedBox(height: 3),
                        Text(
                          '$count ${count == 1 ? 'Item' : 'Items'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (shipment.stageMessage case final message?) ...[
                        const SizedBox(height: 4),
                        Text(
                          message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: shipment.delayed
                                ? theme.colorScheme.error
                                : AppColors.successInk,
                          ),
                        ),
                      ],
                      if (shipment.etaFrom != null ||
                          shipment.etaTo != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          'ETA: ${_window(shipment)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (shipment.delayMessage case final delay?) ...[
                        const SizedBox(height: 3),
                        Text(
                          delay,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: theme.colorScheme.error,
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

  static String _window(TrackingShipment shipment) {
    final from = shipment.etaFrom;
    final to = shipment.etaTo;
    if (from != null && to != null) {
      return '${formatDay(from)} – ${formatDay(to)}';
    }
    return formatDay((from ?? to)!);
  }
}

/// What was paid, and how.
class OrderPaymentCard extends StatelessWidget {
  const OrderPaymentCard({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paid = order.paymentState == PaymentState.paid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Payment',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // Flexible, because the shop names its own states and "Cash on
            // delivery" is a long one to fit beside a six-figure total.
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: paid
                      ? AppColors.success.withValues(alpha: 0.14)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        // The shop's own word for it.
                        order.paymentState.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: paid
                              ? AppColors.successInk
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (paid) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.check_circle,
                        size: 13,
                        color: AppColors.successInk,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatRupees(order.totals.total),
              maxLines: 1,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        // What that state means, in the words the state itself carries --
        // "Payment received", "Pay the courier when it arrives".
        Text(
          order.paymentState.detail,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11.5,
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.3,
          ),
        ),
        if (order.server?.paymentMethod case final method?
            when method.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Method',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.credit_card,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  method,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Where it is going.
class OrderAddressCard extends StatelessWidget {
  const OrderAddressCard({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Delivery address',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          order.recipient,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        // The number this order actually went out with, which is not
        // necessarily the number on the account today.
        if (order.contactPhone case final phone?) ...[
          const SizedBox(height: 3),
          Text(
            phone,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 3),
        Text(
          order.address,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12.5,
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        if (order.country case final country?) ...[
          const SizedBox(height: 3),
          Text(
            country,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

/// The courier and the number it knows this parcel by.
///
/// Not in the reference, and kept anyway: it is the only thing on this page a
/// shopper can take to the courier's own website, and the page it replaced
/// showed it. Drawn only once something has actually been dispatched -- an
/// empty tracking row reads as information that failed to load.
class OrderTrackingCard extends StatelessWidget {
  const OrderTrackingCard({super.key, required this.order, required this.now});

  final Order order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = order.trackingNumber(now);
    if (number == null) return const SizedBox.shrink();

    return OrderCard(
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
                  order.courier ?? 'Tracking',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  number,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    color: theme.colorScheme.onSurfaceVariant,
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
