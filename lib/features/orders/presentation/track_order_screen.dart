import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../data/order_store.dart';
import 'order_detail_screen.dart';

/// Look up one order by the number printed on it.
///
/// Deliberately not a second tracking system. It searches the orders this
/// account already has -- refreshed from the server first, so the answer is
/// the server's and not a stale local copy -- and hands the one it finds to
/// [OrderDetailScreen], which is where this app has always shown a carrier's
/// view. Nothing here reimplements a stage, an ETA or a status label.
class TrackOrderScreen extends StatefulWidget {
  const TrackOrderScreen({super.key});

  @override
  State<TrackOrderScreen> createState() => _TrackOrderScreenState();
}

class _TrackOrderScreenState extends State<TrackOrderScreen> {
  final _number = TextEditingController();

  bool _searching = false;

  /// What the last search found, or null before one has been made.
  Order? _found;

  /// Why the last search found nothing. Null when it did, or before one.
  String? _problem;

  bool _searched = false;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _track() async {
    final typed = _number.text.trim();
    if (typed.isEmpty) {
      setState(() {
        _searched = true;
        _found = null;
        _problem = 'Enter the order number from your confirmation.';
      });
      return;
    }

    if (!AuthStore.instance.isSignedIn) {
      // The orders are the account's, so there is nothing to search until
      // there is an account. Sending them to sign in beats "not found", which
      // would be a lie.
      final signedIn = await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const AuthScreen()));
      if (signedIn != true || !mounted) return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searched = true;
      _problem = null;
      _found = null;
    });

    try {
      // The server's list, not the one this device happens to hold: an order
      // placed on the web, or on another phone, has to be findable here.
      await OrderStore.instance.refreshFromServer();
      final order = _match(typed);
      if (order != null) {
        // The carrier's view, fetched for the one order being asked about.
        await OrderStore.instance.loadTracking(order.id);
      }
      if (!mounted) return;

      // The store keeps a failed refresh rather than throwing, so that a
      // network blip does not wipe the orders screen. That means a lookup can
      // come back empty for two very different reasons, and saying "no such
      // order" when the list simply could not be read would send somebody
      // hunting for a number that is perfectly correct.
      final failure = OrderStore.instance.error;

      setState(() {
        _searching = false;
        _found = order == null ? null : OrderStore.instance.byId(order.id);
        if (order != null) {
          _problem = null;
        } else if (failure != null) {
          _problem = failure.isNetwork
              ? 'No connection, so your orders could not be checked.'
              : 'Your orders could not be checked just now. ${failure.message}';
        } else {
          _problem =
              'No order numbered "$typed" on this account. Check the number '
              'on your confirmation, or contact support.';
        }
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _problem = e.isNetwork
            ? 'No connection, so the order could not be looked up.'
            : e.message;
      });
    }
  }

  /// The order carrying this number.
  ///
  /// Matched on the printed reference and on the id, case and spacing
  /// forgiven -- somebody reading a number off a screen types it as they see
  /// it, and refusing "ord-20260830-2272" for its case would be pedantry.
  Order? _match(String typed) {
    final wanted = _key(typed);
    for (final order in OrderStore.instance.orders) {
      if (_key(order.displayReference) == wanted || _key(order.id) == wanted) {
        return order;
      }
    }
    return null;
  }

  static String _key(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s-]'), '');

  void _open(Order order) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final found = _found;

    return Scaffold(
      appBar: AppBar(title: const Text('Track order')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Text(
              'Enter your order number to see where it has got to.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _number,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => _track(),
              decoration: const InputDecoration(
                labelText: 'Order number',
                hintText: 'ORD-00000000-0000',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _searching ? null : _track,
                icon: _searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.local_shipping_outlined, size: 18),
                label: Text(_searching ? 'Looking...' : 'Track order'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            if (found != null) ...[
              const SizedBox(height: 18),
              _Result(order: found, onOpen: () => _open(found)),
            ] else if (_problem != null) ...[
              const SizedBox(height: 18),
              _Problem(_problem!),
            ] else if (!_searched) ...[
              const SizedBox(height: 18),
              _Hint(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Where the order has got to, in the server's own words.
class _Result extends StatelessWidget {
  const _Result({required this.order, required this.onOpen});

  final Order order;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The store's own label, which already folds in cancelled, delivered and
    // whatever the carrier last said. Reading those states again here would be
    // a second opinion that could disagree with the orders screen.
    final status = order.statusLabel();
    final tracking = order.tracking;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.displayReference,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              status,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (tracking != null && tracking.stageLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                tracking.stageLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                // Said out loud rather than left blank: an order the carrier
                // has not scanned yet is a normal state, not a failure.
                'No carrier updates yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onOpen,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('View order details'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'The number is on your order confirmation, and at the top of every '
            'order in My orders.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
