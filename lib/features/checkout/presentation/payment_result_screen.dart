import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/payment_strings.dart';
import '../../../core/theme/colors.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../orders/presentation/order_detail_screen.dart';
import '../data/payment_outcome.dart';

/// How a payment ended.
///
/// One screen for all four endings rather than a dialog for the happy one and
/// a snack bar for the rest. A shopper who has just moved money is owed a full
/// screen that says what happened, what it cost, and what to do next --
/// whichever of the four it was.
class PaymentResultScreen extends StatelessWidget {
  const PaymentResultScreen({
    super.key,
    required this.outcome,
    required this.onRetry,
    required this.onChooseAnother,
    required this.onDone,
  });

  /// Listened to rather than passed once, so the same screen carries the
  /// shopper from "creating your order" through to whatever it became. Pushing
  /// a second screen on top of a spinner would leave the spinner behind it.
  final ValueListenable<PaymentOutcome> outcome;

  /// Try the same method again. Absent from the screen when retrying cannot
  /// work.
  final VoidCallback onRetry;

  /// Go back and pick a different way to pay.
  final VoidCallback onChooseAnother;

  /// Finished. Leaves both this screen and the checkout behind it, because the
  /// order is placed and there is nothing left to check out.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final strings = LanguageStore.instance.strings.payment;
    final theme = Theme.of(context);

    return PopScope(
      // Backing out of a result screen leaves a shopper unsure what happened,
      // and out of a payment in flight is worse. The buttons are the way off.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ValueListenableBuilder<PaymentOutcome>(
              valueListenable: outcome,
              builder: (context, outcome, _) => SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: switch (outcome) {
                  PaymentIdle() => const SizedBox.shrink(),
                  PaymentInProgress(:final message) => _Working(
                    message: message,
                  ),
                  final PaymentSucceeded success => _Success(
                    outcome: success,
                    strings: strings,
                    theme: theme,
                    onDone: onDone,
                  ),
                  final PaymentFailed failed => _Failed(
                    outcome: failed,
                    strings: strings,
                    onRetry: onRetry,
                    onChooseAnother: onChooseAnother,
                  ),
                  final PaymentCancelled cancelled => _Cancelled(
                    outcome: cancelled,
                    strings: strings,
                    onRetry: onRetry,
                    onChooseAnother: onChooseAnother,
                  ),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Working extends StatelessWidget {
  const _Working({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 20),
        Text(
          // Names the step, because creating an order and asking a bank for
          // money take very different amounts of time and only one of them
          // means the money has started moving.
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({
    required this.outcome,
    required this.strings,
    required this.theme,
    required this.onDone,
  });

  final PaymentSucceeded outcome;
  final PaymentStrings strings;
  final ThemeData theme;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final order = outcome.order;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Emblem(icon: Icons.check_circle, colour: AppColors.successInk),
        const SizedBox(height: 16),
        Text(
          outcome.paidNow ? strings.paymentSuccessful : strings.orderPlaced,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          outcome.paidNow
              ? strings.paidWith(outcome.methodLabel)
              : strings.payOnDelivery,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        _OrderCard(
          orderNumber: order.orderNumber,
          amountLabel: outcome.paidNow
              ? strings.payableNow
              : strings.payableOnDelivery,
          amount: outcome.payableNow,
          remaining: order.remainingAmount,
          remainingLabel: strings.payableOnDelivery,
        ),
        const SizedBox(height: 24),
        if (order.orderId.isNotEmpty)
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => OrderDetailScreen(orderId: order.orderId),
              ),
            ),
            icon: const Icon(Icons.local_shipping_outlined, size: 19),
            label: Text(strings.trackOrder),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        const SizedBox(height: 8),
        TextButton(onPressed: onDone, child: Text(strings.done)),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.outcome,
    required this.strings,
    required this.onRetry,
    required this.onChooseAnother,
  });

  final PaymentFailed outcome;
  final PaymentStrings strings;
  final VoidCallback onRetry;
  final VoidCallback onChooseAnother;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Emblem(icon: Icons.error_outline, colour: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          // What actually happened. An order refused *before* payment is not a
          // failed payment: nothing was attempted and nothing was charged, and
          // "Payment failed" sends a shopper looking for a charge that was
          // never made -- or worse, ordering again to be sure.
          //
          // The order number is what tells the two apart. It is set only once
          // the order exists, which is only ever after the server accepted it.
          // Found in end-to-end testing: a cart line with no variant chosen is
          // refused by the server, and the screen called that a payment
          // failure.
          outcome.orderNumber == null
              ? strings.orderNotPlaced
              : strings.paymentFailed,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          outcome.message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
        // The most important sentence on this screen when it applies: whether
        // an order now exists. Without it a shopper cannot tell if they should
        // order again, and may pay twice.
        if (outcome.orderNumber != null) ...[
          const SizedBox(height: 16),
          _Note(text: strings.orderStillExists(outcome.orderNumber!)),
        ],
        const SizedBox(height: 24),
        if (outcome.canRetry)
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: Text(strings.tryAgain),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onChooseAnother,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text(strings.chooseAnother),
        ),
      ],
    );
  }
}

class _Cancelled extends StatelessWidget {
  const _Cancelled({
    required this.outcome,
    required this.strings,
    required this.onRetry,
    required this.onChooseAnother,
  });

  final PaymentCancelled outcome;
  final PaymentStrings strings;
  final VoidCallback onRetry;
  final VoidCallback onChooseAnother;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Not an error emblem. Nothing went wrong, and nobody is owed an
        // apology for changing their mind.
        _Emblem(
          icon: Icons.info_outline,
          colour: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          strings.paymentCancelled,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          strings.cancelledDetail,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
        if (outcome.orderNumber != null) ...[
          const SizedBox(height: 16),
          _Note(text: strings.orderStillExists(outcome.orderNumber!)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onRetry,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          child: Text(strings.tryAgain),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onChooseAnother,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text(strings.chooseAnother),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.orderNumber,
    required this.amountLabel,
    required this.amount,
    required this.remainingLabel,
    this.remaining,
  });

  final String orderNumber;
  final String amountLabel;
  final num amount;
  final String remainingLabel;
  final num? remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Column(
        children: [
          if (orderNumber.isNotEmpty) ...[
            Text(
              orderNumber,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
          ],
          _Line(label: amountLabel, value: formatRupees(amount), bold: true),
          // Shown only when the shop actually splits the payment. A "remaining:
          // Rs. 0" row invites a question that has no answer.
          if (remaining != null && remaining! > 0) ...[
            const SizedBox(height: 6),
            _Line(label: remainingLabel, value: formatRupees(remaining!)),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = bold
        ? theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800)
        : theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
      ),
    );
  }
}

class _Emblem extends StatelessWidget {
  const _Emblem({required this.icon, required this.colour});

  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colour.withValues(alpha: 0.12),
      ),
      child: Icon(icon, size: 46, color: colour),
    );
  }
}
