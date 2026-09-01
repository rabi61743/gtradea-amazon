import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Who the invoice is made out to.
///
/// `CheckoutOrderInput` has carried `billingType`, `companyName` and `taxId`
/// since it was written, and sends them to the server inside `billingAddress`.
/// Nothing ever set them, so every order this app has placed has been billed to
/// an individual -- including the wholesale ones, which is most of them. This
/// is the control that makes those three fields mean something.
///
/// A business needs a name on the invoice; that is what makes it a business
/// invoice rather than a personal receipt with a label on it. The tax number is
/// asked for but not insisted on -- plenty of small firms here do not have one
/// to hand, and refusing the order over it would cost a sale to enforce a rule
/// the server has not asked for.
class BillToSection extends StatelessWidget {
  const BillToSection({
    super.key,
    required this.isBusiness,
    required this.companyName,
    required this.taxId,
    required this.onChanged,
    required this.onCompanyName,
    required this.onTaxId,
    this.enabled = true,
    this.showCompanyError = false,
  });

  final bool isBusiness;
  final String companyName;
  final String taxId;

  final ValueChanged<bool> onChanged;
  final ValueChanged<String> onCompanyName;
  final ValueChanged<String> onTaxId;

  final bool enabled;

  /// Set once an order has been attempted without a company name.
  final bool showCompanyError;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _Choice(
                icon: Icons.person_outline,
                label: 'Individual',
                selected: !isBusiness,
                enabled: enabled,
                onTap: () => onChanged(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Choice(
                icon: Icons.apartment_outlined,
                label: 'Business',
                selected: isBusiness,
                enabled: enabled,
                onTap: () => onChanged(true),
              ),
            ),
          ],
        ),
        // Only where they are needed. A company name box under an order billed
        // to a person is a field that can only be filled in by mistake.
        if (isBusiness) ...[
          const SizedBox(height: 12),
          TextField(
            enabled: enabled,
            onChanged: onCompanyName,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Company name',
              errorText: showCompanyError && companyName.trim().isEmpty
                  ? 'A business invoice needs a company name.'
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            enabled: enabled,
            onChanged: onTaxId,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'PAN / VAT number (optional)',
              helperText: 'Add it and it appears on the invoice.',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = theme.colorScheme.primary;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // The selected one is outlined and washed in the brand blue rather
            // than filled with it: this is a choice about paperwork, not the
            // action the screen is for, so it does not take the accent.
            color: selected ? active.withValues(alpha: 0.07) : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(
              color: selected ? active : theme.colorScheme.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? active : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? active : null,
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
