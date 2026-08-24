import 'package:flutter/foundation.dart';

/// A card network, as far as the number reveals it.
///
/// Detected from the leading digits so the form can show the right icon and
/// expect the right CVV length. Not authoritative -- the gateway decides -- but
/// enough to stop someone typing a 3-digit code into a 4-digit field.
enum CardBrand {
  visa('Visa', 16, 3),
  mastercard('Mastercard', 16, 3),
  amex('American Express', 15, 4),
  unionPay('UnionPay', 19, 3),
  unknown('Card', 19, 4);

  const CardBrand(this.label, this.maxDigits, this.cvvLength);

  final String label;

  /// The longest number this brand issues. Used to stop typing, not to reject.
  final int maxDigits;

  /// How long the security code is. Amex uses four; everyone else three.
  final int cvvLength;

  static CardBrand of(String digits) {
    if (digits.startsWith('4')) return CardBrand.visa;
    if (digits.startsWith('34') || digits.startsWith('37')) {
      return CardBrand.amex;
    }
    if (digits.startsWith('62')) return CardBrand.unionPay;
    final two = int.tryParse(digits.length >= 2 ? digits.substring(0, 2) : '');
    if (two != null && two >= 51 && two <= 55) return CardBrand.mastercard;
    final four = int.tryParse(digits.length >= 4 ? digits.substring(0, 4) : '');
    if (four != null && four >= 2221 && four <= 2720) {
      return CardBrand.mastercard;
    }
    return CardBrand.unknown;
  }
}

/// What a card is, once it has been checked.
///
/// Deliberately not a place to keep a card. It exists for the moment between
/// the form being filled in and the gateway being handed the details, and
/// nothing in this app writes it anywhere.
@immutable
class CardDetails {
  const CardDetails({
    required this.number,
    required this.holder,
    required this.expiryMonth,
    required this.expiryYear,
    required this.cvv,
  });

  /// Digits only, no spaces.
  final String number;
  final String holder;
  final int expiryMonth;

  /// Four digits.
  final int expiryYear;

  /// The security code.
  ///
  /// Held only for as long as the payment takes. Storing this is forbidden by
  /// every card scheme in existence, and there is no code in this app that
  /// writes it to disk, to a log, or into a saved card.
  final String cvv;

  CardBrand get brand => CardBrand.of(number);

  /// The only part of a number that may be kept or shown.
  String get last4 =>
      number.length >= 4 ? number.substring(number.length - 4) : number;

  /// Never includes the number. Guards against a card ending up in a crash
  /// report through a stray interpolation.
  @override
  String toString() => 'CardDetails(${brand.label} ending $last4)';
}

/// Why a card field is not acceptable, in words that say what to change.
class CardErrors {
  const CardErrors({this.number, this.holder, this.expiry, this.cvv});

  final String? number;
  final String? holder;
  final String? expiry;
  final String? cvv;

  bool get isValid =>
      number == null && holder == null && expiry == null && cvv == null;
}

/// Checks a card before anything is sent anywhere.
///
/// Client-side validation is a courtesy, not a security control: it catches a
/// typo before a round trip and a decline. The gateway is what actually decides
/// whether a card is good.
CardErrors validateCard({
  required String number,
  required String holder,
  required String expiry,
  required String cvv,
  DateTime? now,
}) {
  final digits = number.replaceAll(RegExp(r'[^0-9]'), '');
  final brand = CardBrand.of(digits);

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

  final trimmedHolder = holder.trim();
  final holderError = trimmedHolder.isEmpty
      ? 'Enter the name on the card'
      : (trimmedHolder.length < 2 ? 'Enter the full name' : null);

  final expiryError = _expiryError(expiry, now ?? DateTime.now());

  final cvvDigits = cvv.replaceAll(RegExp(r'[^0-9]'), '');
  String? cvvError;
  if (cvvDigits.isEmpty) {
    cvvError = 'Enter the security code';
  } else if (cvvDigits.length != brand.cvvLength) {
    cvvError = '${brand.label} codes are ${brand.cvvLength} digits';
  }

  return CardErrors(
    number: numberError,
    holder: holderError,
    expiry: expiryError,
    cvv: cvvError,
  );
}

String? _expiryError(String raw, DateTime now) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 'Enter the expiry date';
  if (digits.length < 4) return 'Use MM/YY';

  final month = int.tryParse(digits.substring(0, 2));
  final year = int.tryParse(digits.substring(2, 4));
  if (month == null || year == null) return 'Use MM/YY';
  if (month < 1 || month > 12) return 'That month does not exist';

  final fullYear = 2000 + year;
  // A card is good through the last day of its expiry month, so the comparison
  // is against the first day of the next one.
  final expiresAfter = DateTime(fullYear, month + 1);
  if (!expiresAfter.isAfter(DateTime(now.year, now.month, now.day))) {
    return 'That card has expired';
  }
  return null;
}

/// The checksum every card number carries.
bool passesLuhn(String digits) {
  var sum = 0;
  var double = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    final code = digits.codeUnitAt(i) - 48;
    if (code < 0 || code > 9) return false;
    var value = code;
    if (double) {
      value *= 2;
      if (value > 9) value -= 9;
    }
    sum += value;
    double = !double;
  }
  return sum % 10 == 0;
}

/// Groups a number for display: 4-4-4-4, or 4-6-5 for Amex.
String formatCardNumber(String digits) {
  final groups = CardBrand.of(digits) == CardBrand.amex
      ? const [4, 6, 5]
      : const [4, 4, 4, 4, 3];
  final buffer = StringBuffer();
  var index = 0;
  for (final size in groups) {
    if (index >= digits.length) break;
    final end = (index + size).clamp(0, digits.length);
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(digits.substring(index, end));
    index = end;
  }
  return buffer.toString();
}
