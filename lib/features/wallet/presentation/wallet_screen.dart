import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time_format.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../../auth/data/auth_store.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/wallet_repository.dart';

/// Coins earned and spent.
///
/// Where the home page's Coins card goes. The balance and the movements are
/// the account's own -- `/wallet` is authenticated, so a signed-out shopper is
/// asked to sign in rather than shown a zero that means nothing.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  num _balance = 0;
  List<WalletEntry> _entries = const [];
  bool _loading = true;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (AuthStore.instance.account == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final balance = await WalletRepository.instance.balance();
      // The list is a nicety; a wallet that shows its balance and fails to
      // list history is still worth showing.
      final entries = await WalletRepository.instance.transactions().onError(
        (_, _) => const <WalletEntry>[],
      );
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _entries = entries;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coins')),
      body: _body(),
    );
  }

  Widget _body() {
    final theme = Theme.of(context);

    if (AuthStore.instance.account == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sign in to see the coins you have earned.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  await Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
                  if (mounted) unawaited(_load());
                },
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error case final failure?) {
      return LoadFailed(
        message: failure.isNetwork
            ? 'No connection, so your coins could not be loaded.'
            : failure.message,
        onRetry: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8EC),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.monetization_on, size: 40, color: _coinInk),
                const SizedBox(height: 10),
                Text(
                  formatRupees(_balance),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your balance',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Nothing has moved in or out yet.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            Text(
              'Activity',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final entry in _entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  entry.isCredit ? Icons.add_circle_outline : Icons.remove,
                  color: entry.isCredit
                      ? AppColors.successInk
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(entry.note.isEmpty ? 'Adjustment' : entry.note),
                subtitle: entry.at == null
                    ? null
                    : Text(formatDateHeading(entry.at!)),
                trailing: Text(
                  '${entry.isCredit ? '+' : ''}${formatRupees(entry.amount)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: entry.isCredit ? AppColors.successInk : null,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static const _coinInk = Color(0xFFD98A1E);
}
