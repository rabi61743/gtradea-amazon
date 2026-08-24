import 'package:flutter/material.dart';

import '../../../core/l10n/payment_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../data/payment_method.dart';
import '../data/saved_payment_store.dart';

/// The ways this shop accepts money, and which one is chosen.
///
/// The list comes from the server. A method the shop has switched off is never
/// drawn, because offering one means a shopper enters an address, agrees a
/// total, commits, and only then is refused by a gateway that was never going
/// to accept them.
class PaymentMethodsSection extends StatelessWidget {
  const PaymentMethodsSection({
    super.key,
    required this.strings,
    required this.methods,
    required this.selected,
    required this.onSelected,
    required this.savedCards,
    required this.selectedCardId,
    required this.onCardSelected,
    required this.onUseNewCard,
    required this.onRemoveCard,
    this.enabled = true,
  });

  final PaymentStrings strings;
  final List<PaymentMethod> methods;
  final PaymentMethod? selected;
  final ValueChanged<PaymentMethod> onSelected;

  final List<SavedPaymentMethod> savedCards;
  final String? selectedCardId;
  final ValueChanged<SavedPaymentMethod> onCardSelected;
  final VoidCallback onUseNewCard;
  final ValueChanged<SavedPaymentMethod> onRemoveCard;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (methods.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          strings.noMethods,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            strings.chooseMethod,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final method in methods)
          _MethodTile(
            method: method,
            selected: method.id == selected?.id,
            enabled: enabled,
            onTap: () => onSelected(method),
          ),
        // Card details belong under the card option, not on a separate screen:
        // a saved card is part of choosing how to pay, not a step after it.
        if (selected?.kind == PaymentKind.card) ...[
          const SizedBox(height: 4),
          _SavedCards(
            strings: strings,
            cards: savedCards,
            selectedId: selectedCardId,
            enabled: enabled,
            onSelected: onCardSelected,
            onUseNew: onUseNewCard,
            onRemove: onRemoveCard,
          ),
        ],
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.07)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.dividerColor,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  method.kind.icon,
                  size: 24,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              method.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (method.badge != null) ...[
                            const SizedBox(width: 8),
                            // The shop's own wording, shown verbatim.
                            _Badge(label: method.badge!),
                          ],
                        ],
                      ),
                      if (method.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          method.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cards this shopper asked us to remember.
class _SavedCards extends StatelessWidget {
  const _SavedCards({
    required this.strings,
    required this.cards,
    required this.selectedId,
    required this.enabled,
    required this.onSelected,
    required this.onUseNew,
    required this.onRemove,
  });

  final PaymentStrings strings;
  final List<SavedPaymentMethod> cards;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<SavedPaymentMethod> onSelected;
  final VoidCallback onUseNew;
  final ValueChanged<SavedPaymentMethod> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cards.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                strings.savedCards,
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final card in cards)
              _SavedCardTile(
                strings: strings,
                card: card,
                selected: card.id == selectedId,
                enabled: enabled,
                onTap: () => onSelected(card),
                onRemove: () => onRemove(card),
              ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: enabled ? onUseNew : null,
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                cards.isEmpty ? strings.cardNumber : strings.useNewCard,
              ),
            ),
          ),
          // Said where the card is entered, not buried in a policy page. It is
          // the one place a shopper is deciding whether to trust this app.
          Text(
            strings.securityNote,
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

class _SavedCardTile extends StatelessWidget {
  const _SavedCardTile({
    required this.strings,
    required this.card,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onRemove,
  });

  final PaymentStrings strings;
  final SavedPaymentMethod card;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expired = card.isExpired();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.07)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          // An expired card stays visible but cannot be chosen: hiding it
          // makes a shopper hunt for a card they know they saved.
          onTap: (enabled && !expired) ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color:
                    selected ? theme.colorScheme.primary : theme.dividerColor,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.credit_card,
                  size: 20,
                  color: expired
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${card.brand.label} ${card.maskedNumber}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: expired
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        expired
                            ? '${strings.expired} · ${card.expiryLabel}'
                            : '${card.holder} · ${card.expiryLabel}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: expired
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: strings.removeCard,
                  onPressed: enabled ? onRemove : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
