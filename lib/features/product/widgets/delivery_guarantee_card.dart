import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/storefront_config.dart';

/// The shipping line on the product page: who carries it, and by when.
///
/// Replaces a card that read "Deliver to Lalitpur" over a **Change** button
/// wired to an empty callback -- a city nobody chose and a control that did
/// nothing.
///
/// Neutral by design. This is a fact about the order, not something to press,
/// so under the 60-30-10 rule it spends none of the orange: a hairline border,
/// the carrier in the foreground colour, the label muted and the dates picked
/// out in weight rather than in colour.
class DeliveryGuaranteeCard extends StatelessWidget {
  const DeliveryGuaranteeCard({super.key, required this.guarantee, this.now});

  final DeliveryGuarantee guarantee;

  /// The clock, injectable so a test can pin the window.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    if (!guarantee.enabled) return const SizedBox.shrink();
    final theme = Theme.of(context);

    final (from, to) = guarantee.windowFrom((now ?? DateTime.now)());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // Tinted rather than outlined, with the courier's own badge: the
      // delivery window is the one thing on this page a shopper checks before
      // the price, and the design gives it a ground of its own.
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  ),
                  child: Icon(
                    Icons.local_shipping_outlined,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Standard gtradea.com Logistics',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Wrap, not Row: at a large text size the label and the window
            // together are wider than a phone, and the dates are the half worth
            // keeping on one line.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Guaranteed delivery: ',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${_short(from)} – ${_short(to)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                _Explain(guarantee: guarantee),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "Sep 18". No year: both ends of the window are within weeks, and a year on
  /// a delivery date reads as a warning rather than as information.
  static String _short(DateTime date) =>
      '${_months[date.month - 1]} ${date.day}';

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

/// The ⓘ beside the window.
///
/// It is there because the window needs a caveat, and a caveat set in small
/// print under every product page is one nobody reads. Tapping says what the
/// dates are counted from -- which matters, because they are counted from today
/// rather than from the day the order ships.
class _Explain extends StatelessWidget {
  const _Explain({required this.guarantee});

  final DeliveryGuarantee guarantee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkResponse(
      radius: 18,
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Guaranteed delivery'),
          content: Text(
            'Imported orders clear customs before they are delivered, so the '
            'window is ${guarantee.weeksMin} to ${guarantee.weeksMax} weeks '
            'from today rather than a single date.\n\n'
            'It is an estimate for this route, not a quote for this order — '
            'freight is charged on delivery, as per actual.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
      child: Semantics(
        button: true,
        label: 'What guaranteed delivery means',
        child: Icon(
          Icons.info_outline,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
