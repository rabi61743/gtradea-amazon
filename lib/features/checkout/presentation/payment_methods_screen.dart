import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/payment_strings.dart';
import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loadable_view.dart';
import '../../auth/data/auth_store.dart';
import '../data/payment_method.dart';
import '../data/payment_settings_repository.dart';
import '../data/saved_payment_store.dart';

/// Saved cards, and what this shop accepts.
///
/// Reachable from account settings rather than only from checkout, because
/// removing a card is something people do calmly, long after buying anything.
///
/// A card cannot be added here. There is nothing to add: the details are only
/// ever collected at the moment of paying, and a card saved here would be four
/// digits and an expiry attached to no transaction. It appears in this list
/// once it has been used and the shopper asked us to remember it.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  List<PaymentMethod> _accepted = const [];
  bool _loading = true;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    SavedPaymentStore.instance.load();
    _loadAccepted();
  }

  Future<void> _loadAccepted() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final methods = await PaymentSettingsRepository.instance.methods();
      if (!mounted) return;
      final userId = AuthStore.instance.account?.id;
      setState(() {
        _accepted =
            methods.where((m) => m.isVisibleTo(userId)).toList(growable: false);
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

  PaymentStrings get _strings => LanguageStore.instance.strings.payment;

  Future<void> _confirmRemove(SavedPaymentMethod card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_strings.removeCardConfirm),
        content: Text('${card.brand.label} ${card.maskedNumber}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_strings.removeCard),
          ),
        ],
      ),
    );
    if (confirmed ?? false) SavedPaymentStore.instance.remove(card.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        SavedPaymentStore.instance,
        LanguageStore.instance,
      ]),
      builder: (context, _) {
        final cards = SavedPaymentStore.instance.cards;

        return Scaffold(
          appBar: AppBar(title: Text(_strings.manageTitle)),
          body: RefreshIndicator(
            onRefresh: _loadAccepted,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _GroupLabel(_strings.savedCards),
                if (cards.isEmpty)
                  const _NoCards()
                else
                  for (final card in cards)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CardRow(
                        card: card,
                        strings: _strings,
                        onRemove: () => _confirmRemove(card),
                      ),
                    ),
                const SizedBox(height: 8),
                _SecurityNote(text: _strings.securityNote),
                const SizedBox(height: 22),
                // What the shop takes, read from the server. Worth showing
                // here: someone checking their payment options should not have
                // to start a checkout to find out what is on offer.
                const _GroupLabel('Accepted at checkout'),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    ),
                  )
                else if (_error != null)
                  LoadFailed(
                    compact: true,
                    message: _error!.isNetwork
                        ? 'No connection, so we could not check which payment '
                            'methods are available.'
                        : _error!.message,
                    onRetry: _loadAccepted,
                  )
                else if (_accepted.isEmpty)
                  _Muted(text: _strings.noMethods)
                else
                  _AcceptedGroup(methods: _accepted),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One saved card. Removing is the only thing that can be done to it here.
class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.card,
    required this.strings,
    required this.onRemove,
  });

  final SavedPaymentMethod card;
  final PaymentStrings strings;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expired = card.isExpired();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: theme.dividerColor),
        color: theme.colorScheme.surface,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
            ),
            child: Icon(
              Icons.credit_card,
              size: 21,
              color: expired
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${card.brand.label} ${card.maskedNumber}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  card.holder.isEmpty
                      ? card.expiryLabel
                      : '${card.holder} · ${card.expiryLabel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                // Marked rather than hidden. Someone looking for a card they
                // saved should find it, and know why it cannot be used.
                if (expired) ...[
                  const SizedBox(height: 4),
                  Text(
                    strings.expired,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: strings.removeCard,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// The methods this shop takes, as one bordered card of rows.
class _AcceptedGroup extends StatelessWidget {
  const _AcceptedGroup({required this.methods});

  final List<PaymentMethod> methods;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: theme.dividerColor),
        color: theme.colorScheme.surface,
      ),
      child: Column(
        children: [
          for (var i = 0; i < methods.length; i++) ...[
            if (i > 0) Divider(height: 1, color: theme.dividerColor),
            ListTile(
              leading: Icon(
                methods[i].kind.icon,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(
                methods[i].label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: methods[i].description.isEmpty
                  ? null
                  : Text(methods[i].description),
              trailing: methods[i].badge == null
                  ? null
                  : Text(
                      methods[i].badge!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoCards extends StatelessWidget {
  const _NoCards();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          Icon(
            Icons.credit_card_off_outlined,
            size: 34,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            'No saved cards',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            // Says where a card comes from, because there is deliberately no
            // Add button here: a card is saved at the moment it is used.
            'When you pay by card you can ask us to remember it, and it will '
            'appear here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.lock_outline,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Matches the section headings on the account page.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
