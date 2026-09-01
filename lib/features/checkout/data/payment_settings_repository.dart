import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import 'payment_gateway.dart';
import 'payment_method.dart';

/// Which ways to pay this storefront currently accepts.
///
/// Read from the server, not compiled in. Whether a shop takes cash on delivery
/// this week is an operational decision, and a method offered by the app after
/// an admin switched it off fails at the gateway -- after the shopper has
/// entered an address, agreed a total and committed.
class PaymentSettingsRepository {
  PaymentSettingsRepository._();

  static final PaymentSettingsRepository instance =
      PaymentSettingsRepository._();

  Dio get _dio => ApiClient.http;

  /// The methods this app can offer, in the shop's own order.
  ///
  /// Filtered to what the app can actually complete, in one place rather than
  /// per screen, so the checkout page and the payment methods screen cannot
  /// disagree about what the shop takes.
  Future<List<PaymentMethod>> methods() => guarded(() async {
    final res = await _dio.get(
      '/site-settings/active_payment_methods',
      options: guestCall,
    );
    final body = asMap(res.data);
    // The endpoint answers either the setting row or the value directly.
    // An unseeded key is a normal state and comes back with a null value.
    final value = body.containsKey('setting_value')
        ? body['setting_value']
        : body;
    return decodePaymentMethods(value)
        .where((method) => PaymentGateway.canComplete(method.id))
        .toList(growable: false);
  });

  /// What share of the order the gateway collects up front.
  ///
  /// A percentage, clamped the way the server clamps it. Arrives as a string
  /// often enough that parsing rather than casting is the only safe read.
  Future<int> advancePercent() async {
    try {
      final res = await _dio.get(
        '/site-settings/advance_payment_percent',
        options: guestCall,
      );
      final body = asMap(res.data);
      final raw = body.containsKey('setting_value')
          ? body['setting_value']
          : res.data;
      final percent = asInt(raw);
      if (percent == null) return 100;
      return percent.clamp(10, 100);
    } catch (_) {
      // Charging the whole amount is the safe default: it never asks a shopper
      // for less than the order is worth and then bills the difference.
      return 100;
    }
  }
}
