import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';

/// The ladder from the request, used as test data only. Real ladders come
/// from each product's record (`pricing.quantityTiers`) and are never written
/// into the app.
const _ladder = [
  QuantityTier(minQuantity: 1, price: 20),
  QuantityTier(minQuantity: 10, price: 17),
  QuantityTier(minQuantity: 100, price: 14),
  QuantityTier(minQuantity: 1000, price: 11),
];

/// Every boundary the request names, with the rung each must land on.
const _boundaries = {
  1: 20,
  9: 20,
  10: 17,
  99: 17,
  100: 14,
  999: 14,
  1000: 11,
  5000: 11,
};

CartLine _line({int quantity = 1, List<QuantityTier> tiers = _ladder}) =>
    CartLine(
      productId: '536875038426',
      title: 'Adult diapers, L',
      unitPrice: 20,
      quantity: quantity,
      source: '1688',
      tiers: tiers,
    );

void main() {
  group('the ladder', () {
    for (final entry in _boundaries.entries) {
      test('${entry.key} pieces cost ${entry.value} each', () {
        expect(tierPriceAt(_ladder, 20, entry.key), entry.value);
      });
    }

    test('below the first rung is the base price', () {
      const fromTwo = [
        QuantityTier(minQuantity: 2, price: 2886),
        QuantityTier(minQuantity: 200, price: 2842),
      ];
      expect(tierPriceAt(fromTwo, 2900, 1), 2900);
      expect(tierPriceAt(fromTwo, 2900, 2), 2886);
    });

    test('the product page reads it the same way', () {
      final detail = ProductDetail(
        numIid: '536875038426',
        title: 'Adult diapers, L',
        price: 20,
        rating: 0,
        reviewCount: 0,
        images: const [],
        variants: const [],
        specs: const [],
        description: '',
        tiers: _ladder,
      );
      for (final entry in _boundaries.entries) {
        expect(detail.priceAt(entry.key), entry.value, reason: '${entry.key}');
        expect(
          detail.priceAt(entry.key),
          _line(quantity: entry.key).unitPrice,
          reason: 'page and cart agree at ${entry.key}',
        );
      }
    });
  });

  group('a cart line', () {
    for (final entry in _boundaries.entries) {
      test('at ${entry.key}: unit ${entry.value}, total = quantity x unit', () {
        final line = _line(quantity: entry.key);
        expect(line.unitPrice, entry.value);
        expect(line.lineTotal, entry.key * entry.value);
      });
    }

    test('moves to the right rung whichever way the quantity crosses', () {
      var line = _line(quantity: 9);
      expect(line.unitPrice, 20);
      line = line.copyWith(quantity: 10);
      expect(line.unitPrice, 17, reason: 'up across 10');
      line = line.copyWith(quantity: 1000);
      expect(line.unitPrice, 11, reason: 'up across 100 and 1000');
      line = line.copyWith(quantity: 999);
      expect(line.unitPrice, 14, reason: 'down across 1000');
      line = line.copyWith(quantity: 1);
      expect(line.unitPrice, 20, reason: 'all the way back');
    });

    test('names the rung being charged', () {
      expect(_line(quantity: 9).appliedTierFrom, 1);
      expect(_line(quantity: 10).appliedTierFrom, 10);
      expect(_line(quantity: 150).appliedTierFrom, 100);
      expect(_line(quantity: 1000).appliedTierFrom, 1000);
      expect(_line(tiers: const []).appliedTierFrom, isNull);
    });

    test('without a ladder keeps the price it was added at', () {
      final line = _line(quantity: 500, tiers: const []);
      expect(line.unitPrice, 20);
      expect(line.lineTotal, 10000);
    });

    test('keeps its ladder through a save and a restore', () {
      final restored = CartLine.fromJson(_line(quantity: 100).toJson())!;
      expect(restored.tiers, hasLength(4));
      expect(restored.unitPrice, 14);
      expect(restored.copyWith(quantity: 9).unitPrice, 20);
    });

    test('a line saved before ladders existed still reads', () {
      final old = _line(tiers: const []).toJson()..remove('quantityTiers');
      final restored = CartLine.fromJson(old)!;
      expect(restored.tiers, isEmpty);
      expect(restored.unitPrice, 20);
    });
  });

  group('the cart', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AuthStore.instance.resetForTest();
      CartStore.instance.resetForTest();
      stubCatalog();
    });

    tearDown(clearApiStub);

    test('reprices a line the moment its quantity crosses a rung', () {
      CartStore.instance.add(_line(quantity: 9));
      final key = CartStore.instance.lines.single.key;

      CartStore.instance.increment(key);
      expect(CartStore.instance.lines.single.quantity, 10);
      expect(CartStore.instance.lines.single.unitPrice, 17);

      CartStore.instance.setQuantity(key, 1000);
      expect(CartStore.instance.lines.single.unitPrice, 11);
      expect(CartStore.instance.lines.single.lineTotal, 11000);

      CartStore.instance.decrement(key);
      expect(CartStore.instance.lines.single.unitPrice, 14);
    });
  });
}
