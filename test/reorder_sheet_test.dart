import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/network/api_error.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/cart/presentation/cart_screen.dart';
import 'package:gtradea_amazon/features/checkout/presentation/checkout_screen.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/orders/data/reorder_validation.dart';
import 'package:gtradea_amazon/features/orders/presentation/order_detail_screen.dart';
import 'package:gtradea_amazon/features/orders/presentation/reorder_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/orders.dart';

/// Reordering, from the order screen through to the cart.
///
/// The rule under all of it: an old order is never the authority on what
/// something costs or whether it can be had. The previous build added the
/// order's own lines straight to the cart, so these tests are mostly about
/// what must *not* happen -- nothing added before the catalogue answers,
/// nothing added that the catalogue refused, and no price carried over.

const _jacket = CartLine(
  productId: 'p-1',
  variantLabel: 'Blush pink / S',
  title: 'Ice silk jacket',
  unitPrice: 1130,
  quantity: 2,
);

const _dress = CartLine(
  productId: 'p-2',
  variantLabel: 'Ivory / M',
  title: 'Suspender dress',
  unitPrice: 1808,
);

/// A product record, in the envelope's own shape.
Map<String, dynamic> detailJson({
  required String numIid,
  required String title,
  required String colour,
  String size = 'S',
  num price = 1130,
  int? stock = 50,
  int minOrder = 1,
}) => {
  'success': true,
  'item': {
    'num_iid': numIid,
    'title': title,
    'min_order_quantity': minOrder,
    'pic_url': 'https://example.invalid/$numIid.jpg',
    'skus': [
      {
        'sku_id': 'sku-$numIid',
        'spec_id': 'spec-$numIid',
        'quantity': stock,
        'image_url': 'https://example.invalid/$numIid.jpg',
        'variant_parts': [
          {'name': 'Color', 'value': colour},
          {'name': 'Size', 'value': size},
        ],
      },
    ],
  },
  'pricing': {
    'displayPrice': price,
    'skuPrices': {
      'sku-$numIid': {'displayPrice': price},
    },
  },
};

/// Answers the catalogue from a fixed table; anything missing is a 404.
void stubDetails(Map<String, Map<String, dynamic>> byId) {
  ReorderValidator.instance.fetch = (id) async {
    final body = byId[id];
    if (body == null) {
      throw const ApiError(statusCode: 404, message: 'not found');
    }
    return body;
  };
}

Future<void> _pump(WidgetTester tester, {required List<CartLine> lines}) async {
  tester.view.physicalSize = const Size(1100, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final order = seedOrder(
    reached: OrderStage.delivered,
    status: 'delivered',
    lines: lines,
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: OrderDetailScreen(orderId: order.id),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps something after making sure it is actually on screen.
Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

final _reorder = find.widgetWithText(FilledButton, 'Reorder');
final _buyAgain = find.byKey(const ValueKey('buy-again'));
final _checkout = find.widgetWithText(FilledButton, 'Checkout');
final _addToCart = find.widgetWithText(OutlinedButton, 'Add to cart');

/// Scoped to the sheet's own subtree.
///
/// The order screen behind it has a 'More' of its own -- the app bar's
/// overflow menu -- and an unscoped finder picks that one, which sits under
/// the sheet's barrier. The tap then lands on the barrier and dismisses the
/// sheet, so a test about a stepper fails several lines later complaining that
/// a button has vanished.
Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(ReorderSheet), matching: finder);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OrderStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    final api = stubCatalog();
    ApiClient.overrideDio = api.dio();
    stubDetails({
      'p-1': detailJson(numIid: 'p-1', title: 'Ice silk jacket', colour: 'Blush pink'),
      'p-2': detailJson(
        numIid: 'p-2',
        title: 'Suspender dress',
        colour: 'Ivory',
        size: 'M',
        price: 1808,
      ),
    });
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
    ReorderValidator.instance.fetch = (_) async => const {};
  });

  group('reordering a whole order', () {
    testWidgets('checks first, and adds nothing until it is confirmed', (
      tester,
    ) async {
      await _pump(tester, lines: const [_jacket, _dress]);

      await _tap(tester, _reorder);

      // The sheet is up and the cart is untouched. This is the whole point:
      // the old build had already written both lines by now.
      expect(find.byType(ReorderSheet), findsOneWidget);
      expect(CartStore.instance.lines, isEmpty);
      expect(find.text('2 of 2 ready'), findsOneWidget);
    });

    testWidgets('adds the checked lines, at the price the catalogue gave', (
      tester,
    ) async {
      // The listing has moved since the order was placed.
      stubDetails({
        'p-1': detailJson(
          numIid: 'p-1',
          title: 'Ice silk jacket',
          colour: 'Blush pink',
          price: 1260,
        ),
      });
      await _pump(tester, lines: const [_jacket]);

      await _tap(tester, _reorder);
      await _tap(tester, _addToCart);

      final [line] = CartStore.instance.lines;
      expect(line.basePrice, 1260, reason: 'today\'s price, not the order\'s');
      expect(line.quantity, 2);
      // Recovered from the live record. The order row never had a SKU.
      expect(line.skuId, 'sku-p-1');
      expect(find.byType(CartScreen), findsOneWidget);
    });

    testWidgets('shows both figures when a price has moved', (tester) async {
      stubDetails({
        'p-1': detailJson(
          numIid: 'p-1',
          title: 'Ice silk jacket',
          colour: 'Blush pink',
          price: 1260,
        ),
      });
      await _pump(tester, lines: const [_jacket]);

      await _tap(tester, _reorder);

      expect(find.text('Price went up'), findsOneWidget);
      // What it was and what it is, so the change is legible rather than a
      // number that quietly differs from the one on the order above it.
      expect(find.text('Rs. 1,130'), findsOneWidget);
      expect(find.text('Rs. 1,260'), findsOneWidget);
    });

    testWidgets('a withdrawn product is named and left out', (tester) async {
      // The dress is gone; the jacket is not.
      stubDetails({
        'p-1': detailJson(
          numIid: 'p-1',
          title: 'Ice silk jacket',
          colour: 'Blush pink',
        ),
      });
      await _pump(tester, lines: const [_jacket, _dress]);

      await _tap(tester, _reorder);

      expect(find.text('No longer available'), findsOneWidget);
      // The summary names the flagged count alongside the ready one, so this
      // reads "1 of 2 ready - 1 needs a look".
      expect(find.textContaining('1 of 2 ready'), findsOneWidget);

      await _tap(tester, _addToCart);

      // Only the one that could be bought. Nothing was substituted for the
      // other, and the reorder was not refused wholesale because of it.
      expect(CartStore.instance.lines, hasLength(1));
      expect(CartStore.instance.lines.single.productId, 'p-1');
    });

    testWidgets('an out-of-stock line cannot be added', (tester) async {
      stubDetails({
        'p-1': detailJson(
          numIid: 'p-1',
          title: 'Ice silk jacket',
          colour: 'Blush pink',
          stock: 0,
        ),
      });
      await _pump(tester, lines: const [_jacket]);

      await _tap(tester, _reorder);

      expect(find.text('Out of stock'), findsOneWidget);
      // Nothing to buy, so the way out is closed rather than leading to an
      // empty cart.
      expect(tester.widget<FilledButton>(_checkout).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(_addToCart).onPressed, isNull);
    });

    testWidgets('a variant that is gone is not swapped for another', (
      tester,
    ) async {
      // The listing is alive, but in ivory rather than blush pink.
      stubDetails({
        'p-1': detailJson(
          numIid: 'p-1',
          title: 'Ice silk jacket',
          colour: 'Ivory',
        ),
      });
      await _pump(tester, lines: const [_jacket]);

      await _tap(tester, _reorder);

      expect(find.text('Option no longer offered'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(_addToCart).onPressed, isNull);
    });

    testWidgets('dismissing it adds nothing at all', (tester) async {
      await _pump(tester, lines: const [_jacket, _dress]);

      await _tap(tester, _reorder);
      await _tap(tester, find.byTooltip('Close'));

      expect(find.byType(ReorderSheet), findsNothing);
      expect(CartStore.instance.lines, isEmpty);
    });

    testWidgets('a line can be dropped before confirming', (tester) async {
      await _pump(tester, lines: const [_jacket, _dress]);

      await _tap(tester, _reorder);
      await _tap(tester, _inSheet(find.byTooltip('Remove from this reorder')).first);
      await _tap(tester, _addToCart);

      expect(CartStore.instance.lines, hasLength(1));
    });

    testWidgets('the quantity can be changed before confirming', (
      tester,
    ) async {
      await _pump(tester, lines: const [_jacket]);

      await _tap(tester, _reorder);
      await _tap(tester, _inSheet(find.byTooltip('More')).first);
      await _tap(tester, _addToCart);

      expect(CartStore.instance.lines.single.quantity, 3);
    });

    testWidgets('Checkout goes to the existing checkout screen', (
      tester,
    ) async {
      await _pump(tester, lines: const [_jacket]);

      await _tap(tester, _reorder);
      await _tap(tester, _checkout);

      // The app's own checkout, with the cart's own totals -- not a second
      // one belonging to this feature.
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(CartStore.instance.lines, hasLength(1));
    });
  });

  group('buying one thing again', () {
    testWidgets('reorders only that line', (tester) async {
      await _pump(tester, lines: const [_jacket, _dress]);

      await _tap(tester, _buyAgain.first);

      expect(find.text('Buy again'), findsWidgets);
      expect(find.text('1 of 1 ready'), findsOneWidget);

      await _tap(tester, _addToCart);

      expect(CartStore.instance.lines, hasLength(1));
      expect(CartStore.instance.lines.single.productId, 'p-1');
    });

    testWidgets('twice merges rather than making a second line', (
      tester,
    ) async {
      // The cart's own rule, which this must go through rather than around.
      await _pump(tester, lines: const [_jacket]);

      for (var i = 0; i < 2; i++) {
        await _tap(tester, _buyAgain.first);
        await _tap(tester, _addToCart);
        // Back from the cart screen the first round pushed.
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      expect(CartStore.instance.lines, hasLength(1));
      expect(CartStore.instance.lines.single.quantity, 4, reason: '2 then 2');
    });
  });

  group('when the catalogue cannot be reached', () {
    testWidgets('says so, and does not call the goods discontinued', (
      tester,
    ) async {
      ReorderValidator.instance.fetch = (_) async =>
          throw const ApiError(statusCode: null, message: 'no connection');
      await _pump(tester, lines: const [_jacket]);

      await _tap(tester, _reorder);

      expect(find.text('Could not be checked'), findsOneWidget);
      expect(find.text('No longer available'), findsNothing);
      // Nothing is added on an unconfirmed price.
      expect(tester.widget<OutlinedButton>(_addToCart).onPressed, isNull);
      expect(CartStore.instance.lines, isEmpty);
    });
  });
}
