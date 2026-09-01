import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import 'card_details.dart';
import 'saved_payment_store.dart';

/// The shop's record of a shopper's cards, at `/saved-payment-methods`.
///
/// The same four routes the website uses, so a card saved on either shows up on
/// the other.
///
/// **What the server keeps is what a receipt shows**: the brand, the last four
/// digits, the expiry and the name. There is no field for a card number and
/// none for a security code, on the wire or in the table -- so this is not a
/// vault and a saved card here cannot, on its own, be charged. That is the
/// existing design, and it is why the form asks for no CVV: the code is
/// collected at the moment of payment and never leaves the device except to
/// the gateway.
class SavedPaymentRepository {
  SavedPaymentRepository._();

  static final SavedPaymentRepository instance = SavedPaymentRepository._();

  Dio get _dio => ApiClient.http;

  /// This account's cards, newest first as the server sends them.
  Future<List<SavedPaymentMethod>> list() => guarded(() async {
    final res = await _dio.get('/saved-payment-methods');
    return asRows(res.data, key: 'payment_methods')
        .map(savedCardFromServer)
        .whereType<SavedPaymentMethod>()
        .toList(growable: false);
  });

  /// Saves one, and returns the row the server made of it.
  ///
  /// [number] is read for its brand and its last four digits and then goes no
  /// further -- it is not a parameter of the request. The signature takes it
  /// rather than the derived pieces so that a caller cannot accidentally send
  /// the whole number by passing it to the wrong field.
  Future<SavedPaymentMethod> add({
    required String number,
    required String holder,
    required int expiryMonth,
    required int expiryYear,
    bool isDefault = false,
  }) => guarded(() async {
    final digits = number.replaceAll(RegExp(r'[^0-9]'), '');
    final brand = CardBrand.of(digits);
    final trimmedHolder = holder.trim();

    final res = await _dio.post(
      '/saved-payment-methods',
      data: {
        'card_last_four': digits.substring(digits.length - 4),
        'card_type': brand.name,
        'expiry_month': expiryMonth,
        'expiry_year': expiryYear,
        'cardholder_name': trimmedHolder.isEmpty ? null : trimmedHolder,
        'is_default': isDefault,
      },
    );

    final saved = savedCardFromServer(asMap(res.data));
    if (saved != null) return saved;

    // A server that answers 200 with a body this app cannot read still saved
    // the card. Returning what was sent keeps the screen truthful until the
    // next list refreshes it.
    return SavedPaymentMethod(
      id:
          '${brand.name}:${digits.substring(digits.length - 4)}:'
          '$expiryMonth$expiryYear',
      brand: brand,
      last4: digits.substring(digits.length - 4),
      holder: trimmedHolder,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      isDefault: isDefault,
    );
  });

  Future<void> remove(String serverId) => guarded(() async {
    await _dio.delete(
      '/saved-payment-methods/${Uri.encodeComponent(serverId)}',
    );
  });

  Future<void> setDefault(String serverId) => guarded(() async {
    await _dio.post(
      '/saved-payment-methods/${Uri.encodeComponent(serverId)}/default',
    );
  });
}

/// Reads one server row into the card this app already models.
///
/// The field names are the server's, which are not this app's -- `card_type`
/// carries the brand and `card_last_four` the digits.
SavedPaymentMethod? savedCardFromServer(Map<String, dynamic> json) {
  final serverId = asString(json['id']);
  final last4 = asString(json['card_last_four']);
  if (last4 == null || last4.length != 4) return null;

  final month = asInt(json['expiry_month']) ?? 0;
  final year = asInt(json['expiry_year']) ?? 0;
  if (month < 1 || month > 12 || year <= 0) return null;

  final type = asString(json['card_type']);
  final brand = CardBrand.values.firstWhere(
    (b) => b.name == type,
    orElse: () => CardBrand.unknown,
  );

  return SavedPaymentMethod(
    // The server's own id, so a delete or a default reaches the right row.
    id: serverId == null || serverId.isEmpty
        ? '${brand.name}:$last4:$month$year'
        : serverId,
    serverId: serverId,
    brand: brand,
    last4: last4,
    holder: asString(json['cardholder_name']) ?? '',
    expiryMonth: month,
    expiryYear: year,
    isDefault: asBool(json['is_default']),
  );
}
