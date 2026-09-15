import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/data/product_repository.dart';
import 'package:gtradea_amazon/features/product/data/storefront_config.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/product_detail_skeleton.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

late FakeApi api;

/// A second product, so "the one before" is a real thing and not the same row
/// under another name.
Map<String, dynamic> get _otherRow => {
  ...feedRowJson,
  'num_iid': '111222333444',
  'title': 'Beeswax Candles, Boxed in Fifties',
  'display_price': 940,
};

Map<String, dynamic> get _otherDetail => {
  'success': true,
  'item': {
    ...detailResponseJson['item']! as Map<String, dynamic>,
    'num_iid': '111222333444',
    'title': 'Beeswax Candles, Boxed in Fifties',
    'props': [
      {'name': 'Material', 'value': 'Beeswax'},
    ],
  },
  'pricing': {'displayPrice': 940},
};

Product get _other => Product.fromJson(_otherRow);

/// The detail endpoint, answering after [delay] for whichever id is asked for.
void _stubDetail({Duration? delay}) {
  api.onCall('GET', '/api/1688/product', (call) {
    final id = call.query['num_iid'];
    final body = id == '111222333444' ? _otherDetail : detailResponseJson;
    return reply(body, delay: delay);
  });
}

Future<void> _pump(WidgetTester tester, Product product) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProductDetailScreen(product: product),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CartStore.instance.resetForTest();
    StorefrontConfigRepository.instance.resetForTest();
    ProductRepository.instance.clearDetailCache();
  });

  tearDown(() {
    ProductRepository.instance.clearDetailCache();
    ProductRepository.instance.now = DateTime.now;
    clearApiStub();
  });

  group('while the record is being fetched', () {
    testWidgets('the page is a skeleton, not the row it was opened from', (
      tester,
    ) async {
      _stubDetail(delay: const Duration(seconds: 2));
      await _pump(tester, sampleProduct);

      expect(find.byType(ProductDetailSkeleton), findsOneWidget);
      // Not even this product's own title: the record decides what the page
      // says, and until it lands the page says nothing about any product.
      expect(find.textContaining('Phosphorus Paper'), findsNothing);
      expect(find.textContaining('Rs. 388'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailSkeleton), findsNothing);
      expect(find.textContaining('Phosphorus Paper'), findsWidgets);
    });

    testWidgets('and nothing of the product looked at before it', (
      tester,
    ) async {
      // The heart of it: A is on screen, B is opened, and B must never wear
      // A's title, price or facts while its own are in flight.
      _stubDetail();
      await _pump(tester, sampleProduct);
      await tester.pumpAndSettle();
      expect(find.textContaining('Phosphorus Paper'), findsWidgets);

      _stubDetail(delay: const Duration(seconds: 2));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProductDetailScreen(product: _other),
        ),
      );
      await tester.pump();

      expect(find.byType(ProductDetailSkeleton), findsOneWidget);
      expect(find.textContaining('Phosphorus Paper'), findsNothing);
      expect(find.text('Phosphorus paper'), findsNothing);
      expect(find.textContaining('Rs. 388'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.textContaining('Beeswax Candles'), findsWidgets);
      expect(find.textContaining('Phosphorus'), findsNothing);
    });

    testWidgets('the buy bar waits for a price rather than showing one', (
      tester,
    ) async {
      _stubDetail(delay: const Duration(seconds: 2));
      await _pump(tester, sampleProduct);

      final buy = find.widgetWithText(ElevatedButton, 'Buy');
      expect(buy, findsOneWidget);
      expect(tester.widget<ElevatedButton>(buy).onPressed, isNull);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.textContaining('Buy · Rs.'), findsOneWidget);
    });

    testWidgets('a failure falls back to the row, with the reason', (
      tester,
    ) async {
      // The one case where the card's own data is better than nothing: the
      // record could not be fetched at all.
      api.on(
        'GET',
        '/api/1688/product',
        status: 500,
        body: const {'message': 'The catalogue is unavailable.'},
      );
      await _pump(tester, sampleProduct);
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailSkeleton), findsNothing);
      expect(find.textContaining('Phosphorus Paper'), findsWidgets);
      expect(find.textContaining('catalogue is unavailable'), findsOneWidget);
    });
  });

  group('the fetch itself', () {
    testWidgets('asks for the product that was opened, by its own id', (
      tester,
    ) async {
      _stubDetail();
      await _pump(tester, _other);
      await tester.pumpAndSettle();

      final asked = api.calls
          .where((c) => c.path == '/api/1688/product')
          .toList();
      expect(asked, hasLength(1));
      expect(asked.single.query['num_iid'], '111222333444');
    });

    testWidgets('and asks once, however many pages want the same record', (
      tester,
    ) async {
      // Two callers at the same moment share one request rather than making
      // two of the same.
      _stubDetail(delay: const Duration(milliseconds: 300));
      await _pump(tester, sampleProduct);

      unawaited(ProductRepository.instance.prefetchDetail('639278524639'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        api.calls.where((c) => c.path == '/api/1688/product'),
        hasLength(1),
      );
    });

    testWidgets('a record just fetched is reused, so reopening is instant', (
      tester,
    ) async {
      _stubDetail();
      await _pump(tester, sampleProduct);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, sampleProduct);
      await tester.pumpAndSettle();

      expect(
        api.calls.where((c) => c.path == '/api/1688/product'),
        hasLength(1),
        reason: 'the second open was served from what was just fetched',
      );
      expect(find.textContaining('Phosphorus Paper'), findsWidgets);
    });

    testWidgets('but a stale one is not: the cache expires', (tester) async {
      var clock = DateTime(2026, 9, 6, 12);
      ProductRepository.instance.now = () => clock;
      _stubDetail();

      await _pump(tester, sampleProduct);
      await tester.pumpAndSettle();

      clock = clock.add(ProductRepository.cacheTtl * 2);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, sampleProduct);
      await tester.pumpAndSettle();

      expect(
        api.calls.where((c) => c.path == '/api/1688/product'),
        hasLength(2),
        reason: 'a price an hour old is not one to show as current',
      );
    });
  });
}
