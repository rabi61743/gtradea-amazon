import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/network/api_error.dart';
import 'package:gtradea_amazon/features/address/data/address_store.dart';
import 'package:gtradea_amazon/features/checkout/data/checkout_models.dart';
import 'package:gtradea_amazon/features/checkout/data/checkout_repository.dart';
import 'package:gtradea_amazon/features/checkout/data/order_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

const _address = Address(
  id: 'a1',
  label: AddressLabel.home,
  fullName: 'Rabi Yadav',
  phone: '9812345678',
  province: 'Bagmati',
  city: 'Lalitpur',
  area: 'Jhamsikhel',
  landmark: 'Near the school',
  postalCode: '44700',
);

CheckoutOrderInput input({
  List<String> selected = const [],
  String? promoCode,
  num walletApply = 0,
  String billingType = 'individual',
  String? companyName,
}) => CheckoutOrderInput(
  shippingAddress: CheckoutAddress.fromAddress(_address),
  selectedCartItemIds: selected,
  promoCode: promoCode,
  walletApply: walletApply,
  billingType: billingType,
  companyName: companyName,
  termsAccepted: true,
);

ServerPromo promo({
  String type = 'percentage',
  num value = 20,
  num? max,
  num min = 0,
  bool freeShipping = false,
  bool active = true,
  DateTime? until,
  int limit = 0,
  int used = 0,
}) => ServerPromo(
  code: 'DASHAIN20',
  discountType: type,
  discountValue: value,
  maxDiscountAmount: max,
  minPurchaseAmount: min,
  freeShipping: freeShipping,
  isActive: active,
  validUntil: until,
  usageLimit: limit,
  usedCount: used,
);

void main() {
  group('the order body', () {
    test('puts the district in both city and state', () {
      // The freight calculation keys on state and the stored address displays
      // city. Sending only one breaks whichever half is missing.
      final json = input().toJson(paymentMethod: 'cod');
      final shipping = json['shippingAddress'] as Map;

      expect(shipping['city'], 'Lalitpur');
      expect(shipping['state'], 'Bagmati');
      expect(shipping['country'], 'Nepal');
    });

    test('sends the phone in international form', () {
      final shipping =
          input().toJson()['shippingAddress'] as Map<String, dynamic>;
      expect(shipping['phone'], '+9779812345678');
    });

    test('freight is always zero and never the delivery quote', () {
      // Freight is quoted on actual weight and collected at the door, so it
      // must never enter the amount a gateway charges. Wiring the delivery
      // total in here would charge for it twice.
      final json = input().toJson(paymentMethod: 'cod');
      expect(json['freightCost'], 0);
      expect(json['freightBasis'], 'none');
    });

    test('an empty selection is omitted, because absent means everything', () {
      // An empty array and an absent key are not the same request: absent
      // tells the server to price the whole cart.
      expect(input().toJson().containsKey('selectedCartItemIds'), isFalse);
      expect(input(selected: ['row-1']).toJson()['selectedCartItemIds'], [
        'row-1',
      ]);
    });

    test('a zero wallet application is omitted', () {
      expect(input().toJson().containsKey('walletApply'), isFalse);
      expect(input(walletApply: 500).toJson()['walletApply'], 500);
    });

    test('an empty promo code is omitted, not sent blank', () {
      expect(input(promoCode: '').toJson().containsKey('promoCode'), isFalse);
      expect(input(promoCode: 'X').toJson()['promoCode'], 'X');
    });

    test('the payment method is present only when the caller passes it', () {
      // The server infers it from the path for most gateways and builds a
      // different body when the key is present. Helpfully sending it to all of
      // them changes what gets created.
      expect(input().toJson().containsKey('paymentMethod'), isFalse);
      expect(input().toJson(paymentMethod: 'cod')['paymentMethod'], 'cod');
    });

    test(
      'billing mirrors shipping, with the tax fields only for a business',
      () {
        final personal = input().toJson()['billingAddress'] as Map;
        expect(personal['city'], 'Lalitpur');
        expect(personal['billingType'], 'individual');
        expect(personal.containsKey('companyName'), isFalse);

        final business =
            input(
                  billingType: 'business',
                  companyName: 'GT Ltd',
                ).toJson()['billingAddress']
                as Map;
        expect(business['companyName'], 'GT Ltd');

        // Business, but the field was left blank: neither key is sent.
        final blank =
            input(
                  billingType: 'business',
                  companyName: '',
                ).toJson()['billingAddress']
                as Map;
        expect(blank.containsKey('companyName'), isFalse);
      },
    );
  });

  group('the money', () {
    test('backs VAT out of the price rather than adding it on top', () {
      // Catalogue prices already include it. Adding 13% again would turn 1130
      // into 1277 for a shopper who was quoted 1130.
      final summary = OrderSummary.compute(subtotal: 1130);

      expect(summary.productTotal, 1130);
      expect(summary.productVat, 130);
      expect(summary.productExVat, 1000);
      expect(summary.totalOrder, 1130);
    });

    test('takes the VAT rate from the server when it has quoted one', () {
      final summary = OrderSummary.compute(
        subtotal: 1000,
        delivery: const DeliveryQuote(total: 200, vat: 20, vatPercent: 10),
      );
      expect(summary.vatPercent, 10);
      expect(summary.productVat, 91, reason: '1000 * 10 / 110');
    });

    test('applies a percentage promo to the original subtotal', () {
      // Not to what the mode discount left. Applying it to the remainder is
      // the intuitive reading and under-discounts the shopper against both the
      // web build and the server.
      final summary = OrderSummary.compute(
        subtotal: 1000,
        modeDiscountPercent: 10,
        promo: promo(value: 20),
      );

      expect(summary.modeDiscount, 100);
      expect(summary.promoDiscount, 200, reason: '20% of 1000, not of 900');
      expect(summary.productTotal, 700);
    });

    test('caps a promo at what the mode discount left behind', () {
      // The two together can never exceed the subtotal, so the order can never
      // come to less than nothing.
      final summary = OrderSummary.compute(
        subtotal: 1000,
        modeDiscountPercent: 30,
        promo: promo(type: 'fixed', value: 5000),
      );

      expect(summary.modeDiscount, 300);
      expect(summary.promoDiscount, 700);
      expect(summary.productTotal, 0);
    });

    test('honours a maximum discount amount', () {
      final summary = OrderSummary.compute(
        subtotal: 10000,
        promo: promo(value: 50, max: 1000),
      );
      expect(summary.promoDiscount, 1000);
    });

    test('free shipping zeroes the whole delivery leg, not just its tax', () {
      final summary = OrderSummary.compute(
        subtotal: 1000,
        promo: promo(value: 0, freeShipping: true),
        delivery: const DeliveryQuote(total: 250, vat: 29),
      );

      expect(summary.logisticTotal, 0);
      expect(summary.logisticVat, 0);
      expect(summary.totalOrder, 1000);
    });

    test(
      'delivery is added to the total, with the server figure for its tax',
      () {
        final summary = OrderSummary.compute(
          subtotal: 1000,
          delivery: const DeliveryQuote(total: 250, vat: 29),
        );

        expect(summary.logisticTotal, 250);
        expect(summary.logisticVat, 29, reason: 'the server computed it');
        expect(summary.totalOrder, 1250);
      },
    );

    test('the mode discount is the only figure kept to paisa', () {
      final summary = OrderSummary.compute(
        subtotal: 999,
        modeDiscountPercent: 7,
      );
      expect(summary.modeDiscount, 69.93);
    });

    test('no quote means no delivery leg and the default rate', () {
      // A quote of mode "off", or nothing at all, hides the block rather than
      // showing a zero row.
      expect(
        DeliveryQuote.fromJson(const {'mode': 'off', 'total': 500}),
        isNull,
      );
      expect(DeliveryQuote.fromJson(const {'total': 0}), isNull);

      final summary = OrderSummary.compute(subtotal: 1000);
      expect(summary.logisticTotal, 0);
      expect(summary.vatPercent, 13);
    });
  });

  group('promo refusals', () {
    test('names the reason rather than just refusing', () {
      expect(refusePromo(null, 1000), PromoRefusal.unknown);
      expect(refusePromo(promo(active: false), 1000), PromoRefusal.inactive);
      expect(
        refusePromo(promo(until: DateTime(2020)), 1000),
        PromoRefusal.expired,
      );
      expect(refusePromo(promo(limit: 5, used: 5), 1000), PromoRefusal.usedUp);
      expect(refusePromo(promo(min: 2000), 1000), PromoRefusal.belowMinimum);
      expect(refusePromo(promo(), 1000), isNull);
    });
  });

  group('placing an order', () {
    late FakeApi api;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      api = FakeApi();
      ApiClient.overrideDio = api.dio();
    });

    tearDown(() => ApiClient.overrideDio = null);

    test('reads the order back', () async {
      api.on(
        'POST',
        '/checkout',
        body: const {
          'orderId': 'order-1',
          'orderNumber': 'GT-1001',
          'advanceAmount': 500,
          'remainingAmount': 1760,
        },
      );

      final placed = await CheckoutRepository.instance.placeCashOnDelivery(
        input(),
      );

      expect(placed.orderId, 'order-1');
      expect(placed.orderNumber, 'GT-1001');
      expect(placed.advanceAmount, 500);
    });

    test('a 200 carrying success:false is a failure', () async {
      // Checkout has a second failure convention on top of HTTP status. Missed,
      // it would decode as an order with no id and then be used to build a
      // request path.
      api.on(
        'POST',
        '/checkout',
        body: const {'success': false, 'error': 'That promo code has expired'},
      );

      await expectLater(
        CheckoutRepository.instance.placeCashOnDelivery(input()),
        throwsA(
          isA<ApiError>().having(
            (e) => e.message,
            'message',
            'That promo code has expired',
          ),
        ),
      );
    });

    test('an absent success flag is a success, not a failure', () async {
      // Only a literal false counts. Treating a missing key as failure would
      // reject every ordinary response.
      api.on(
        'POST',
        '/checkout',
        body: const {'orderId': 'x', 'orderNumber': 'GT-2'},
      );

      final placed = await CheckoutRepository.instance.placeCashOnDelivery(
        input(),
      );
      expect(placed.orderNumber, 'GT-2');
    });

    test(
      'a missing order id stays empty rather than becoming "null"',
      () async {
        // `.toString()` on a missing value yields the four-character string
        // "null", which then goes into GET /orders/null.
        api.on('POST', '/checkout', body: const {'orderNumber': 'GT-3'});

        final placed = await CheckoutRepository.instance.placeCashOnDelivery(
          input(),
        );
        expect(placed.orderId, '');
      },
    );

    test(
      'store credit covering everything comes back with no gateway payload',
      () async {
        api.on(
          'POST',
          '/payments/khalti/initiate',
          body: const {
            'orderId': 'o1',
            'orderNumber': 'GT-4',
            'paidByWallet': true,
          },
        );

        final placed = await CheckoutRepository.instance.initiatePayment(
          'khalti',
          input(),
        );

        expect(placed.paidByWallet, isTrue);
        expect(placed.gateway.containsKey('paymentUrl'), isFalse);
      },
    );

    test('eSewa is told its own name and the others are not', () async {
      api.on('POST', '/payments/esewa/initiate', body: const {'orderId': 'o'});
      api.on('POST', '/payments/khalti/initiate', body: const {'orderId': 'o'});

      await CheckoutRepository.instance.initiatePayment('esewa', input());
      await CheckoutRepository.instance.initiatePayment('khalti', input());

      expect(api.calls[0].json['paymentMethod'], 'esewa');
      expect(api.calls[1].json.containsKey('paymentMethod'), isFalse);
    });

    test(
      'an NPS instrument rides alongside the address, not inside it',
      () async {
        api.on('POST', '/payments/nps/initiate', body: const {'orderId': 'o'});

        await CheckoutRepository.instance.initiatePayment(
          'nps',
          input(),
          instrumentCode: 'NIBLMOBILE',
        );

        expect(api.calls.single.json['instrumentCode'], 'NIBLMOBILE');
      },
    );

    test('a delivery quote that fails does not block the order', () async {
      // Someone who cannot get a freight estimate should still be able to buy.
      api.on(
        'POST',
        '/checkout/delivery-charge',
        status: 500,
        body: const {'error': 'down'},
      );

      expect(
        await CheckoutRepository.instance.deliveryCharge(
          district: 'Lalitpur',
          shippingMode: 'land',
        ),
        isNull,
      );
    });

    test('an unknown promo code is absent, not an error', () async {
      api.on(
        'GET',
        '/promo-codes/by-code/NOPE',
        status: 404,
        body: const {'error': 'not found'},
      );

      expect(await CheckoutRepository.instance.promoByCode('nope'), isNull);
    });
  });
}
