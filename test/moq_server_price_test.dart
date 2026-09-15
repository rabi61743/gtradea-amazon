import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

/// Test data only; real ladders come from each product's record.
const _ladder = [
  QuantityTier(minQuantity: 1, price: 20),
  QuantityTier(minQuantity: 10, price: 17),
  QuantityTier(minQuantity: 100, price: 14),
  QuantityTier(minQuantity: 1000, price: 11),
];

late FakeApi api;

/// The account's cart as the fake server holds it: one row, repriced by the
/// server's own ladder whenever its quantity is patched -- which is what the
/// live server was measured doing.
Map<String, dynamic>? _row;
List<QuantityTier> _serverLadder = _ladder;

CartLine _line({List<QuantityTier> tiers = _ladder, int quantity = 9}) =>
    CartLine(
      productId: '536875038426',
      title: 'Adult diapers, L',
      unitPrice: 20,
      quantity: quantity,
      source: '1688',
      tiers: tiers,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    api = stubCatalog();
    signInForTest();
    ApiClient.overrideDio = api.dio();
    _row = null;
    _serverLadder = _ladder;

    api.onCall(
      'GET',
      '/cart',
      (_) => reply({
        'items': [?_row],
      }),
    );
    api.onCall('POST', '/cart', (call) {
      final quantity = call.json['quantity'] as int;
      _row = {
        'id': 'c-1',
        'source': '1688',
        'source_product_id': call.json['source_product_id'],
        'quantity': quantity,
        'product_data': {
          ...(call.json['product_data'] as Map).cast<String, dynamic>(),
          'price': tierPriceAt(_serverLadder, 20, quantity),
        },
      };
      return reply(_row);
    });
    api.onCall('PATCH', '/cart/c-1', (call) {
      final quantity = call.json['quantity'] as int;
      _row = {
        ..._row!,
        'quantity': quantity,
        'product_data': {
          ...(_row!['product_data'] as Map).cast<String, dynamic>(),
          'price': tierPriceAt(_serverLadder, 20, quantity),
        },
      };
      return reply(_row);
    });
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  Future<CartLine> raiseTo(int quantity) async {
    final key = CartStore.instance.lines.single.key;
    CartStore.instance.setQuantity(key, quantity);
    await CartStore.instance.flushSyncForTest();
    return CartStore.instance.lines.single;
  }

  test('the cart and the server agree across every boundary', () async {
    CartStore.instance.add(_line());
    await CartStore.instance.flushSyncForTest();

    for (final (quantity, price) in const [
      (10, 17),
      (99, 17),
      (100, 14),
      (999, 14),
      (1000, 11),
      (9, 20),
    ]) {
      final line = await raiseTo(quantity);
      expect(line.unitPrice, price, reason: 'at $quantity');
      expect(
        (_row!['product_data'] as Map)['price'],
        price,
        reason: 'the server charges the same at $quantity',
      );
      expect(line.lineTotal, quantity * price);
    }
  });

  test("the server's price wins over a stale ladder", () async {
    CartStore.instance.add(_line());
    await CartStore.instance.flushSyncForTest();

    // The seller moved the 10+ rung since this device stored the ladder.
    _serverLadder = const [
      QuantityTier(minQuantity: 1, price: 20),
      QuantityTier(minQuantity: 10, price: 16),
    ];
    final line = await raiseTo(10);

    expect(line.unitPrice, 16, reason: 'what checkout will charge');
    expect(line.tiers, isEmpty, reason: 'the stale ladder is not trusted');
  });

  test('a line added without a ladder still ends on the server price', () async {
    CartStore.instance.add(_line(tiers: const []));
    await CartStore.instance.flushSyncForTest();

    final line = await raiseTo(100);
    expect(line.unitPrice, 14);
    expect(line.lineTotal, 1400);
  });
}
