import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../../product/data/product_detail_content.dart';
import '../../quotes/data/quote_repository.dart';
import '../../quotes/presentation/quote_request_detail_screen.dart';
import '../data/restock_requests.dart';

/// What the product page offers in place of its buy bar when nothing on it
/// can be bought: that it is unavailable, why, and "Notify sellers I want
/// this".
///
/// The request goes to the shop's team through their existing Product
/// requests queue (see [RestockRequests]); their answer comes back through the
/// existing notifications and on the request itself, which this bar opens once
/// it has been sent. Nothing here is shown as sent until the server took it.
class RestockRequestBar extends StatefulWidget {
  const RestockRequestBar({
    super.key,
    required this.product,
    required this.reason,
    this.variantLabel,
  });

  final ProductDetail product;

  /// Why it cannot be bought, in the page's own words.
  final String reason;

  /// The option wanted, where the page is showing one the customer chose.
  final String? variantLabel;

  @override
  State<RestockRequestBar> createState() => _RestockRequestBarState();
}

class _RestockRequestBarState extends State<RestockRequestBar> {
  /// Why the last send failed, shown above the button that retries it.
  String? _error;

  String get _productId => widget.product.numIid;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  /// Whether this account already asked for this product, read from the
  /// server so a request made yesterday, or on the website, shows as sent.
  Future<void> _check() async {
    if (!AuthStore.instance.isSignedIn) return;
    try {
      await RestockRequests.instance.refresh();
    } on ApiError {
      // The button still works: sending checks again before it posts.
    }
  }

  Future<void> _send() async {
    setState(() => _error = null);
    final product = widget.product;
    try {
      final request = await RestockRequests.instance.request(
        productId: _productId,
        title: product.title,
        imageUrl: product.images.isEmpty ? null : product.images.first,
        price: product.price > 0 ? formatRupees(product.price) : null,
        variantLabel: widget.variantLabel,
      );
      if (!mounted || request == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Request sent. You will be notified when the shop answers.',
            ),
          ),
        );
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.isNetwork
            ? 'No connection. Your request was not sent.'
            : e.isUnauthorized
            ? 'Your session has expired. Sign in again to send this.'
            : e.message;
      });
    }
  }

  Future<void> _signIn() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AuthScreen()));
    if (mounted) unawaited(_check());
  }

  void _open(QuoteRequest request) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuoteRequestDetailScreen(request: request),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([
        RestockRequests.instance,
        AuthStore.instance,
      ]),
      builder: (context, _) {
        final store = RestockRequests.instance;
        final signedIn = AuthStore.instance.isSignedIn;
        final existing = signedIn
            ? store.existingFor(
                productId: _productId,
                title: widget.product.title,
              )
            : null;
        final sending = store.isSending(_productId);
        final checking =
            signedIn && !store.isListed && store.listError == null && !sending;

        return SafeArea(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 18,
                        color: scheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Currently unavailable',
                                style: TextStyle(
                                  color: scheme.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: '  ${widget.reason}',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  if (_error != null && existing == null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: _button(
                      signedIn: signedIn,
                      existing: existing,
                      sending: sending,
                      checking: checking,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _button({
    required bool signedIn,
    required QuoteRequest? existing,
    required bool sending,
    required bool checking,
  }) {
    Widget label(String text) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1),
    );

    if (!signedIn) {
      return FilledButton.icon(
        onPressed: _signIn,
        icon: const Icon(Icons.login, size: 18),
        label: label('Sign in to notify sellers'),
      );
    }

    if (existing != null) {
      // Sent, and what has happened to it since -- straight from the server.
      final status = existing.status == QuoteStatus.pending
          ? 'Request sent'
          : 'Request sent · ${existing.statusLabel}';
      return Semantics(
        button: true,
        label: '$status. Opens your request.',
        excludeSemantics: true,
        child: OutlinedButton.icon(
          onPressed: () => _open(existing),
          icon: const Icon(Icons.check_circle, size: 18),
          label: label(status),
        ),
      );
    }

    if (sending || checking) {
      return FilledButton(
        onPressed: null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: label(sending ? 'Sending request...' : 'Checking...'),
            ),
          ],
        ),
      );
    }

    return FilledButton.icon(
      onPressed: _send,
      icon: const Icon(Icons.notifications_active_outlined, size: 18),
      label: label(
        _error != null ? 'Try again' : 'Notify sellers I want this',
      ),
    );
  }
}
