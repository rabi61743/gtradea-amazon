import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/time_format.dart';
import '../data/order_store.dart';
import '../data/orders_repository.dart';
import 'order_status_colors.dart';

/// The parcel's progress, as the carrier reports it.
///
/// **One row per step the server sent**, in the server's own words. The server
/// works out which step is current and when each was reached; this draws that
/// and derives nothing. That matters because the carrier's vocabulary is its
/// own and grows: a step like `CUSTOMS_HELD` / "At customs" used to be decoded,
/// matched against a six-word client-side map, found nothing, and vanished --
/// the one state a shopper most needs to see was the one guaranteed to be
/// invisible.
///
/// The six-stage ladder this used to draw survives only as [_Fallback], for an
/// order placed on this device that the server has not read back yet. There is
/// no tracking for it because there is no carrier yet, and showing the shape of
/// the journey beats showing an empty box.
///
/// An order that left the happy path adds one final row for the departure --
/// Cancelled is not a step after Delivered, it is where the road ended.
class OrderTimeline extends StatelessWidget {
  const OrderTimeline({super.key, required this.order, required this.now});

  final Order order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = order.outcome;

    // A shipment with no steps has nothing to draw; one that has them is a leg
    // of the journey with its own progress.
    final shipments =
        order.tracking?.shipments
            .where((shipment) => shipment.timeline.isNotEmpty)
            .toList(growable: false) ??
        const [];

    final outcomeRow = outcome == null
        ? null
        : _TimelineRow(
            label: outcome.label,
            when: order.outcomeAt,
            done: true,
            isCurrent: true,
            isFirst: false,
            isLast: true,
            tone: outcome == OrderOutcome.returned
                ? AppColors.warning
                : theme.colorScheme.error,
          );

    if (shipments.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Fallback(order: order, now: now, hasOutcome: outcome != null),
          ?outcomeRow,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shipments.length; i++)
          _ShipmentBlock(
            shipment: shipments[i],
            // Named only when there is more than one. A single parcel needs no
            // heading saying it is the parcel.
            showHeading: shipments.length > 1,
            // The rail runs out at the bottom of the last leg, unless an
            // outcome row is about to continue it.
            isLastBlock: i == shipments.length - 1 && outcome == null,
            stopped: outcome != null,
            orderStage: order.stage(now),
          ),
        ?outcomeRow,
      ],
    );
  }
}

/// One leg of the journey: how it is travelling, what the carrier says about
/// it, and its own steps.
class _ShipmentBlock extends StatelessWidget {
  const _ShipmentBlock({
    required this.shipment,
    required this.showHeading,
    required this.isLastBlock,
    required this.stopped,
    required this.orderStage,
  });

  final TrackingShipment shipment;
  final bool showHeading;
  final bool isLastBlock;

  /// Where the order is overall, for colouring a carrier step whose own
  /// words map to none of the six stages.
  final OrderStage orderStage;

  /// The order was cancelled, returned or failed.
  final bool stopped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // On a stopped order the steps it never reached are dropped, not greyed.
    // They are not pending -- nothing is coming -- and a column of faint future
    // steps under "Cancelled" reads as a parcel still on its way.
    final steps = stopped
        ? shipment.timeline
              .where((step) => step.state != TrackingStepState.upcoming)
              .toList(growable: false)
        : shipment.timeline;

    // The carrier's own sentence about where this leg is. Shown above the
    // steps because it says more than any one step label can.
    final message = shipment.delayed
        ? (shipment.delayMessage ?? shipment.stageMessage)
        : shipment.stageMessage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeading) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  _icon(shipment.mode),
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    // The carrier's label, with its own reference beside it.
                    [
                      if (shipment.modeLabel.isNotEmpty) shipment.modeLabel,
                      if (shipment.shipmentNo.isNotEmpty) shipment.shipmentNo,
                    ].join(' · '),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (message != null && message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: shipment.delayed
                    ? AppColors.warning
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: shipment.delayed ? FontWeight.w600 : null,
              ),
            ),
          ),
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(
            // Verbatim. The carrier wrote it and knows its own states.
            label: steps[i].label,
            when: steps[i].reachedAt,
            done: steps[i].state == TrackingStepState.done,
            // The server decides this, not the app. A step marked current is
            // current even where a later one is already done.
            isCurrent: !stopped && steps[i].state == TrackingStepState.current,
            isFirst: i == 0,
            isLast: i == steps.length - 1 && isLastBlock,
            // The step's own stage colour where the carrier's word maps
            // to one of the six, and the order's current stage colour
            // where it does not -- a step like "At customs" is real
            // progress that the ladder has no name for.
            tone: OrderStatusPalette.markFor(
              Order.stageForStep(code: steps[i].stage, label: steps[i].label) ??
                  orderStage,
            ),
          ),
      ],
    );
  }

  static IconData _icon(String mode) => switch (mode.toLowerCase()) {
    'air' => Icons.flight_outlined,
    'sea' => Icons.directions_boat_outlined,
    'land' => Icons.local_shipping_outlined,
    _ => Icons.inventory_2_outlined,
  };
}

/// The shape of the journey, for an order the carrier has not picked up yet.
///
/// Reached only when the server has sent no shipment with steps -- typically an
/// order placed on this device and not yet read back. The labels are this app's
/// own, which is why they are confined to the one case where the server has
/// offered none of its own.
class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.order,
    required this.now,
    required this.hasOutcome,
  });

  final Order order;
  final DateTime now;
  final bool hasOutcome;

  @override
  Widget build(BuildContext context) {
    final reached = order.stage(now);

    // A failed order never got going, so showing five pending stages under it
    // would suggest a parcel that is on its way.
    final stages = order.outcome == OrderOutcome.failed
        ? const <OrderStage>[OrderStage.placed]
        : OrderStage.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < stages.length; i++)
          _TimelineRow(
            label: stages[i].label,
            when: order.whenStageReached(stages[i]),
            done: stages[i].index <= reached.index,
            isCurrent: stages[i] == reached && !hasOutcome,
            isFirst: i == 0,
            isLast: i == stages.length - 1 && !hasOutcome,
            // A stage the order never reached, on an order that stopped: the
            // rail below it is dead, not pending.
            dimmed: hasOutcome && stages[i].index > reached.index,
            // Each rung in its own status colour.
            tone: OrderStatusPalette.markFor(stages[i]),
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.label,
    required this.when,
    required this.done,
    required this.isCurrent,
    required this.isFirst,
    required this.isLast,
    this.dimmed = false,
    this.tone,
  });

  final String label;
  final DateTime? when;
  final bool done;
  final bool isCurrent;
  final bool isFirst;
  final bool isLast;
  final bool dimmed;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = tone ?? theme.colorScheme.primary;
    // Mountain Grey: what a step that has not happened looks like.
    const idle = OrderStatusPalette.upcoming;
    // The step in progress is coloured but not ticked. A carrier's "current"
    // means it is happening, and a tick against it would claim it had finished.
    final markerColour = (done || isCurrent) && !dimmed ? active : idle;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                // The rail above and below each marker, drawn as two halves so
                // the first and last rows have no stub hanging off the end.
                SizedBox(
                  height: 6,
                  child: isFirst
                      ? null
                      : Center(child: Container(width: 2, color: markerColour)),
                ),
                _Marker(
                  colour: markerColour,
                  filled: done && !dimmed,
                  pulsing: isCurrent,
                ),
                Expanded(
                  child: isLast
                      ? const SizedBox.shrink()
                      : Center(
                          child: Container(
                            width: 2,
                            // The rail takes the colour of the stage below it,
                            // so the line stops where progress stopped.
                            color: idle,
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
                      color: dimmed
                          ? theme.colorScheme.onSurfaceVariant
                          : (isCurrent ? active : null),
                    ),
                  ),
                  // Only where the carrier gave a time. A step it has not
                  // reached carries none, and the row says so by saying
                  // nothing rather than by predicting one.
                  if (when != null && !dimmed) ...[
                    const SizedBox(height: 2),
                    Text(
                      formatWhen(when!),
                      style: theme.textTheme.bodySmall?.copyWith(
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
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({
    required this.colour,
    required this.filled,
    required this.pulsing,
  });

  final Color colour;
  final bool filled;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: filled ? 16 : 12,
      height: filled ? 16 : 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? colour : Colors.transparent,
        border: Border.all(color: colour, width: 2),
      ),
      child: filled
          ? Icon(
              Icons.check,
              size: 10,
              color: Theme.of(context).colorScheme.onPrimary,
            )
          : null,
    );

    if (!pulsing) return dot;

    // A halo on the step the parcel is actually at. Static rather than
    // animated: a perpetual animation on a page that is otherwise still would
    // draw the eye away from the words, and it never settles for a test.
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colour.withValues(alpha: 0.18),
      ),
      child: dot,
    );
  }
}
