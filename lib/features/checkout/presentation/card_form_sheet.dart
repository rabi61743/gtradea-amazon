import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/payment_strings.dart';
import '../data/card_details.dart';

/// What the card sheet returns.
typedef CardEntry = ({CardDetails card, bool remember});

/// Where a card is typed in.
///
/// The details exist here and in the call that uses them, and nowhere else.
/// Nothing on this sheet is written to disk, put in a log, or kept after it
/// closes -- the controllers are disposed with the widget, and the only thing
/// that can outlive it is the brand, the last four digits and the expiry, and
/// only if the shopper ticks the box.
class CardFormSheet extends StatefulWidget {
  const CardFormSheet({super.key, required this.strings, this.canSave = true});

  final PaymentStrings strings;

  /// Whether to offer remembering the card at all.
  final bool canSave;

  static Future<CardEntry?> show(
    BuildContext context, {
    required PaymentStrings strings,
    bool canSave = true,
  }) {
    return showModalBottomSheet<CardEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => CardFormSheet(strings: strings, canSave: canSave),
    );
  }

  @override
  State<CardFormSheet> createState() => _CardFormSheetState();
}

class _CardFormSheetState extends State<CardFormSheet> {
  final _number = TextEditingController();
  final _holder = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();

  bool _remember = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    // Rebuild as the number is typed so the brand, its icon and the expected
    // security-code length keep up.
    _number.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    // The card leaves memory with the sheet. Nothing else holds it.
    _number.dispose();
    _holder.dispose();
    _expiry.dispose();
    _cvv.dispose();
    super.dispose();
  }

  String get _digits => _number.text.replaceAll(RegExp(r'[^0-9]'), '');

  CardBrand get _brand => CardBrand.of(_digits);

  CardErrors get _errors => validateCard(
        number: _number.text,
        holder: _holder.text,
        expiry: _expiry.text,
        cvv: _cvv.text,
      );

  void _submit() {
    setState(() => _submitted = true);
    final errors = _errors;
    if (!errors.isValid) return;

    final expiryDigits = _expiry.text.replaceAll(RegExp(r'[^0-9]'), '');
    final card = CardDetails(
      number: _digits,
      holder: _holder.text.trim(),
      expiryMonth: int.parse(expiryDigits.substring(0, 2)),
      expiryYear: 2000 + int.parse(expiryDigits.substring(2, 4)),
      cvv: _cvv.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    Navigator.of(context).pop((card: card, remember: _remember));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = widget.strings;
    // Errors appear once, on submit. Marking a field wrong while it is being
    // typed into is how a form nags.
    final errors = _submitted ? _errors : const CardErrors();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.credit_card, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _brand == CardBrand.unknown ? strings.title : _brand.label,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _number,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.creditCardNumber],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(_brand.maxDigits),
                _CardNumberFormatter(),
              ],
              decoration: InputDecoration(
                labelText: strings.cardNumber,
                errorText: errors.number,
                prefixIcon: const Icon(Icons.numbers),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _holder,
              textCapitalization: TextCapitalization.characters,
              autofillHints: const [AutofillHints.creditCardName],
              decoration: InputDecoration(
                labelText: strings.cardHolder,
                errorText: errors.holder,
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _expiry,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                      _ExpiryFormatter(),
                    ],
                    decoration: InputDecoration(
                      labelText: strings.expiry,
                      errorText: errors.expiry,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _cvv,
                    keyboardType: TextInputType.number,
                    // Obscured like a password, because that is what it is.
                    obscureText: true,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(_brand.cvvLength),
                    ],
                    decoration: InputDecoration(
                      labelText: strings.cvv,
                      errorText: errors.cvv,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              strings.cvvHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (widget.canSave) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _remember,
                onChanged: (value) =>
                    setState(() => _remember = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(strings.saveThisCard),
                // Says exactly what is kept. A shopper ticking this box is
                // entitled to know it is four digits and not a card.
                subtitle: Text(
                  strings.saveCardNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(strings.payNow),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Groups the number as it is typed, so a shopper can check it against the
/// card in their hand without counting digits.
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final formatted = formatCardNumber(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Turns 1226 into 12/26 while it is typed.
class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length && i < 4; i++) {
      if (i == 2) buffer.write('/');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
