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
import 'support/fake_api.dart';

late FakeApi api;

/// A phone-width window: under the width where the grid goes past two
/// columns, and wide enough that the test font does not overflow its text.
Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1100, 3600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: const CartScreen()),
  );
  // The shelf asks the catalogue for real, so let the requests run.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Finder _inShelf(Finder f) =>
    find.descendant(of: find.byType(CartRecommendations), matching: f);

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
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  testWidgets('two to a row, down the page, under its heading', (
    tester,
  ) async {
    await _pump(tester);

    expect(_inShelf(find.text('Recommended for You')), findsOneWidget);

    final cards = _inShelf(find.byType(ProductResultCard));
    expect(cards.evaluate().length, greaterThanOrEqualTo(3));

    final first = tester.getRect(cards.at(0));
    final second = tester.getRect(cards.at(1));
    final third = tester.getRect(cards.at(2));

    // Exactly two on the first row, the third starting the next one.
    expect(second.top, first.top, reason: 'side by side');
    expect(second.left, greaterThan(first.right));
    expect(third.top, greaterThan(first.bottom), reason: 'a new row');
    expect(third.left, first.left);

    // Small gaps both ways.
    expect(second.left - first.right, lessThanOrEqualTo(8));
    expect(third.top - first.bottom, lessThanOrEqualTo(8));

    // Down the page, not along a rail.
    final horizontal = _inShelf(
      find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      ),
    );
    expect(horizontal, findsNothing);

    // Using the page's width: the pair spans about 97% of it.
    final screen = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect((second.right - first.left) / screen, closeTo(0.97, 0.01));
  });

  testWidgets('a failed request says so and offers to try again', (
    tester,
  ) async {
    api.on('GET', '/feed/discover', status: 500, body: const {});

    await _pump(tester);

    expect(_inShelf(find.text('Recommended for You')), findsOneWidget);
    expect(
      _inShelf(find.text('Recommendations could not be loaded.')),
      findsOneWidget,
    );
    // The app's own failure panel, with its own button.
    expect(_inShelf(find.text('Try again')), findsOneWidget);
  });
}
