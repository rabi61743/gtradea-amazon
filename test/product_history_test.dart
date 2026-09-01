import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/account/data/product_views_repository.dart';
import 'package:gtradea_amazon/features/account/presentation/product_history_screen.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

Widget _wrap() =>
    MaterialApp(theme: AppTheme.light, home: const ProductHistoryScreen());

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// A row in the shape this app writes them.
Map<String, dynamic> _view({
  String id = '900001',
  String name = 'boAt Rockerz 550',
  String? viewedAt,
  num? price,
}) => {
  'source': '1688',
  'source_product_id': id,
  'viewed_at': viewedAt ?? DateTime.now().toUtc().toIso8601String(),
  'product_data': {
    'name': name,
    'image_url': 'https://example.invalid/a.jpg',
    'price_label': 'Rs. 3,999',
    'price': ?price,
    'category': 'Over Ear Headphones',
  },
};

void main() {
  late FakeApi api;

  void signIn() {
    signInForTest();
    ApiClient.overrideDio = api.dio();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    OrderStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/product-views', body: const []);
    api.on('GET', '/orders', body: const []);
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    OrderStore.instance.resetForTest();
    clearApiStub();
  });

  group('reading the history', () {
    test('is read from the route the app already writes to', () async {
      // The app has posted a view on every product open since it shipped and
      // never read it back. This is that read.
      signIn();
      api.on('GET', '/product-views', body: [_view()]);

      final views = await ProductViewsRepository.instance.list();

      expect(api.calls.single.path, contains('/product-views'));
      final one = views.single;
      expect(one.productId, '900001');
      expect(one.title, 'boAt Rockerz 550');
      expect(one.priceLabel, 'Rs. 3,999');
      expect(one.category, 'Over Ear Headphones');
      expect(one.imageUrl, isNotNull);
    });

    test('newest first, whatever order the server sent', () async {
      signIn();
      api.on(
        'GET',
        '/product-views',
        body: [
          _view(id: 'old', name: 'Older', viewedAt: '2026-01-01T00:00:00Z'),
          _view(id: 'new', name: 'Newer', viewedAt: '2026-08-30T00:00:00Z'),
        ],
      );

      final views = await ProductViewsRepository.instance.list();
      expect(views.map((v) => v.productId), ['new', 'old']);
    });

    test('a row with no product id is dropped, not made unopenable', () async {
      signIn();
      api.on(
        'GET',
        '/product-views',
        body: [
          {
            'product_data': {'name': 'No id'},
          },
        ],
      );

      expect(await ProductViewsRepository.instance.list(), isEmpty);
    });

    test('removing one names the product it is removing', () async {
      signIn();
      api.on('DELETE', '/product-views', status: 204);

      await ProductViewsRepository.instance.remove('900001');

      final sent = api.calls.single;
      expect(sent.method, 'DELETE');
      expect(sent.query['source_product_id'], '900001');
    });

    test('clearing names nothing, which is what clears the lot', () async {
      signIn();
      api.on('DELETE', '/product-views', status: 204);

      await ProductViewsRepository.instance.clear();

      expect(api.calls.single.query, isEmpty);
    });
  });

  group('the Product History page', () {
    testWidgets('shows both tabs and the history under date headings', (
      tester,
    ) async {
      signIn();
      api.on('GET', '/product-views', body: [_view()]);
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Product History'), findsOneWidget);
      expect(find.text('Recently Viewed'), findsOneWidget);
      expect(find.text('Recently Purchased'), findsOneWidget);
      // The heading the reference shows over the newest group.
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('boAt Rockerz 550'), findsOneWidget);
      expect(find.text('Over Ear Headphones'), findsOneWidget);
      expect(find.text('Rs. 3,999'), findsOneWidget);
      expect(find.text('Add to cart'), findsWidgets);
    });

    testWidgets('opens the product that was tapped, by its own id', (
      tester,
    ) async {
      signIn();
      api.on(
        'GET',
        '/product-views',
        body: [
          _view(id: '900001', name: 'First thing'),
          _view(id: '900002', name: 'Second thing'),
        ],
      );
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Second thing'));
      await tester.pumpAndSettle();

      final opened = tester.widget<ProductDetailScreen>(
        find.byType(ProductDetailScreen),
      );
      expect(opened.product.numIid, '900002');
      expect(opened.product.title, 'Second thing');
    });

    testWidgets('searching narrows the list', (tester) async {
      signIn();
      api.on(
        'GET',
        '/product-views',
        body: [
          _view(id: '1', name: 'boAt Rockerz 550'),
          _view(id: '2', name: 'Adidas Grand Court'),
        ],
      );
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'adidas');
      await tester.pumpAndSettle();

      expect(find.text('Adidas Grand Court'), findsOneWidget);
      expect(find.text('boAt Rockerz 550'), findsNothing);
    });

    testWidgets('says so when there is no history yet', (tester) async {
      signIn();
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Products you open will appear here.'), findsOneWidget);
    });

    testWidgets('a guest is asked to sign in, not shown an empty history', (
      tester,
    ) async {
      // The history is the account's. "Nothing here" would be a lie to
      // somebody whose history sits under an account they are signed out of.
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.textContaining('Sign in to see'), findsOneWidget);
      expect(
        api.calls.where((c) => c.path.contains('/product-views')),
        isEmpty,
      );
    });

    testWidgets('a failure offers a retry rather than an empty history', (
      tester,
    ) async {
      signIn();
      api.on('GET', '/product-views', status: 500, body: const {});
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Products you open will appear here.'), findsNothing);
    });

    testWidgets('a swipe forgets one, and tells the server', (tester) async {
      signIn();
      api.on('GET', '/product-views', body: [_view(name: 'boAt Rockerz 550')]);
      api.on('DELETE', '/product-views', status: 204);
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.drag(find.text('boAt Rockerz 550'), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.text('boAt Rockerz 550'), findsNothing);
      expect(
        api.calls.where((c) => c.method == 'DELETE'),
        isNotEmpty,
        reason: 'or it returns on the next open',
      );
    });
  });
}
