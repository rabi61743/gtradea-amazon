import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';

/// The guaranteed-delivery window shown on the product page.
///
/// **Where the dates come from, stated plainly.** The window is computed on the
/// device from today plus [weeksMin]..[weeksMax]. The server's own
/// `shipping_estimate_note` setting was read live and carries **no `guarantee`
/// object at all**, so those two numbers are the defaults the sibling
/// storefront ships -- three to five weeks -- and not a promise this backend
/// published. The moment somebody sets a guarantee in the backoffice, this
/// reads it and the app follows.
///
/// That is why nothing here says "arrives on the 18th". A window with a fixed
/// basis is a shipping estimate; a single date would be a delivery date the
/// business has not committed to.
class DeliveryGuarantee {
  const DeliveryGuarantee({
    this.enabled = true,
    this.weeksMin = 3,
    this.weeksMax = 5,
    this.compensationPercent = 10,
  });

  final bool enabled;
  final int weeksMin;
  final int weeksMax;

  /// What the seller gives back if the window is missed, as a percentage.
  final num compensationPercent;

  /// The window as two dates, counted from [from].
  (DateTime, DateTime) windowFrom(DateTime from) => (
    from.add(Duration(days: weeksMin * 7)),
    from.add(Duration(days: weeksMax * 7)),
  );

  factory DeliveryGuarantee.fromJson(Map<String, dynamic> json) {
    const fallback = DeliveryGuarantee();
    return DeliveryGuarantee(
      enabled: json['enabled'] as bool? ?? fallback.enabled,
      weeksMin: asInt(json['weeksMin']) ?? fallback.weeksMin,
      weeksMax: asInt(json['weeksMax']) ?? fallback.weeksMax,
      compensationPercent:
          asNum(json['compensationPercent']) ?? fallback.compensationPercent,
    );
  }
}

/// The `shipping_estimate_note` site setting.
///
/// [enabled] governs the **freight-rate note** -- the per-kg and per-cbm table
/// with its heading and footnote -- which this app does not draw. It was
/// measured `false` on the live site, along with every rate. The guarantee
/// below is a separate switch and is read separately.
class ShippingEstimate {
  const ShippingEstimate({
    this.enabled = false,
    this.guarantee = const DeliveryGuarantee(),
  });

  final bool enabled;
  final DeliveryGuarantee guarantee;

  factory ShippingEstimate.fromJson(Map<String, dynamic> json) {
    final guarantee = json['guarantee'];
    return ShippingEstimate(
      enabled: json['enabled'] as bool? ?? false,
      guarantee: guarantee is Map
          ? DeliveryGuarantee.fromJson(guarantee.cast<String, dynamic>())
          : const DeliveryGuarantee(),
    );
  }
}

/// The public site settings, at `GET /site-settings`.
///
/// A key/value store, no credential required, answering with a bare array of
/// `{setting_key, setting_value}`. Several values arrive as **JSON encoded
/// inside a string** rather than as objects, which is why the parse below
/// decodes twice.
class StorefrontConfigRepository {
  StorefrontConfigRepository._();

  static final StorefrontConfigRepository instance =
      StorefrontConfigRepository._();

  Dio get _dio => ApiClient.http;

  /// Read once per run. These are site-wide settings changed by an
  /// administrator, not per-product data, and re-fetching 21KB of payment
  /// gateway configuration on every product page would be a poor trade.
  ShippingEstimate? _cached;

  /// Forgets the cached settings, for tests.
  void resetForTest() => _cached = null;

  Future<ShippingEstimate> shipping() => guarded(() async {
    final cached = _cached;
    if (cached != null) return cached;

    final res = await _dio.get('/site-settings', options: guestCall);
    final rows = res.data;
    if (rows is! List) return _cached = const ShippingEstimate();

    for (final row in rows.whereType<Map>()) {
      if (asString(row['setting_key']) != 'shipping_estimate_note') continue;
      final value = row['setting_value'];

      // Encoded as a string on the live site; handled as an object too, in
      // case the service stops double-encoding it.
      final decoded = value is String ? jsonDecode(value) : value;
      if (decoded is Map) {
        return _cached = ShippingEstimate.fromJson(
          decoded.cast<String, dynamic>(),
        );
      }
    }
    return _cached = const ShippingEstimate();
  });
}
