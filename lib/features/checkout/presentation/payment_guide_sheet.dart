import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import 'how_to_pay.dart';

/// One thing the checkout will not proceed without, and whether it is in hand.
///
/// Built from the checkout's own state -- see where it is constructed. A tick
/// here means the page really has the value; a Required means the page really
/// would refuse.
class GuideRequirement {
  const GuideRequirement({
    required this.label,
    required this.satisfied,
    this.value,
  });

  final String label;

  /// What is on file, when there is something and it is safe to show. Never a
  /// card number, a token or anything else that would be a leak to print --
  /// only what the shopper typed into this page themselves.
  final String? value;

  final bool satisfied;
}

/// What the guide is being told about the order it is explaining.
class PaymentGuideData {
  const PaymentGuideData({
    required this.current,
    required this.done,
    required this.requirements,
    required this.methods,
    required this.total,
    this.minOrder,
    this.selectedMethod,
  });

  final CheckoutStep current;
  final Set<CheckoutStep> done;

  /// Step one's fields, in the order the page asks for them.
  final List<GuideRequirement> requirements;

  /// The methods this shop actually accepts, as the server named them. Never
  /// a list this app made up.
  final List<String> methods;
  final String? selectedMethod;

  /// What the order comes to, and the floor the seller sets when there is one.
  final num total;
  final String? minOrder;
}

/// The payment guide, over the checkout.
///
/// Modelled on the coach-mark the reference shows: the page dimmed behind, one
/// rounded card, a close in a circle at its corner, and each instruction led
/// by its own mark. Set in the shop's own light theme rather than the
/// reference's dark one, and every figure in it is this order's.
class PaymentGuideSheet extends StatelessWidget {
  const PaymentGuideSheet({super.key, required this.data});

  final PaymentGuideData data;

  /// Opens it over whatever is on screen.
  static Future<void> show(BuildContext context, PaymentGuideData data) {
    return showDialog<void>(
      context: context,
      // The dim the reference has, so the page reads as paused behind it.
      barrierColor: Colors.black.withValues(alpha: 0.55),
      barrierLabel: 'How to pay',
      builder: (_) => PaymentGuideSheet(data: data),
    );
  }

  static const _radius = 22.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: ConstrainedBox(
          // Wide enough to read on a tablet, never wider than a column: the
          // steps are a list, and a list set across a desktop is unreadable.
          constraints: BoxConstraints(
            maxWidth: 460,
            maxHeight: media.size.height * 0.86,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(_radius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Header(current: data.current),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final step in CheckoutStep.values)
                              _Step(
                                step: step,
                                state: data.done.contains(step)
                                    ? CheckoutStepState.done
                                    : step == data.current
                                    ? CheckoutStepState.current
                                    : CheckoutStepState.waiting,
                                data: data,
                                last: step == CheckoutStep.values.last,
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        child: const Text('Got it'),
                      ),
                    ),
                  ],
                ),
              ),
              // The close, in its own circle at the corner, as the reference
              // has it.
              Positioned(
                top: -14,
                right: -6,
                child: Material(
                  color: theme.colorScheme.surface,
                  shape: const CircleBorder(),
                  elevation: 3,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Icon(
                        Icons.close,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The band across the top: what this is, and where the shopper is in it.
class _Header extends StatelessWidget {
  const _Header({required this.current});

  final CheckoutStep current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 46, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'How to pay',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Four steps, and the shop confirms the last one. '
            'You are on step ${current.number}.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// One step: its mark, its name, what it needs, and the rule joining it to the
/// next.
class _Step extends StatelessWidget {
  const _Step({
    required this.step,
    required this.state,
    required this.data,
    required this.last,
  });

  final CheckoutStep step;
  final CheckoutStepState state;
  final PaymentGuideData data;
  final bool last;

  static const _icons = {
    CheckoutStep.details: Icons.person_outline,
    CheckoutStep.payment: Icons.account_balance_wallet_outlined,
    CheckoutStep.review: Icons.receipt_long_outlined,
    CheckoutStep.confirm: Icons.lock_outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final done = state == CheckoutStepState.done;
    final current = state == CheckoutStepState.current;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done
                      ? primary
                      : current
                      ? primary.withValues(alpha: 0.10)
                      : theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: done || current
                        ? primary
                        : theme.colorScheme.outlineVariant,
                    width: 1.3,
                  ),
                ),
                child: Icon(
                  done ? Icons.check : _icons[step],
                  size: 19,
                  color: done
                      ? Colors.white
                      : current
                      ? primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: done
                        ? primary.withValues(alpha: 0.4)
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 4 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Step ${step.number} — ${step.title}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: current ? primary : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    step.detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._body(context, theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What this particular step has to say about this particular order.
  List<Widget> _body(BuildContext context, ThemeData theme) {
    switch (step) {
      case CheckoutStep.details:
        return [
          for (final requirement in data.requirements)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _RequirementRow(requirement: requirement),
            ),
        ];

      case CheckoutStep.payment:
        if (data.methods.isEmpty) {
          return [
            _Note(
              'The shop has not offered a method yet. Nothing can be paid '
              'until it does.',
            ),
          ];
        }
        return [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final method in data.methods)
                _Chip(label: method, filled: method == data.selectedMethod),
            ],
          ),
        ];

      case CheckoutStep.review:
        return [
          _Fact(label: 'Order amount', value: formatRupees(data.total)),
          if (data.minOrder != null)
            _Fact(label: 'Minimum order', value: data.minOrder!),
        ];

      case CheckoutStep.confirm:
        return [
          _Note(
            'Nothing is charged until you press the button, and the order is '
            'only paid when the shop says so. If a payment fails you are told '
            'why, with the order number.',
          ),
        ];
    }
  }
}

/// One required field: what it is, whether it is in hand, and what it holds.
class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.requirement});

  final GuideRequirement requirement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            requirement.satisfied
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            size: 15,
            color: requirement.satisfied
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: requirement.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // The asterisk the reference marks required fields with.
                TextSpan(
                  text: ' *',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.error,
                  ),
                ),
                if (requirement.value != null)
                  TextSpan(
                    text: '  ${requirement.value}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!requirement.satisfied) const RequiredTag(),
      ],
    );
  }
}

/// A figure the shopper is being asked to check.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the shop's methods, as the server named it.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.filled});

  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled
            ? primary.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(
          color: filled ? primary : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
          color: filled ? primary : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// A sentence of guidance under a step.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: 12,
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    );
  }
}
