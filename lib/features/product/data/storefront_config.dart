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

/// One way the shop will carry an order, as it publishes it.
///
/// The list comes from the `modes` array inside `shipping_estimate_note` --
/// the shop's own record of what it ships by, with its own labels and its own
/// freight rates. Nothing here is named in the app: a shop that adds a fourth
/// mode, renames one, or drops one gets exactly that on the product page.
class LogisticsMode {
  const LogisticsMode({
    required this.key,
    required this.label,
    this.perKg,
    this.perCbm,
    this.listed = false,
    this.discountPercent = 0,
  });

  /// What the checkout calls this mode -- `air`, `land`, `sea`, or whatever
  /// the shop adds. This is the value sent as `shippingMode`.
  final String key;

  /// The shop's own words for it, e.g. "By Air".
  final String label;

  /// The published freight rates, where the shop shows them. Null is not
  /// zero: it means the shop has not published a rate, and nothing is drawn.
  final num? perKg;
  final num? perCbm;

  /// Whether the shop lists this mode in its own freight-rate note.
  ///
  /// Not the same as whether it can be chosen: every published mode can be
  /// chosen, and this only says whether the shop is currently advertising its
  /// rates. On the live site every mode has this false while the modes
  /// themselves are what checkout runs on.
  final bool listed;

  /// What the shop takes off the goods for choosing this mode, as a
  /// percentage. Only applied when [LogisticsConfig.discountsApply].
  final num discountPercent;

  factory LogisticsMode.fromJson(
    Map<String, dynamic> json, {
    num discountPercent = 0,
  }) {
    final key = (asString(json['key']) ?? asString(json['slug']) ?? '').trim();
    return LogisticsMode(
      key: key,
      label: asString(json['label'])?.trim().isNotEmpty == true
          ? asString(json['label'])!.trim()
          : key,
      perKg: asNum(json['perKg']),
      perCbm: asNum(json['perCbm']),
      listed: asBool(json['enabled']),
      discountPercent: discountPercent,
    );
  }
}

/// What the shop publishes about carrying an order.
///
/// Every field is the server's. The app names no mode, invents no delivery
/// window and assumes no rate: with nothing published this is empty, and the
/// product page says so rather than offering a choice nobody stands behind.
class LogisticsConfig {
  const LogisticsConfig({
    this.modes = const [],
    this.discountsApply = false,
    this.leadDaysMin,
    this.leadDaysMax,
    this.showLeadTime = false,
    this.footnote,
  });

  final List<LogisticsMode> modes;

  /// `shipping_mode_selector_enabled`: whether choosing a mode changes what
  /// the goods cost. False on the live site, so the app shows no discount.
  final bool discountsApply;

  /// `default_lead_time_days_min` / `_max` -- how long the shop says an order
  /// takes. Null where the shop has not published it.
  final int? leadDaysMin;
  final int? leadDaysMax;

  /// `show_lead_time_on_pdp`: whether the shop wants that window on the
  /// product page at all.
  final bool showLeadTime;

  /// `shipping_estimate_note.footnote` -- what the shop says about how it
  /// works out freight, in its own words.
  ///
  /// Read even though the shop's `showFootnote` is false: that flag governs
  /// setting it inline under the rates, and this is behind an information
  /// button somebody has to ask for. Null where the shop has written none, and
  /// the button is then not drawn at all.
  final String? footnote;

  bool get hasLeadTime =>
      showLeadTime && leadDaysMin != null && leadDaysMax != null;

  bool get isEmpty => modes.isEmpty;
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

  /// The settings themselves, by key, so the two readers below cost one
  /// request between them rather than one each.
  Map<String, Object?>? _settings;

  /// Forgets the cached settings, for tests.
  void resetForTest() {
    _cached = null;
    _settings = null;
  }

  /// Every setting, by key, fetched at most once per run.
  Future<Map<String, Object?>> _values() => guarded(() async {
    final cached = _settings;
    if (cached != null) return cached;

    final res = await _dio.get('/site-settings', options: guestCall);
    final rows = res.data;
    if (rows is! List) return _settings = const {};

    final values = <String, Object?>{};
    for (final row in rows.whereType<Map>()) {
      final key = asString(row['setting_key']);
      if (key != null) values[key] = row['setting_value'];
    }
    return _settings = values;
  });

  /// Values arrive as JSON **encoded inside a string** on the live site, and
  /// as objects on some deployments. Both are read.
  Map<String, dynamic>? _asObject(Object? value) {
    final decoded = value is String ? _tryDecode(value) : value;
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  }

  Object? _tryDecode(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      // A plain string setting -- "true", "15", a name. Not an object, which
      // is all this asked.
      return null;
    }
  }

  Future<ShippingEstimate> shipping() => guarded(() async {
    final cached = _cached;
    if (cached != null) return cached;

    final values = await _values();
    final note = _asObject(values['shipping_estimate_note']);
    return _cached = note == null
        ? const ShippingEstimate()
        : ShippingEstimate.fromJson(note);
  });

  /// What the shop will carry an order by, and how long it says that takes.
  ///
  /// Assembled from the settings the storefront itself reads: the modes and
  /// their rates out of `shipping_estimate_note`, the per-mode discounts out
  /// of `<key>_discount_percent`, whether those discounts apply at all out of
  /// `shipping_mode_selector_enabled`, and the delivery window out of
  /// `default_lead_time_days_min` / `_max`.
  ///
  /// Nothing is defaulted into existence. A shop that publishes no modes gets
  /// an empty list here and a product page that says there is nothing to
  /// choose, rather than an air/land/sea menu this app made up.
  Future<LogisticsConfig> logistics() => guarded(() async {
    final values = await _values();
    final note = _asObject(values['shipping_estimate_note']);
    final rows = note?['modes'];

    final modes = [
      if (rows is List)
        for (final row in rows.whereType<Map>())
          LogisticsMode.fromJson(
            row.cast<String, dynamic>(),
            discountPercent:
                asNum(
                  values['${asString(row['key']) ?? ''}_discount_percent'],
                ) ??
                0,
          ),
    ].where((mode) => mode.key.isNotEmpty).toList(growable: false);

    return LogisticsConfig(
      modes: modes,
      discountsApply: asBool(values['shipping_mode_selector_enabled']),
      leadDaysMin: asInt(values['default_lead_time_days_min']),
      leadDaysMax: asInt(values['default_lead_time_days_max']),
      showLeadTime: asBool(values['show_lead_time_on_pdp']),
      footnote: asString(note?['footnote'])?.trim(),
    );
  });
}
