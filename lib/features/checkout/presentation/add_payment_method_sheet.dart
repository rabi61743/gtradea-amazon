import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_error.dart';
import '../data/card_details.dart';
import '../data/saved_payment_store.dart';

/// Add a card to the shopper's saved payment methods.
///
/// The number is typed here and goes no further than this widget: it is read
/// for its brand and its last four digits, and those are what the shop stores.
/// There is no security-code field because there is nothing here to charge --
/// a saved card is a label, and the code is asked for at the moment of payment
/// by the form that actually pays.
class AddPaymentMethodSheet extends StatefulWidget {
  const AddPaymentMethodSheet({super.key});

  /// Returns the saved card, or null when it was cancelled.
  static Future<SavedPaymentMethod?> show(BuildContext context) {
    return showModalBottomSheet<SavedPaymentMethod>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => const AddPaymentMethodSheet(),
    );
  }

  @override
  State<AddPaymentMethodSheet> createState() => _AddPaymentMethodSheetState();
}

class _AddPaymentMethodSheetState extends State<AddPaymentMethodSheet> {
  final _number = TextEditingController();
  final _month = TextEditingController();
  final _year = TextEditingController();
  final _holder = TextEditingController();

  bool _makeDefault = false;
  bool _saving = false;
  String? _problem;

  String? _numberError;
  String? _monthError;
  String? _yearError;
  String? _holderError;

  @override
  void dispose() {
    _number.dispose();
    _month.dispose();
    _year.dispose();
    _holder.dispose();
    super.dispose();
  }

  /// Everything wrong with the form, or nothing.
  bool _check() {
    final digits = _number.text.replaceAll(RegExp(r'[^0-9]'), '');
    final holder = _holder.text.trim();
    final month = int.tryParse(_month.text.trim());
    final year = int.tryParse(_year.text.trim());
    final now = DateTime.now();

    String? numberError;
    if (digits.isEmpty) {
      numberError = 'Enter the card number';
    } else if (digits.length < 12) {
      numberError = 'That number is too short';
    } else if (!passesLuhn(digits)) {
      // Catches a transposed pair, which is the commonest way a number is
      // mistyped and the one a length check cannot see.
      numberError = 'Check the card number';
    }

    String? monthError;
    if (_month.text.trim().isEmpty) {
      monthError = 'Required';
    } else if (month == null || month < 1 || month > 12) {
      monthError = 'MM, 01-12';
    }

    String? yearError;
    if (_year.text.trim().isEmpty) {
      yearError = 'Required';
    } else if (year == null || _year.text.trim().length != 4) {
      yearError = 'Use YYYY';
    } else if (year < now.year || year > now.year + 30) {
      yearError = 'Check the year';
    }

    // Only once both halves are themselves sensible: "expired" is a confusing
    // thing to say about a month that does not exist.
    if (monthError == null && yearError == null) {
      // A card is good through the last day of its expiry month, so the
      // comparison is against the first day of the next one.
      final expiresAfter = DateTime(year!, month! + 1);
      if (!expiresAfter.isAfter(DateTime(now.year, now.month, now.day))) {
        yearError = 'That card has expired';
      }
    }

    final holderError = holder.isEmpty
        ? 'Enter the name on the card'
        : (holder.length < 2 ? 'Enter the full name' : null);

    setState(() {
      _numberError = numberError;
      _monthError = monthError;
      _yearError = yearError;
      _holderError = holderError;
      _problem = null;
    });

    return numberError == null &&
        monthError == null &&
        yearError == null &&
        holderError == null;
  }

  Future<void> _save() async {
    // Guarded as well as disabled: a second tap that lands in the same frame
    // as the first would otherwise save the card twice.
    if (_saving) return;
    if (!_check()) return;

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    try {
      final saved = await SavedPaymentStore.instance.addCard(
        number: _number.text,
        holder: _holder.text,
        expiryMonth: int.parse(_month.text.trim()),
        expiryYear: int.parse(_year.text.trim()),
        makeDefault: _makeDefault,
      );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _problem = e.isNetwork
            ? 'No connection. The card was not saved.'
            : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      // Lifts the sheet clear of the keyboard, which otherwise covers the very
      // field being typed into.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              Text(
                'Add Payment Method',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Add a new card to save for future purchases. We only store '
                'the last 4 digits for security.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),

              const _Label('Card Number'),
              TextField(
                controller: _number,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                autofocus: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(19),
                  _CardNumberSpacing(),
                ],
                decoration: InputDecoration(
                  hintText: '1234 5678 9012 3456',
                  errorText: _numberError,
                ),
                onChanged: (_) {
                  if (_numberError != null) setState(() => _numberError = null);
                },
              ),
              const SizedBox(height: 14),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Label('Expiry Month'),
                        TextField(
                          controller: _month,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          decoration: InputDecoration(
                            hintText: 'MM',
                            errorText: _monthError,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Label('Expiry Year'),
                        TextField(
                          controller: _year,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          decoration: InputDecoration(
                            hintText: 'YYYY',
                            errorText: _yearError,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              const _Label('Cardholder Name'),
              TextField(
                controller: _holder,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  hintText: 'John Doe',
                  errorText: _holderError,
                ),
              ),
              const SizedBox(height: 8),

              CheckboxListTile(
                value: _makeDefault,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _makeDefault = value ?? false),
                title: const Text('Set as default payment method'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),

              if (_problem != null) ...[
                const SizedBox(height: 6),
                _Problem(_problem!),
              ],

              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Card'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Groups the digits in fours as they are typed, so a long number can be
/// checked against the card in the shopper's hand.
class _CardNumberSpacing extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue old,
    TextEditingValue value,
  ) {
    final digits = value.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

/// Why the card did not save. In the sheet rather than in a snackbar that
/// slides away before it has been read.
class _Problem extends StatelessWidget {
  const _Problem(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
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
