import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/cart/presentation/cart_recommendations.dart';
import 'package:gtradea_amazon/features/cart/presentation/cart_screen.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/search/widgets/product_result_card.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

/// The shelf under the cart answers the cart's own sub-categories.
///
/// The signal it used to run on was the line's category *name*, matched against
/// the department tree. Most of this catalogue's labels are leaves the tree does
/// not carry -- "Display rack", "flange" -- so the match failed and the shelf
/// showed a general feed. The line carries the catalogue's own id now, and
/// `/categories/{cid}/products` answers at that depth where
/// `/feed/trending-products` returns an empty list.

late FakeApi api;

/// A catalogue row from one sub-category, named so a test can tell them apart.
Map<String, dynamic> _row(String cid, int i) => {
  ...feedRowJson,
  'num_iid': '$cid-$i',
  'title': 'Product $cid-$i',
  'display_price': 400 + i,
  'category_cid': cid,
  'category_name': 'Category $cid',
};

CartLine _line(String id, {String? cid, String? name, int quantity = 1}) =>
    CartLine(
      productId: id,
      title: 'Cart $id',
      unitPrice: 500,
      quantity: quantity,
      category: name,
      categoryCid: cid,
    );

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1100, 3600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: const CartScreen()),
  );
  // The shelf really asks the catalogue, and debounces before it does.
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Finder _inShelf(Finder f) =>
    find.descendant(of: find.byType(CartRecommendations), matching: f);

/// Which sub-category endpoints were asked, in order.
List<String> _askedCids() => api.calls
    .where((c) => c.path.startsWith('/categories/'))
    .map((c) => c.path.split('/')[2])
    .toList();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    WishlistStore.instance.resetForTest();
    CatalogStore.instance.resetForTest();
    api = stubCatalog(products: 8);
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/cart', body: const {'items': []});
    api.on('GET', '/wishlist', body: const {'items': []});

    // Two sub-categories, each answering with its own products.
    api.onCall(
      'GET',
      '/categories/shoes-1/products',
      (_) => reply([for (var i = 0; i < 6; i++) _row('shoes-1', i)]),
    );
    api.onCall(
      'GET',
      '/categories/face-9/products',
      (_) => reply([for (var i = 0; i < 6; i++) _row('face-9', i)]),
    );
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  testWidgets('one product: the shelf is that product sub-category', (
    tester,
  ) async {
    CartStore.instance.add(_line('in-cart', cid: 'shoes-1', name: 'Running'));

    await _pump(tester);

    expect(
      _askedCids(),
      contains('shoes-1'),
      reason: 'asked the sub-category by its own id',
    );
    expect(_inShelf(find.textContaining('Product shoes-1')), findsWidgets);
  });

  testWidgets('two sub-categories: both get a say', (tester) async {
    CartStore.instance.add(_line('a', cid: 'shoes-1', name: 'Running'));
    CartStore.instance.add(_line('b', cid: 'face-9', name: 'Face care'));

    await _pump(tester);

    final asked = _askedCids();
    expect(asked, contains('shoes-1'));
    expect(asked, contains('face-9'));
    expect(_inShelf(find.textContaining('Product shoes-1')), findsWidgets);
    expect(_inShelf(find.textContaining('Product face-9')), findsWidgets);
  });

  testWidgets('the heavier sub-category is asked first', (tester) async {
    // Ordered by what is actually being bought, not by insertion.
    CartStore.instance.add(_line('a', cid: 'shoes-1', name: 'Running'));
    CartStore.instance.add(
      _line('b', cid: 'face-9', name: 'Face care', quantity: 9),
    );

    await _pump(tester);

    final asked = _askedCids();
    expect(asked.first, 'face-9', reason: 'nine beats one');
  });

  testWidgets('removing a product recalculates', (tester) async {
    CartStore.instance.add(_line('a', cid: 'shoes-1', name: 'Running'));
    CartStore.instance.add(_line('b', cid: 'face-9', name: 'Face care'));
    await _pump(tester);

    final before = _askedCids().length;
    CartStore.instance.remove(CartStore.instance.lines.last.key);
    await _pump(tester);

    expect(
      _askedCids().length,
      greaterThan(before),
      reason: 'the cart changed, so the shelf asked again',
    );
  });

  testWidgets('a line with no sub-category still falls back', (tester) async {
    // Anything added before the id was carried, or from the history screens.
    // The shelf must still show something rather than going blank.
    CartStore.instance.add(_line('old', name: 'Some department'));

    await _pump(tester);

    expect(_askedCids(), isEmpty, reason: 'no id to ask with');
    expect(_inShelf(find.byType(ProductResultCard)), findsWidgets);
  });

  testWidgets('an empty cart uses the general feed', (tester) async {
    await _pump(tester);

    expect(_askedCids(), isEmpty);
    expect(_inShelf(find.byType(ProductResultCard)), findsWidgets);
  });

  testWidgets('what is already in the cart is not recommended back', (
    tester,
  ) async {
    // The sub-category answer contains the very product that asked for it.
    CartStore.instance.add(_line('shoes-1-0', cid: 'shoes-1', name: 'Running'));

    await _pump(tester);

    expect(
      _inShelf(find.text('Product shoes-1-0')),
      findsNothing,
      reason: 'already in the basket',
    );
    expect(_inShelf(find.textContaining('Product shoes-1-')), findsWidgets);
  });
}
