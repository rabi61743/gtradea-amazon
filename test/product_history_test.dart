import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/features/account/presentation/recent_views_section.dart';
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
      expect(find.text('boAt Rockerz 550'), findsWidgets);
      // The card's category line, and the section's detail line under it.
      expect(find.text('Over Ear Headphones'), findsWidgets);
      expect(find.text('Rs. 3,999'), findsWidgets);
      expect(find.text('Buy Now'), findsWidgets);
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

      // The history card, not its echo in the section below the list.
      await tester.tap(find.text('Second thing').first);
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

      expect(find.text('Adidas Grand Court'), findsWidgets);
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

    testWidgets('follows the viewed tab, without asking the server again', (
      tester,
    ) async {
      signIn();
      api.on(
        'GET',
        '/product-views',
        body: [
          _view(id: '1', name: 'boAt Rockerz 550', price: 3999),
          _view(id: '2', name: 'Cordless Drill Machine', price: 5490),
        ],
      );
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // No strip at the head of the section any more; the rows are it.
      expect(find.text('Your recent searches, all in one place'), findsNothing);
      // One row per product, and one fetch behind them.
      expect(find.text('boAt Rockerz 550'), findsOneWidget);
      expect(
        api.calls.where((c) => c.path.contains('/product-views')).length,
        1,
        reason: 'the section draws what the screen already holds',
      );
    });

    testWidgets('bones stand in for the rows while the history is fetched', (
      tester,
    ) async {
      signIn();
      // Held open, so the page can be looked at mid-fetch.
      api.onCall(
        'GET',
        '/product-views',
        (_) => reply([
          _view(name: 'boAt Rockerz 550'),
        ], delay: const Duration(seconds: 2)),
      );
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.byType(RecentViewsSkeleton), findsOneWidget);
      // Shaped like the row it stands in for, not a spinner.
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(RecentViewsSkeleton), findsNothing);
      expect(find.text('boAt Rockerz 550'), findsOneWidget);
    });

    testWidgets('the price is Trust Blue and a badge is Commerce Orange', (
      tester,
    ) async {
      signIn();
      api.on('GET', '/product-views', body: [_view(price: 2850)]);
      api.onCall(
        'GET',
        '/api/1688/product',
        (_) => reply({
          'item': {'num_iid': '900001', 'total_sold': 12000},
          'pricing': {'displayPrice': 2850},
        }),
      );
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final price = tester.widget<Text>(find.text('Rs. 2,850'));
      expect(price.style?.color, AppColors.trustBlue);

      // The subcategory tag, in Cosmic Orange.
      final tag = tester.widget<Text>(find.text('Over Ear Headphones'));
      expect(tag.style?.color, AppColors.commerceOrange);

      // And Buy Now is filled in the same blue as the price.
      final buy = tester.widget<FilledButton>(
        find
            .ancestor(
              of: find.text('Buy Now'),
              matching: find.byType(FilledButton),
            )
            .first,
      );
      expect(
        buy.style?.backgroundColor?.resolve(<WidgetState>{}),
        AppColors.trustBlue,
      );
    });

    testWidgets('every card is 97% of the page, centred in it', (tester) async {
      signIn();
      api.on('GET', '/product-views', body: [_view(name: 'boAt Rockerz 550')]);
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final page = tester.getSize(find.byType(ProductHistoryScreen)).width;

      // The history card, and the row in the section under it.
      final cards = tester
          .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .map((box) => box.widthFactor)
          .toSet();
      expect(cards, {0.97});

      // The rows are the list now; the Card is the purchased tab's.
      final card = tester.getRect(
        find
            .ancestor(
              of: find.text('boAt Rockerz 550'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(card.width, closeTo(page * 0.97, 0.5));
      expect(card.left, closeTo(page - card.right, 0.5));
    });

    testWidgets('and honours the search box the screen already has', (
      tester,
    ) async {
      signIn();
      api.on(
        'GET',
        '/product-views',
        body: [
          _view(id: '1', name: 'boAt Rockerz 550', price: 3999),
          _view(id: '2', name: 'Cordless Drill Machine', price: 5490),
        ],
      );
      _tall(tester);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'drill');
      await tester.pumpAndSettle();

      // Search behaviour is untouched; the section simply shows what is left.
      expect(find.text('boAt Rockerz 550'), findsNothing);
      expect(find.text('Cordless Drill Machine'), findsOneWidget);
    });
  });
}
