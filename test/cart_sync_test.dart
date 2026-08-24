import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/promo/data/coupon_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

const _polo = CartLine(
  productId: '825709571788',
  variantLabel: 'Green / M',
  title: 'Quick-drying polo',
  unitPrice: 554,
  quantity: 2,
  source: '1688',
  skuId: 'sku-green-m',
  specId: 'spec-green-m',
  category: 'Men',
);

const _kettle = CartLine(
  productId: '1122334455',
  title: 'Electric kettle',
  unitPrice: 1800,
  source: '1688',
);

/// A cart row as `GET /cart` returns it.
Map<String, dynamic> row(
  String id, {
  required String sourceProductId,
  int quantity = 1,
  String? variantLabel,
  num price = 554,
  String name = 'Quick-drying polo',
}) =>
    {
      'id': id,
      'quantity': quantity,
      'source': '1688',
      'source_product_id': sourceProductId,
      'variant_label': variantLabel,
      'product_data': {'name': name, 'price': price, 'image': null},
    };

/// Runs whatever sync is pending, without waiting out the debounce.
///
/// Sleeping past a wall-clock timer makes these flaky the moment the machine
/// is loaded, and a flaky test about money is worse than no test.
Future<void> settleSync() => CartStore.instance.flushSyncForTest();

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clearApiStub();
    CartStore.instance.resetForTest();
    CouponStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    api = stubCatalog();
  });

  tearDown(() {
    ApiClient.overrideDio = null;
  });

  group('a guest cart', () {
    test('stays on the device and touches no endpoint', () async {
      CartStore.instance.add(_polo);
      await settleSync();

      expect(CartStore.instance.count, 2);
      expect(CartStore.instance.isGuestCart, isTrue);
      expect(api.calls.where((c) => c.path.startsWith('/cart')), isEmpty);
    });
  });

  group('signing in', () {
    test('carries the guest cart into the account', () async {
      // The sibling app throws a guest cart away at sign-in. Someone who filled
      // a basket and then signed in to pay would watch it empty.
      final created = <String>[];
      api.onCall('POST', '/cart', (call) {
        created.add(call.json['source_product_id'] as String);
        return reply({...call.json, 'id': 'srv-${created.length}'});
      });

      CartStore.instance.add(_polo);
      CartStore.instance.add(_kettle);

      signInForTest();
      await CartStore.instance.switchIdentity('rabi@example.com');
      await settleSync();

      expect(created, containsAll([_polo.productId, _kettle.productId]));
      expect(CartStore.instance.lineCount, 2);
    });

    test('sends the source explicitly rather than defaulting it', () async {
      // The server routes an order for an imported product differently from a
      // local one, so a default here would send local products down the import
      // path.
      api.onCall('POST', '/cart', (call) => reply({...call.json, 'id': 's1'}));

      CartStore.instance.add(_polo);
      signInForTest();
      await CartStore.instance.switchIdentity('rabi@example.com');
      await settleSync();

      final post = api.calls.firstWhere((c) => c.method == 'POST');
      expect(post.json['source'], '1688');
      expect(post.json['source_product_id'], _polo.productId);
      expect(post.json['product_id'], isNull);
    });

    test('sends the chosen SKU, not just the colour name', () async {
      // The order the server places upstream is against a SKU. A label alone
      // would not identify what to buy.
      api.onCall('POST', '/cart', (call) => reply({...call.json, 'id': 's1'}));

      CartStore.instance.add(_polo);
      signInForTest();
      await CartStore.instance.switchIdentity('rabi@example.com');
      await settleSync();

      final data = (api.calls.firstWhere((c) => c.method == 'POST').json
          ['product_data'] as Map);
      expect(data['skuId'], 'sku-green-m');
      expect(data['specId'], 'spec-green-m');
      expect(data['name'], 'Quick-drying polo');
      expect(data['price'], 554);
    });

    test('does not add a product the account already holds', () async {
      // Added on the web, then signed in on the phone holding the same thing.
      // Adding it again would silently double the order.
      api.on('GET', '/cart', body: {
        'items': [
          row('srv-1', sourceProductId: _polo.productId,
              variantLabel: 'Green / M', quantity: 2),
        ],
      });
      var posts = 0;
      api.onCall('POST', '/cart', (call) {
        posts++;
        return reply({...call.json, 'id': 'srv-new'});
      });
      api.on('PATCH', '/cart/srv-1', status: 204);

      CartStore.instance.add(_polo);
      signInForTest();
      await CartStore.instance.switchIdentity('rabi@example.com');
      await settleSync();

      expect(posts, 0);
      expect(CartStore.instance.lineCount, 1);
    });

    test('an empty guest cart just takes the account cart', () async {
      api.on('GET', '/cart', body: {
        'items': [row('srv-9', sourceProductId: '999', quantity: 3)],
      });

      signInForTest();
      await CartStore.instance.switchIdentity('rabi@example.com');
      await settleSync();

      expect(CartStore.instance.lineCount, 1);
      expect(CartStore.instance.count, 3);
      expect(CartStore.instance.lines.single.serverId, 'srv-9');
    });
  });

  group('while signed in', () {
    setUp(() async {
      api.onCall('POST', '/cart', (call) => reply({...call.json, 'id': 'srv-1'}));
      signInForTest();
      await CartStore.instance.switchIdentity('rabi@example.com');
    });

    test('a quantity change reaches the server', () async {
      CartStore.instance.add(_polo);
      await settleSync();

      api.on('GET', '/cart', body: {
        'items': [
          row('srv-1', sourceProductId: _polo.productId,
              variantLabel: 'Green / M', quantity: 2),
        ],
      });
      api.on('PATCH', '/cart/srv-1', status: 204);

      CartStore.instance.setQuantity(_polo.key, 5);
      await settleSync();

      final patch = api.calls.lastWhere((c) => c.method == 'PATCH');
      expect(patch.path, '/cart/srv-1');
      expect(patch.json['quantity'], 5);
    });

    test('a removal deletes the row rather than leaving it behind', () async {
      api.on('GET', '/cart', body: {
        'items': [
          row('srv-1', sourceProductId: _polo.productId,
              variantLabel: 'Green / M', quantity: 2),
        ],
      });
      api.on('DELETE', '/cart/srv-1', status: 204);

      await CartStore.instance.refreshFromServer();
      expect(CartStore.instance.lineCount, 1);

      CartStore.instance.remove(CartStore.instance.lines.single.key);
      await settleSync();

      expect(api.calls.any((c) => c.method == 'DELETE' && c.path == '/cart/srv-1'),
          isTrue);
    });

    test('the change stays on screen when the server refuses it', () async {
      // Rolling back would take away what the shopper just did because of a
      // dropped connection. The cart is kept and the failure is reported.
      CartStore.instance.add(_polo);
      await settleSync();

      api.on('GET', '/cart', status: 500, body: {'error': 'cart is down'});

      CartStore.instance.setQuantity(_polo.key, 4);
      await settleSync();

      expect(CartStore.instance.lineFor(_polo.productId, 'Green / M')?.quantity,
          4);
      expect(CartStore.instance.syncError?.message, 'cart is down');
    });

    test('a retry clears the failure once the server comes back', () async {
      CartStore.instance.add(_polo);
      await settleSync();

      api.on('GET', '/cart', status: 500, body: {'error': 'cart is down'});
      CartStore.instance.setQuantity(_polo.key, 4);
      await settleSync();
      expect(CartStore.instance.syncError, isNotNull);

      api.on('GET', '/cart', body: const {'items': []});
      await CartStore.instance.retrySync();

      expect(CartStore.instance.syncError, isNull);
    });

    test('a failed refresh keeps the cached cart rather than emptying it',
        () async {
      // An empty cart shown because the network failed reads as "we lost your
      // things", which is the worst possible way to be wrong here.
      CartStore.instance.add(_polo);
      await settleSync();

      api.on('GET', '/cart', status: 503, body: {'error': 'down'});
      await CartStore.instance.refreshFromServer();

      expect(CartStore.instance.lineCount, 1);
      expect(CartStore.instance.syncError, isNotNull);
    });
  });

  group('adopting the account cart', () {
    test('a row the server sends thin keeps the local snapshot', () async {
      // The server stores the snapshot, but an older row may predate a field.
      // Falling back to what this device remembers beats rendering "Item".
      signInForTest();
      CartStore.instance.add(_polo);

      api.on('GET', '/cart', body: {
        'items': [
          {
            'id': 'srv-1',
            'quantity': 2,
            'source': '1688',
            'source_product_id': _polo.productId,
            'variant_label': 'Green / M',
            'product_data': const <String, dynamic>{},
          },
        ],
      });

      await CartStore.instance.refreshFromServer();

      final line = CartStore.instance.lines.single;
      expect(line.title, 'Quick-drying polo');
      expect(line.unitPrice, 554);
      expect(line.serverId, 'srv-1');
    });

    test('a local catalogue row is read from its joined product', () async {
      signInForTest();
      api.on('GET', '/cart', body: {
        'items': [
          {
            'id': 'srv-2',
            'quantity': 1,
            'source': 'local',
            'product_id': 'local-7',
            'product': {'name': 'Local thing', 'price': 240},
          },
        ],
      });

      await CartStore.instance.refreshFromServer();

      final line = CartStore.instance.lines.single;
      expect(line.title, 'Local thing');
      expect(line.unitPrice, 240);
      expect(line.source, 'local');
    });
  });
}
