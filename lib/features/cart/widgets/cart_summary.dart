import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/cart_store.dart';

/// Subtotal, savings, delivery and total.
///
/// One widget used by both the cart and checkout. If the cart said "Free" and
/// checkout said "Rs. 0" for the same order, a shopper would stop trusting
/// both -- so the arithmetic lives in [CartTotals] and the wording lives here,
/// and neither screen is allowed its own version of either.
class CartSummary extends StatelessWidget {
  const CartSummary({super.key, required this.totals});

  final CartTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = totals.itemCount;

    // The goods, split into what they cost before tax and the tax inside them.
    // Both are read off CartTotals, which back-solves the VAT out of what is
    // actually charged rather than adding it on top -- the displayed prices
    // already include it, and adding it again would double-charge.
    final vat = totals.vatIncluded.round();
    final goods = totals.subtotal - totals.discount;

    return Column(
      children: [
        _SummaryRow(
          label: 'Product price (excl. VAT)',
          value: formatRupees(goods - vat),
        ),
        const SizedBox(height: 8),
        _SummaryRow(label: 'Product VAT (13%)', value: formatRupees(vat)),
        const SizedBox(height: 8),
        _SummaryRow(
          label: 'Subtotal ($items ${items == 1 ? 'item' : 'items'})',
          value: formatRupees(totals.subtotal),
        ),
        if (totals.savings > 0) ...[
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'You save',
            value: '-${formatRupees(totals.savings)}',
            valueColor: AppColors.successInk,
          ),
        ],
        if (totals.discount > 0) ...[
          const SizedBox(height: 8),
          _SummaryRow(
            // Named, because a discount line the shopper cannot trace back to
            // the code they typed reads as a mistake in the shop's favour.
            label: totals.couponCode == null
                ? 'Coupon'
                : 'Coupon ${totals.couponCode}',
            value: '-${formatRupees(totals.discount)}',
            valueColor: AppColors.successInk,
          ),
        ],
        const SizedBox(height: 8),
        // Three states, and the difference between the first two is the whole
        // point: a delivery of zero that nobody has quoted is not free, it is
        // unpriced. Freight is quoted by the server against the basket and its
        // destination, so a cart with no address yet has no figure to show --
        // and rendering that as "Free" would promise something checkout then
        // takes back.
        _SummaryRow(
          label: 'Delivery fee',
          value: !totals.deliveryQuoted
              ? 'Calculated at checkout'
              : totals.delivery == 0
              ? 'Free'
              : formatRupees(totals.delivery),
          valueColor: totals.deliveryQuoted && totals.delivery == 0
              ? AppColors.successInk
              : null,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1),
        ),
        _SummaryRow(
          label: 'Total',
          value: formatRupees(totals.total),
          emphasised: true,
        ),
        if (totals.vatIncluded >= 1) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            // Below the rule and out of the value column on purpose: it is a
            // note about the total, not another term of the sum. The prices
            // above already carry it, and adding it again would double-charge.
            child: Text(
              'Includes ${formatRupees(totals.vatIncluded)} VAT',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasised
                ? theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  )
                : theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
        Text(
          value,
          style: emphasised
              ? theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                )
              : theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
        ),
      ],
    );
  }
}
