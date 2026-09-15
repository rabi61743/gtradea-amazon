import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// The four things a shopper does to pay, in order.
///
/// Not a wizard: the checkout is one page and stays one page. This names the
/// stages that page already has, so a first-time buyer can see where they are
/// in it and what is still wanted from them.
enum CheckoutStep {
  details('Enter your details', 'Delivery address, phone and email.'),
  payment('Select payment', 'Choose one of the methods the shop accepts.'),
  review('Review your order', 'Check the items, the address and the total.'),
  confirm(
    'Confirm payment',
    'Agree the terms, then pay. We wait for the '
        'shop to confirm it.',
  );

  const CheckoutStep(this.title, this.detail);

  /// What the shopper is doing at this step.
  final String title;

  /// One line on what it needs. Short on purpose: a paragraph at checkout is
  /// a paragraph nobody reads.
  final String detail;

  int get number => index + 1;
}

/// Where a step stands.
enum CheckoutStepState { done, current, waiting }

/// The step strip, and the guide behind it.
///
/// Every state here is read from the checkout itself -- an address that is
/// really chosen, a phone that really validates, a method that is really
/// selected, terms really accepted. Nothing about it can say a step is done
/// when the page would refuse to place the order.
class HowToPay extends StatelessWidget {
  const HowToPay({
    super.key,
    required this.current,
    required this.done,
    required this.onOpenGuide,
  });

  /// The step the shopper is on.
  final CheckoutStep current;

  /// The steps already satisfied.
  final Set<CheckoutStep> done;

  /// Opens the full guide over the page.
  ///
  /// The strip is the summary -- where am I, how many left -- and the
  /// guide is the explanation. Unfolding the explanation in place pushed
  /// the payment methods down the page for everybody, including the
  /// shoppers who did not need it.
  final VoidCallback onOpenGuide;

  CheckoutStepState _stateOf(CheckoutStep step) {
    if (done.contains(step)) return CheckoutStepState.done;
    if (step == current) return CheckoutStepState.current;
    return CheckoutStepState.waiting;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.14),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpenGuide,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'How to pay',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'Step ${current.number} of ${CheckoutStep.values.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _Strip(stateOf: _stateOf),
          ),
        ],
      ),
    );
  }
}

/// The four marks in a row, joined by a rule.
class _Strip extends StatelessWidget {
  const _Strip({required this.stateOf});

  final CheckoutStepState Function(CheckoutStep) stateOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in CheckoutStep.values) ...[
          if (step != CheckoutStep.values.first)
            Expanded(
              child: Padding(
                // Level with the middle of the marks it joins.
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  height: 1.5,
                  color: stateOf(step) == CheckoutStepState.waiting
                      ? theme.colorScheme.outlineVariant
                      : theme.colorScheme.primary.withValues(alpha: 0.45),
                ),
              ),
            ),
          _Mark(step: step, state: stateOf(step)),
        ],
      ],
    );
  }
}

/// One numbered mark, with its short name under it.
class _Mark extends StatelessWidget {
  const _Mark({required this.step, required this.state});

  final CheckoutStep step;
  final CheckoutStepState state;

  static const _size = 24.0;

  /// One word each, so four fit across a phone -- and none of them repeats a
  /// section heading on the page: a mark labelled 'Payment' directly under
  /// the Payment heading reads as the heading twice.
  static const _short = {
    CheckoutStep.details: 'Details',
    CheckoutStep.payment: 'Method',
    CheckoutStep.review: 'Review',
    CheckoutStep.confirm: 'Confirm',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    final (Color fill, Color ink, Color border) = switch (state) {
      CheckoutStepState.done => (primary, Colors.white, primary),
      CheckoutStepState.current => (
        primary.withValues(alpha: 0.12),
        primary,
        primary,
      ),
      CheckoutStepState.waiting => (
        Colors.transparent,
        theme.colorScheme.onSurfaceVariant,
        theme.colorScheme.outlineVariant,
      ),
    };

    return Semantics(
      label: switch (state) {
        CheckoutStepState.done => '${step.title}, done',
        CheckoutStepState.current => '${step.title}, current step',
        CheckoutStepState.waiting => step.title,
      },
      child: SizedBox(
        width: 66,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _size,
              height: _size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(color: border, width: 1.4),
              ),
              child: state == CheckoutStepState.done
                  ? Icon(Icons.check, size: 14, color: ink)
                  : Text(
                      '${step.number}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
            ),
            const SizedBox(height: 5),
            Text(
              _short[step]!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                fontWeight: state == CheckoutStepState.current
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: state == CheckoutStepState.waiting
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small "Required" beside a field's name.
///
/// Says what the page will actually refuse to proceed without -- see the
/// checkout's own checks. A marker on a field that is not really required is
/// a lie the form tells about itself.
class RequiredTag extends StatelessWidget {
  const RequiredTag({super.key, this.satisfied = false});

  /// Whether the thing it marks has been supplied. A supplied requirement is
  /// drawn as met rather than as an outstanding demand.
  final bool satisfied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (satisfied) {
      return Icon(
        Icons.check_circle,
        size: 14,
        color: theme.colorScheme.primary,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Required',
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.error,
          height: 1.1,
        ),
      ),
    );
  }
}
