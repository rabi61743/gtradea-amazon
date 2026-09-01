import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/home/widgets/product_grid.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

/// The live shape: `/api/1688/product` answers with a **1688** leaf category,
/// which is a different id space from the storefront cid the search index puts
/// on a card.
Map<String, dynamic> _detailBody({String? categoryId = '122698007'}) => {
  ...detailResponseJson,
  'item': {
    ...Map<String, dynamic>.from(
      detailResponseJson['item'] as Map<String, dynamic>,
    ),
    'category_id': ?categoryId,
    'category_name': 'Electric water heater',
  },
};

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/api/1688/product', body: _detailBody());
    api.on('GET', '/site-settings', body: const {});
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductDetailScreen(product: sampleProduct),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// The shelf sits at the foot of a long page, so it is not built until it
  /// is scrolled to.
  Future<void> scrollToEnd(WidgetTester tester) async {
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 20; i++) {
      await tester.drag(scrollable, const Offset(0, -600));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  group('more like this', () {
    testWidgets('asks the endpoint that can read a 1688 category', (
      tester,
    ) async {
      // The bug: the record's `category_id` is a 1688 leaf, and
      // `/categories/{cid}/products` indexes the storefront's own cids. It
      // answers an id it does not know with `200 []` rather than an error, so
      // the shelf was never drawn on any product opened from search.
      api.on('GET', '/api/1688/search', body: {'items': feedRows(6)});
      api.on('GET', '/categories/122698007/products', body: const []);

      await pump(tester);

      final keyword = api.calls.where(
        (c) => c.path.contains('/api/1688/search'),
      );
      expect(keyword, isNotEmpty, reason: 'the id it holds is a 1688 one');
      expect(keyword.first.query['category_id'], '122698007');
    });

    testWidgets('draws the products it gets back', (tester) async {
      api.on('GET', '/api/1688/search', body: {'items': feedRows(6)});

      await pump(tester);
      await scrollToEnd(tester);

      expect(find.byType(ProductGrid), findsOneWidget);
      expect(find.text('Catalogue product 0'), findsOneWidget);
    });

    testWidgets('falls back to the storefront cid when 1688 has nothing', (
      tester,
    ) async {
      // A listing whose 1688 category is empty, but whose card came from the
      // cached index and so carries a storefront cid worth trying.
      api.on('GET', '/api/1688/search', body: {'items': const []});
      api.on('GET', '/categories/124262012/products', body: feedRows(4));

      await pump(tester);
      await scrollToEnd(tester);

      expect(
        api.calls.where((c) => c.path.contains('/categories/')),
        isNotEmpty,
        reason: 'the second id space is tried before giving up',
      );
      expect(find.byType(ProductGrid), findsOneWidget);
    });

    testWidgets('a category nobody can serve draws no empty shelf', (
      tester,
    ) async {
      api.on('GET', '/api/1688/search', body: {'items': const []});
      api.on('GET', '/categories/124262012/products', body: const []);

      await pump(tester);
      await scrollToEnd(tester);

      expect(find.byType(ProductGrid), findsNothing);
    });

    testWidgets('a non-numeric category is never sent to the keyword feed', (
      tester,
    ) async {
      // It drops a `category_id` it cannot parse and answers with whatever an
      // empty query returns -- a shelf of unrelated products under the wrong
      // heading, which is worse than no shelf.
      api.on(
        'GET',
        '/api/1688/product',
        body: _detailBody(categoryId: 'uuid-shaped'),
      );
      api.on('GET', '/api/1688/search', body: {'items': feedRows(6)});
      api.on('GET', '/categories/124262012/products', body: const []);

      await pump(tester);
      await scrollToEnd(tester);

      expect(
        api.calls.where((c) => c.path.contains('/api/1688/search')),
        isEmpty,
      );
    });
  });
}
