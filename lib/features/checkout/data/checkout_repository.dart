import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/json.dart';
import '../../cart/data/cart_store.dart';
import 'checkout_models.dart';

/// What delivery will cost, as quoted for a district.
class DeliveryQuote {
  const DeliveryQuote({
    required this.total,
    this.vat = 0,
    this.vatPercent = 13,
    this.mode = 'charge',
  });

  /// The freight figure, VAT included.
  final num total;

  /// The VAT already inside [total]. Taken from the server rather than
  /// recomputed -- freight is taxed on its own basis.
  final num vat;

  /// The rate to back VAT out of the goods with. From the server, because a
  /// rate change is the server's to make.
  final num vatPercent;

  /// 'charge' means the gateway collects it, 'estimate' means the courier
  /// does, 'off' means there is no quote at all.
  final String mode;

  bool get isCollectedUpfront => mode == 'charge';

  /// Null rather than an empty quote when there is nothing to quote: the
  /// delivery block is hidden entirely, and the VAT rate falls back.
  static DeliveryQuote? fromJson(Map<String, dynamic> json) {
    final mode = asString(json['mode']) ?? 'charge';
    final total = asNum(json['total']) ?? 0;
    if (mode == 'off' || total <= 0) return null;

    final breakdown = asMap(json['breakdown']);
    return DeliveryQuote(
      total: total,
      vat: asNum(breakdown['vat']) ?? 0,
      vatPercent: asNum(breakdown['vat_pct']) ?? 13,
      mode: mode,
    );
  }
}

/// A promo code as the server describes it.
class ServerPromo {
  const ServerPromo({
    required this.code,
    required this.discountType,
    required this.discountValue,
    this.maxDiscountAmount,
    this.minPurchaseAmount = 0,
    this.freeShipping = false,
    this.isActive = true,
    this.validFrom,
    this.validUntil,
    this.usageLimit = 0,
    this.usedCount = 0,
  });

  final String code;

  /// 'percentage' or a fixed amount.
  final String discountType;
  final num discountValue;

  /// The ceiling on a percentage discount, when there is one.
  final num? maxDiscountAmount;

  final num minPurchaseAmount;
  final bool freeShipping;
  final bool isActive;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final int usageLimit;
  final int usedCount;

  factory ServerPromo.fromJson(Map<String, dynamic> json) => ServerPromo(
    code: (asString(json['code']) ?? '').toUpperCase(),
    discountType: asString(json['discount_type']) ?? 'fixed',
    discountValue: asNum(json['discount_value']) ?? 0,
    maxDiscountAmount: asNum(json['max_discount_amount']),
    minPurchaseAmount: asNum(json['min_purchase_amount']) ?? 0,
    freeShipping: asBool(json['free_shipping']),
    isActive: asBool(json['is_active'], orElse: true),
    validFrom: asDate(json['valid_from']),
    validUntil: asDate(json['valid_until']),
    usageLimit: asInt(json['usage_limit']) ?? 0,
    usedCount: asInt(json['used_count']) ?? 0,
  );
}

/// Placing orders, quoting delivery, and checking promo codes.
class CheckoutRepository {
  CheckoutRepository._();

  static final CheckoutRepository instance = CheckoutRepository._();

  Dio get _dio => ApiClient.http;

  /// Places a cash-on-delivery order.
  Future<PlacedOrder> placeCashOnDelivery(CheckoutOrderInput input) =>
      _post('/checkout', input.toJson(paymentMethod: 'cod'));

  /// Starts an online payment.
  ///
  /// The `paymentMethod` key is deliberately inconsistent between gateways,
  /// because the server is: eSewa expects it, the others infer it from the
  /// path and build a different body when it is present. Sending it to all of
  /// them, or to none, changes what gets created.
  Future<PlacedOrder> initiatePayment(
    String gateway,
    CheckoutOrderInput input, {
    String? instrumentCode,
  }) {
    final body = input.toJson(
      paymentMethod: gateway == 'esewa' ? 'esewa' : null,
    );
    if (gateway == 'nps' && (instrumentCode?.isNotEmpty ?? false)) {
      // A sibling of shippingAddress, not nested. Omitting it is a supported
      // default meaning "let NPS show its own bank picker".
      body['instrumentCode'] = instrumentCode;
    }
    return _post('/payments/$gateway/initiate', body);
  }

  /// Confirms a payment after the gateway sends the shopper back.
  ///
  /// Each provider has its own idea of what "confirmed" means, so the caller
  /// gets the whole body and the gateway-specific check lives with the screen
  /// that ran the handshake.
  Future<Map<String, dynamic>> confirmPayment(
    String path,
    Map<String, dynamic> body,
  ) => guarded(() async {
    final res = await _dio.post(path, data: body);
    return asMap(res.data);
  });

  /// What delivery costs for a district.
  ///
  /// Every failure falls back to no quote rather than blocking checkout: a
  /// shopper who cannot get a freight estimate should still be able to order.
  Future<DeliveryQuote?> deliveryCharge({
    required String district,
    required String shippingMode,
    List<String> selectedCartItemIds = const [],
    List<CartLine> guestLines = const [],
  }) async {
    try {
      final res = await _dio.post(
        '/checkout/delivery-charge',
        data: {
          'district': district,
          'shippingMode': shippingMode,
          if (selectedCartItemIds.isNotEmpty)
            'selectedCartItemIds': selectedCartItemIds,
          // Only for a basket the server does not hold. A signed-in shopper's
          // cart is the server's own, and sending a copy of it from here would
          // be asking the server to price the prices this app happens to have.
          if (guestLines.isNotEmpty)
            'guestCartItems': [
              for (final line in guestLines)
                {
                  'id': line.serverId ?? line.productId,
                  'product_name': line.title,
                  'quantity': line.quantity,
                  'price': line.unitPrice,
                  'source': line.source,
                  // What the freight table is looked up by: the upstream
                  // catalogue id, which is where weight and dimensions live.
                  if (line.source != 'local')
                    'source_product_id': line.productId,
                },
            ],
        },
      );
      return DeliveryQuote.fromJson(asMap(res.data));
    } catch (_) {
      return null;
    }
  }

  /// Looks a promo code up.
  ///
  /// Returns null when there is no such code. Whether it *applies* is decided
  /// by the caller against the basket, and re-decided by the server when the
  /// order is placed -- the client verdict is a courtesy, never the ruling.
  Future<ServerPromo?> promoByCode(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) return null;
    try {
      final res = await _dio.get('/promo-codes/by-code/$trimmed');
      final body = asMap(res.data);
      if (body.isEmpty) return null;
      return ServerPromo.fromJson(body);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiError.fromDio(e);
    }
  }

  /// Posts and unwraps, honouring this API's second failure convention.
  ///
  /// Most of it reports failure with an HTTP status. Checkout also answers 200
  /// with `{success: false}`, and only a literal false counts -- an absent
  /// `success` is a success.
  Future<PlacedOrder> _post(String path, Map<String, dynamic> body) {
    return guarded(() async {
      final res = await _dio.post(path, data: body);
      final data = asMap(res.data);
      if (data['success'] == false) {
        throw ApiError.fromEnvelope(data);
      }
      return PlacedOrder.fromJson(data);
    });
  }
}
