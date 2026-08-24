import 'package:flutter/foundation.dart';

import 'checkout_models.dart';

/// Where a payment has got to.
///
/// A sealed hierarchy rather than a status enum plus a bag of nullable fields:
/// the compiler then makes it impossible to render a success without an order,
/// or a failure without a reason, which are exactly the two mistakes a payment
/// screen must not make.
@immutable
sealed class PaymentOutcome {
  const PaymentOutcome();
}

/// Nothing has been attempted yet.
class PaymentIdle extends PaymentOutcome {
  const PaymentIdle();
}

/// The order is being created, or the gateway is being asked.
///
/// [message] says which, because the two take very different amounts of time
/// and a shopper watching a spinner deserves to know whether their money has
/// moved yet.
class PaymentInProgress extends PaymentOutcome {
  const PaymentInProgress(this.message);

  final String message;
}

/// Paid, or placed and payable on delivery. Either way, there is an order.
class PaymentSucceeded extends PaymentOutcome {
  const PaymentSucceeded({
    required this.order,
    required this.methodLabel,
    required this.payableNow,
    this.paidNow = true,
  });

  final PlacedOrder order;
  final String methodLabel;

  /// What the gateway was asked for. Not always the order total: the shop can
  /// collect an advance and the rest on delivery.
  final num payableNow;

  /// False for cash on delivery, where an order exists and no money has moved.
  final bool paidNow;
}

/// The gateway refused, or something between here and it broke.
class PaymentFailed extends PaymentOutcome {
  const PaymentFailed({
    required this.message,
    this.orderNumber,
    this.canRetry = true,
  });

  /// What went wrong, in words that say what to do next.
  final String message;

  /// Set when the order was created before the payment failed.
  ///
  /// It matters enormously: without it a shopper is told the payment failed and
  /// has no idea whether they now have an order. With it, the screen can say
  /// the order exists and can be paid from the order page.
  final String? orderNumber;

  /// False when retrying the same way cannot work -- a card the issuer
  /// declined, a gateway under review. The screen then offers another method
  /// instead of a button that will fail again.
  final bool canRetry;
}

/// The shopper backed out at the gateway.
///
/// Distinct from a failure on purpose. Nothing went wrong, nobody needs an
/// apology, and the wording should not imply either.
class PaymentCancelled extends PaymentOutcome {
  const PaymentCancelled({this.orderNumber});

  final String? orderNumber;
}
