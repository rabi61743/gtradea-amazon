import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../cart/data/cart_store.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/coupon.dart';
import '../data/coupon_store.dart';
import 'coupon_sheet.dart';

/// Enter a code, or go and look at what is on offer.
///
/// Sits in the cart rather than at checkout: the total it changes is the one
/// the shopper is looking at, and finding a discount only after committing to
/// pay is how people end up abandoning a basket to go hunting for codes.
///
/// Refusals are shown in place with the reason spelled out. A code refused
/// with "invalid" when the basket is forty rupees short is the message that
/// makes someone give up on a coupon that would have worked.
class PromoSection extends StatefulWidget {
  const PromoSection({super.key, required this.lines});

  final List<CartLine> lines;

  @override
  State<PromoSection> createState() => _PromoSectionState();
}

class _PromoSectionState extends State<PromoSection> {
  final _controller = TextEditingController();
  CouponOutcome? _outcome;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    CouponStore.instance.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply([String? code]) {
    final entered = code ?? _controller.text;
    if (entered.trim().isEmpty) return;

    final outcome = CouponStore.instance.apply(entered, widget.lines);
    setState(() => _outcome = outcome);

    if (outcome is CouponApplied) {
      _controller.clear();
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _browse() async {
    final chosen = await CouponSheet.show(context, lines: widget.lines);
    if (chosen != null && mounted) _apply(chosen);
  }

  void _remove() {
    CouponStore.instance.remove();
    setState(() => _outcome = null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CouponStore.instance,
      builder: (context, _) {
        final applied = CouponStore.instance.applied;

        return Card(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          // Flat, like the product lines above it. The theme lifts every Card
          // by 1, and a column of floating slips down the cart reads as a pile
          // rather than a page. The border and the corner stay: they are what
          // separates this block from the summary under it now.
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.local_offer_outlined,
                      size: 19,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Offers and coupons',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: _browse,
                      child: const Text('View offers'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (applied != null)
                  _AppliedRow(
                    coupon: applied,
                    discount: applied.discountFor(widget.lines),
                    onRemove: _remove,
                  )
                else
                  _CodeField(
                    controller: _controller,
                    expanded: _expanded,
                    onFocusChanged: (value) =>
                        setState(() => _expanded = value),
                    onSubmit: _apply,
                  ),
                if (_outcome != null && _outcome is! CouponApplied) ...[
                  const SizedBox(height: 10),
                  _Refusal(outcome: _outcome!),
                ],
                if (_outcome is CouponApplied) ...[
                  const SizedBox(height: 10),
                  _Success(outcome: _outcome! as CouponApplied),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.expanded,
    required this.onFocusChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool expanded;
  final ValueChanged<bool> onFocusChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            // Codes are upper case everywhere they are shown, so typing them
            // in lower case should not look like a different thing.
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              _UpperCaseFormatter(),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            onTap: () => onFocusChanged(true),
            decoration: const InputDecoration(
              hintText: 'Enter a promo code',
              isDense: true,
              prefixIcon: Icon(Icons.confirmation_number_outlined, size: 20),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Rebuilt on every keystroke so Apply is dead until there is something
        // to apply, rather than punishing a tap on an empty field.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : onSubmit,
            style: FilledButton.styleFrom(minimumSize: const Size(84, 44)),
            child: const Text('Apply'),
          ),
        ),
      ],
    );
  }
}

/// Codes read as upper case wherever they are shown, so the field matches.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

class _AppliedRow extends StatelessWidget {
  const _AppliedRow({
    required this.coupon,
    required this.discount,
    required this.onRemove,
  });

  final Coupon coupon;
  final num discount;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        color: AppColors.success.withValues(alpha: 0.10),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 19, color: AppColors.successInk),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coupon.code,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatRupees(discount)} off this order',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onRemove, child: const Text('Remove')),
        ],
      ),
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({required this.outcome});

  final CouponApplied outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        const Icon(
          Icons.celebration_outlined,
          size: 16,
          color: AppColors.successInk,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${outcome.coupon.code} applied. You saved '
            '${formatRupees(outcome.discount)}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.successInk,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// Why the code was not taken, in words that say what to do next.
class _Refusal extends StatelessWidget {
  const _Refusal({required this.outcome});

  final CouponOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message(outcome),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  /// Shared with the offers sheet, so a code refused by typing and the same
  /// code refused by tapping give the same reason.
  static String message(CouponOutcome outcome) => switch (outcome) {
    CouponUnknown(:final code) =>
      'We do not recognise "$code". Check the spelling, or pick one from '
          'the offers.',
    CouponExpired(:final coupon) =>
      '${coupon.code} expired on ${_date(coupon.expiresAt)}.',
    CouponAlreadyUsed(:final coupon) =>
      'You have already used ${coupon.code}. It is one per shopper.',
    CouponBelowMinimum(:final coupon, :final shortfall) =>
      'Spend ${formatRupees(shortfall)} more to use ${coupon.code}. '
          'It needs an order of ${formatRupees(coupon.minOrder)}.',
    CouponNotApplicable(:final coupon) =>
      '${coupon.code} only applies to '
          '${coupon.eligibleCategories.join(' and ')}, and there is none '
          'in your cart.',
    CouponConflict(:final existing) =>
      '${existing.code} is already on this order, and offers cannot be '
          'combined. Remove it first.',
    CouponApplied() => '',
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
