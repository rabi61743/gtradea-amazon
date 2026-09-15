import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../auth/data/auth_store.dart';
import '../data/order_store.dart';
import '../documents/order_document.dart';
import '../documents/order_document_saver.dart';

/// Download Invoice or Download Receipt, whichever the order's status calls
/// for.
///
/// The label reads the status the server last reported for this order; the
/// download itself reads it again from the server, so the file is always the
/// right one even if the order moved on while the page was open.
class OrderDocumentButton extends StatefulWidget {
  const OrderDocumentButton({
    super.key,
    required this.order,
    this.compact = false,
  });

  final Order order;

  /// The small version for a row in the orders list, rather than the card on
  /// the order's own page.
  final bool compact;

  /// An order only this device knows about has no server record to print.
  static bool availableFor(Order order) =>
      order.server != null && order.server!.id.isNotEmpty;

  @override
  State<OrderDocumentButton> createState() => _OrderDocumentButtonState();
}

class _OrderDocumentButtonState extends State<OrderDocumentButton> {
  bool _busy = false;

  OrderDocumentKind get _kind =>
      OrderDocumentKind.forStatus(widget.order.server?.status ?? '');

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);

    final messenger = ScaffoldMessenger.of(context);
    final noun = _kind.label.toLowerCase();
    String? message;

    try {
      final result = await OrderDocuments.download(
        widget.order.id,
        accountEmail: AuthStore.instance.account?.email,
      );
      // Null is the shopper closing the save dialog, which says nothing.
      if (result != null) {
        message = '${result.kind.label} saved as ${result.fileName}';
      }
    } on OrderDocumentUnavailable catch (e) {
      message = e.message;
    } on ApiError catch (e) {
      message = e.isNetwork
          ? 'No connection. The $noun could not be downloaded.'
          : e.message;
    } catch (_) {
      message = 'The $noun could not be created. Please try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (message != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = 'Download ${_kind.label.toLowerCase()}';
    final spinner = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Theme.of(context).colorScheme.primary,
      ),
    );

    if (widget.compact) {
      return TextButton.icon(
        onPressed: _busy ? null : _download,
        icon: _busy ? spinner : const Icon(Icons.download_rounded, size: 18),
        label: Text(_busy ? 'Preparing ${_kind.label.toLowerCase()}…' : label),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 40),
        ),
      );
    }

    final theme = Theme.of(context);
    final invoice = _kind == OrderDocumentKind.invoice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              invoice ? Icons.description_outlined : Icons.receipt_long_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _kind.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    invoice
                        ? 'A PDF of this delivered order, for your records.'
                        : 'This order is not complete yet, so a receipt is '
                              'available. The invoice follows on delivery.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _download,
          icon: _busy ? spinner : const Icon(Icons.download_rounded, size: 20),
          label: Text(
            _busy ? 'Preparing ${_kind.label.toLowerCase()}…' : label,
          ),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        ),
      ],
    );
  }
}
