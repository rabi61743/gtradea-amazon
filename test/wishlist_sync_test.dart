import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

const _polo = SavedProduct(
  id: '825709571788',
  title: 'Quick-drying polo',
  price: 554,
  category: 'Men',
);

/// A saved row as `GET /wishlist` returns it.
Map<String, dynamic> _row(
  String id, {
  required String sourceProductId,
  String name = 'Electric kettle',
  num price = 1800,
}) => {
  'id': id,
  'source': '1688',
  'source_product_id': sourceProductId,
  'category': 'Home',
  'product_data': {'name': name, 'price': price, 'image': null},
};

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    WishlistStore.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  test(
    'a guest list stays on the device and asks the server nothing',
    () async {
      WishlistStore.instance.toggle(_polo);
      await WishlistStore.instance.sync();

      expect(WishlistStore.instance.contains(_polo.id), isTrue);
      expect(
        api.calls.where((c) => c.path.contains('/wishlist')),
        isEmpty,
        reason: 'a guest has no account list to write to',
      );
    },
  );

  test('signing in pushes what is on the device to the account', () async {
    signInForTest();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/wishlist', body: const {'items': []});
    api.on('POST', '/wishlist', body: const {'id': 'w-1'});

    WishlistStore.instance.toggle(_polo);
    await WishlistStore.instance.sync();

    final sent = api.calls.lastWhere(
      (c) => c.method == 'POST' && c.path == '/wishlist',
    );
    final body = sent.body as Map;
    expect(body['source_product_id'], _polo.id);
    expect(body['category'], 'Men');
    expect((body['product_data'] as Map)['name'], 'Quick-drying polo');
    expect(WishlistStore.instance.syncError, isNull);
  });

  test('and adopts what the account already holds from elsewhere', () async {
    signInForTest();
    ApiClient.overrideDio = api.dio();
    api.on(
      'GET',
      '/wishlist',
      body: {
        'items': [_row('w-9', sourceProductId: '1122334455')],
      },
    );

    await WishlistStore.instance.sync();

    // Saved on a laptop, and here it is on the phone.
    expect(WishlistStore.instance.contains('1122334455'), isTrue);
    expect(WishlistStore.instance.items.single.title, 'Electric kettle');
  });

  test(
    'a removal is told to the account, by the row id it gave back',
    () async {
      signInForTest();
      ApiClient.overrideDio = api.dio();
      api.on(
        'GET',
        '/wishlist',
        body: {
          'items': [_row('w-9', sourceProductId: '1122334455')],
        },
      );
      api.on('DELETE', '/wishlist/w-9', status: 204);

      await WishlistStore.instance.sync();
      WishlistStore.instance.remove('1122334455');
      // The write is fire-and-forget, as the local one is; give it the turns
      // it needs to reach the account.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        api.calls.where(
          (c) => c.method == 'DELETE' && c.path == '/wishlist/w-9',
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'a list that cannot be saved is kept, and the failure is said',
    () async {
      signInForTest();
      ApiClient.overrideDio = api.dio();
      api.on('GET', '/wishlist', status: 500, body: const {});

      WishlistStore.instance.toggle(_polo);
      await WishlistStore.instance.sync();

      // What the shopper saved is still on screen; it just is not stored yet.
      expect(WishlistStore.instance.contains(_polo.id), isTrue);
      expect(WishlistStore.instance.syncError, isNotNull);
    },
  );
}
