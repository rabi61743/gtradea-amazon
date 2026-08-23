import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../data/order_store.dart';

/// The parcel's progress, one row per stage.
///
/// Every stage is listed whether or not it has happened, so a shopper can see
/// what is still to come rather than only how far it has got. Stages already
/// passed carry the time they happened; stages ahead carry when they are
/// expected, clearly marked as expected.
///
/// An order that left the happy path stops the rail at the stage it reached
/// and adds one final row for the departure -- Cancelled is not a seventh
/// stage after Delivered, it is where the road ended.
class OrderTimeline extends StatelessWidget {
  const OrderTimeline({super.key, required this.order, required this.now});

  final Order order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = order.outcome;
    final reached = order.stage(now);

    // A failed order never got going, so showing five pending stages under it
    // would suggest a parcel that is on its way.
    final stages = outcome == OrderOutcome.failed
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
            isExpected: stages[i].index > reached.index,
            isCurrent: stages[i] == reached && outcome == null,
            isFirst: i == 0,
            isLast: i == stages.length - 1 && outcome == null,
            // A stage the order never reached, on an order that stopped: the
            // rail below it is dead, not pending.
            dimmed: outcome != null && stages[i].index > reached.index,
          ),
        if (outcome != null)
          _TimelineRow(
            label: outcome.label,
            when: order.outcomeAt,
            done: true,
            isExpected: false,
            isCurrent: true,
            isFirst: false,
            isLast: true,
            tone: outcome == OrderOutcome.returned
                ? AppColors.warning
                : theme.colorScheme.error,
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
    required this.isExpected,
    required this.isCurrent,
    required this.isFirst,
    required this.isLast,
    this.dimmed = false,
    this.tone,
  });

  final String label;
  final DateTime? when;
  final bool done;
  final bool isExpected;
  final bool isCurrent;
  final bool isFirst;
  final bool isLast;
  final bool dimmed;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = tone ?? theme.colorScheme.primary;
    final idle = theme.colorScheme.outlineVariant;
    final markerColour = done && !dimmed ? active : idle;

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
                      : Center(
                          child: Container(width: 2, color: markerColour),
                        ),
                ),
                _Marker(colour: markerColour, filled: done && !dimmed, pulsing: isCurrent),
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
                  if (when != null && !dimmed) ...[
                    const SizedBox(height: 2),
                    Text(
                      isExpected
                          ? 'Expected ${formatWhen(when!)}'
                          : formatWhen(when!),
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
          ? Icon(Icons.check, size: 10, color: Theme.of(context).colorScheme.onPrimary)
          : null,
    );

    if (!pulsing) return dot;

    // A halo on the stage the parcel is actually at. Static rather than
    // animated: this screen already refreshes on a timer, and a pulse under a
    // rebuild loop reads as a flicker.
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

/// Dates the way a delivery is talked about: today and tomorrow by name, and
/// a short date otherwise. "Delivered on 23 Aug, 8:41 pm" is checkable in a
/// way that "2026-08-23T20:41:07" is not.
String formatWhen(DateTime when) {
  final now = DateTime.now();
  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  final difference = day.difference(today).inDays;

  final time = _time(when);
  if (difference == 0) return 'Today, $time';
  if (difference == 1) return 'Tomorrow, $time';
  if (difference == -1) return 'Yesterday, $time';
  return '${when.day} ${_months[when.month - 1]}, $time';
}

/// Just the day, for an estimate where the minute is false precision.
String formatDay(DateTime when) {
  final now = DateTime.now();
  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  final difference = day.difference(today).inDays;

  if (difference == 0) return 'today';
  if (difference == 1) return 'tomorrow';
  return '${when.day} ${_months[when.month - 1]}';
}

String _time(DateTime when) {
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${when.hour < 12 ? 'am' : 'pm'}';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
