import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/network/api_error.dart';
import '../data/payment_gateway.dart';

/// Waits for a payment whose answer has to be asked for rather than caught.
///
/// The WebView normally catches the gateway's redirect and the verify runs
/// straight away. This screen is the other case: the shopper closed the page,
/// or the provider gives no server-to-server probe, so the only way to find out
/// is to keep asking the server whether the order has been paid.
///
/// It never declares a failure on its own. A payment that has not landed within
/// the window is unresolved, not refused, and telling someone their payment
/// failed while their bank is still processing it is how they end up paying
/// twice.
class PaymentPendingScreen extends StatefulWidget {
  const PaymentPendingScreen({
    super.key,
    required this.gatewayLabel,
    required this.orderNumber,
    required this.poll,
    this.interval = const Duration(seconds: 3),
    this.timeout = const Duration(minutes: 5),
  });

  final String gatewayLabel;
  final String orderNumber;

  /// Asks whoever can answer -- the provider, or the order itself.
  final Future<GatewayVerdict> Function() poll;

  final Duration interval;
  final Duration timeout;

  /// Returns the verdict once one arrives, or null if the shopper gave up.
  static Future<GatewayVerdict?> show(
    BuildContext context, {
    required String gatewayLabel,
    required String orderNumber,
    required Future<GatewayVerdict> Function() poll,
  }) {
    return Navigator.of(context).push<GatewayVerdict>(
      MaterialPageRoute(
        builder: (_) => PaymentPendingScreen(
          gatewayLabel: gatewayLabel,
          orderNumber: orderNumber,
          poll: poll,
        ),
      ),
    );
  }

  @override
  State<PaymentPendingScreen> createState() => _PaymentPendingScreenState();
}

class _PaymentPendingScreenState extends State<PaymentPendingScreen> {
  Timer? _timer;
  DateTime _startedAt = DateTime.now();
  int _attempts = 0;
  bool _checking = false;
  bool _gaveUp = false;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _timer = Timer.periodic(widget.interval, (_) => _check());
    // One immediate check as well: a wallet payment can already have landed by
    // the time this screen builds, and three seconds of spinner over a
    // finished payment is three seconds of doubt.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || _gaveUp || !mounted) return;

    if (DateTime.now().difference(_startedAt) >= widget.timeout) {
      _timer?.cancel();
      setState(() => _gaveUp = true);
      return;
    }

    setState(() {
      _checking = true;
      _attempts++;
    });

    try {
      final verdict = await widget.poll();
      if (!mounted) return;

      // Paid, or definitely not. Anything else is still in flight.
      final terminal =
          verdict.paid ||
          verdict.status == 'failed' ||
          verdict.status == 'fail' ||
          verdict.abandoned;

      if (terminal) {
        _timer?.cancel();
        Navigator.of(context).pop(verdict);
        return;
      }
    } on ApiError {
      // Expected while a gateway is mid-flight. A dropped poll is not a failed
      // payment, and stopping here would report one.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = LanguageStore.instance.strings.payment;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop();
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Waiting for ${widget.gatewayLabel}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.orderNumber.isEmpty
                        ? 'Finish the payment in the page that opened.'
                        : 'Order ${widget.orderNumber}. Finish the payment in '
                              'the page that opened.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  if (_gaveUp) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.07,
                        ),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.25,
                          ),
                        ),
                      ),
                      child: Text(
                        // Not "payment failed". If money left their account the
                        // order will settle on its own, and saying otherwise
                        // invites a second payment.
                        'We have not seen this payment yet. If money left your '
                        'account the order will update on its own -- check '
                        'your orders in a minute.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _checking ? null : _check,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(strings.tryAgain),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings.done),
                  ),
                  if (_attempts > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Checked $_attempts '
                      '${_attempts == 1 ? 'time' : 'times'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
