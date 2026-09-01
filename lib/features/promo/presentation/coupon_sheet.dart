import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../cart/data/cart_store.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/coupon.dart';
import '../data/coupon_store.dart';

/// Everything on offer, with the terms on the card rather than behind a link.
///
/// Each coupon is judged against the basket as it stands, so an offer that
/// cannot be used says why on its own card -- how much more to spend, what it
/// applies to, when it ran out. Listing offers a shopper cannot take and
/// letting them find out by tapping is the thing this avoids.
///
/// Returns the code to apply, or null if they backed out.
class CouponSheet extends StatelessWidget {
  const CouponSheet({super.key, required this.lines});

  final List<CartLine> lines;

  static Future<String?> show(
    BuildContext context, {
    required List<CartLine> lines,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CouponSheet(lines: lines),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = CouponStore.instance;

    // Usable first. An offers list that opens on three greyed-out cards reads
    // as "nothing for you" even when there is something.
    final offers = [...CouponContent.all]
      ..sort((a, b) {
        final aUsable = _refusalFor(a, store) == null;
        final bUsable = _refusalFor(b, store) == null;
        if (aUsable != bUsable) return aUsable ? -1 : 1;
        return a.expiresAt.compareTo(b.expiresAt);
      });

    return Material(
      color: theme.colorScheme.surface,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, controller) => Column(
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Offers for you',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Only one offer can be used per order',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                itemCount: offers.length,
                itemBuilder: (context, i) {
                  final coupon = offers[i];
                  final refusal = _refusalFor(coupon, store);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CouponCard(
                      coupon: coupon,
                      lines: lines,
                      refusal: refusal,
                      isApplied: store.applied?.code == coupon.code,
                      onApply: refusal != null
                          ? null
                          : () => Navigator.of(context).pop(coupon.code),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Why this offer cannot be taken right now, or null when it can.
  ///
  /// Runs the same rules the apply path runs, so a card that says "apply" and
  /// then refuses is not possible.
  CouponOutcome? _refusalFor(Coupon coupon, CouponStore store) {
    final existing = store.applied;
    if (existing != null &&
        existing.code != coupon.code &&
        (!existing.stackable || !coupon.stackable)) {
      return CouponConflict(existing);
    }
    if (coupon.hasExpired()) return CouponExpired(coupon);
    if (coupon.oncePerShopper && store.hasUsed(coupon.code)) {
      return CouponAlreadyUsed(coupon);
    }
    if (coupon.eligibleLines(lines).isEmpty) return CouponNotApplicable(coupon);

    final subtotal = lines.fold<num>(0, (sum, line) => sum + line.lineTotal);
    if (subtotal < coupon.minOrder) {
      return CouponBelowMinimum(coupon, coupon.minOrder - subtotal);
    }
    if (coupon.discountFor(lines) <= 0) return CouponNotApplicable(coupon);
    return null;
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard({
    required this.coupon,
    required this.lines,
    required this.refusal,
    required this.isApplied,
    required this.onApply,
  });

  final Coupon coupon;
  final List<CartLine> lines;
  final CouponOutcome? refusal;
  final bool isApplied;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usable = refusal == null;
    final tint = usable ? theme.colorScheme.primary : theme.colorScheme.outline;

    return Opacity(
      // Dimmed rather than hidden. A shopper who is Rs. 40 short should see
      // the offer they are 40 short of, not wonder where it went.
      opacity: usable ? 1 : 0.75,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(
            color: isApplied
                ? AppColors.successInk
                : tint.withValues(alpha: usable ? 0.45 : 0.3),
            width: isApplied ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _CodeChip(code: coupon.code, tint: tint),
                            const SizedBox(width: 8),
                            Text(
                              coupon.amountLabel,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: usable ? AppColors.successInk : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          coupon.headline,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    tooltip: 'Copy code',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: coupon.code));
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(content: Text('${coupon.code} copied')),
                        );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (coupon.minOrder > 0)
                    _Term(
                      icon: Icons.shopping_basket_outlined,
                      label: 'Min ${formatRupees(coupon.minOrder)}',
                    ),
                  if (coupon.maxDiscount != null && coupon.isPercentage)
                    _Term(
                      icon: Icons.vertical_align_top,
                      label: 'Up to ${formatRupees(coupon.maxDiscount!)}',
                    ),
                  _Term(
                    icon: Icons.category_outlined,
                    label: coupon.eligibleCategories.isEmpty
                        ? 'All departments'
                        : coupon.eligibleCategories.join(', '),
                  ),
                  _Term(
                    icon: Icons.event_outlined,
                    label: coupon.hasExpired()
                        ? 'Expired ${_date(coupon.expiresAt)}'
                        : 'Until ${_date(coupon.expiresAt)}',
                  ),
                  if (coupon.oncePerShopper)
                    const _Term(
                      icon: Icons.person_outline,
                      label: 'One per shopper',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: isApplied
                        ? Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                size: 15,
                                color: AppColors.successInk,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Applied',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.successInk,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          )
                        : refusal != null
                        ? Text(
                            _shortReason(refusal!),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.3,
                            ),
                          )
                        : Text(
                            'Saves ${formatRupees(coupon.discountFor(lines))} '
                            'on this order',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                  if (!isApplied)
                    TextButton(onPressed: onApply, child: const Text('Apply')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The card carries a short form; the full sentence belongs where the
  /// shopper acted, not on every card in a list.
  static String _shortReason(CouponOutcome outcome) => switch (outcome) {
    CouponExpired() => 'This offer has ended',
    CouponAlreadyUsed() => 'You have used this one',
    CouponBelowMinimum(:final shortfall) =>
      'Add ${formatRupees(shortfall)} more to use this',
    CouponNotApplicable(:final coupon) =>
      'Nothing from ${coupon.eligibleCategories.join(' or ')} in your cart',
    CouponConflict() => 'Remove the applied offer first',
    CouponUnknown() || CouponApplied() => '',
  };

  static String _date(DateTime when) {
    const months = [
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
    return '${when.day} ${months[when.month - 1]}';
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code, required this.tint});

  final String code;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: tint.withValues(alpha: 0.4),
          // Dashed would be prettier; a real border is what survives a
          // theme change and a screen reader.
        ),
      ),
      child: Text(
        code,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: tint,
        ),
      ),
    );
  }
}

class _Term extends StatelessWidget {
  const _Term({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
