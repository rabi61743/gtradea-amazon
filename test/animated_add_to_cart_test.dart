import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/product/widgets/animated_add_to_cart_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

Widget _button({
  required Future<bool> Function() onAdd,
  bool reducedMotion = false,
}) => MaterialApp(
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: 200,
          child: AnimatedAddToCartButton(onAdd: onAdd),
        ),
      ),
    ),
  ),
);

final _shirt = find.byWidgetPredicate(
  (w) =>
      w is CustomPaint &&
      w.painter.runtimeType.toString() == '_FoldedShirtPainter',
);

void main() {
  group('the button', () {
    testWidgets('at rest: cart and label, nothing moving', (tester) async {
      await tester.pumpWidget(_button(onAdd: () async => true));

      expect(find.text('Add to cart'), findsOneWidget);
      expect(find.byIcon(Icons.add_shopping_cart), findsOneWidget);
      expect(_shirt, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('success waits for the add to be confirmed', (tester) async {
      final confirm = Completer<bool>();
      await tester.pumpWidget(_button(onAdd: () => confirm.future));

      await tester.tap(find.text('Add to cart'));
      // The animation's clock starts on its first frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      // The shirt is on its way down.
      expect(_shirt, findsOneWidget);

      // The whole drop has played; the server has not answered yet.
      await tester.pump(AnimatedAddToCartButton.dropDuration);
      expect(find.text('Added to cart'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      confirm.complete(true);
      await tester.pump();
      await tester.pump(AnimatedAddToCartButton.successDuration);
      expect(find.text('Added to cart'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      // Ready again afterwards.
      await tester.pump(AnimatedAddToCartButton.holdSuccess);
      expect(find.text('Add to cart'), findsOneWidget);
      expect(find.text('Added to cart'), findsNothing);
    });

    testWidgets('a refused add goes back to rest, never to Added', (
      tester,
    ) async {
      await tester.pumpWidget(_button(onAdd: () async => false));

      await tester.tap(find.text('Add to cart'));
      await tester.pump(AnimatedAddToCartButton.dropDuration);
      await tester.pump(AnimatedAddToCartButton.successDuration);

      expect(find.text('Added to cart'), findsNothing);
      expect(find.text('Add to cart'), findsOneWidget);
    });

    testWidgets('taps during the drop do not add twice', (tester) async {
      var calls = 0;
      final confirm = Completer<bool>();
      await tester.pumpWidget(
        _button(
          onAdd: () {
            calls++;
            return confirm.future;
          },
        ),
      );

      await tester.tap(find.text('Add to cart'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);
      expect(calls, 1);

      confirm.complete(true);
      await tester.pump(AnimatedAddToCartButton.dropDuration);
      await tester.pump(AnimatedAddToCartButton.successDuration);
      await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);
      expect(calls, 1, reason: 'not while Added is showing either');
      await tester.pump(AnimatedAddToCartButton.holdSuccess);
    });

    testWidgets('reduced motion: no drop, still a clear Added', (tester) async {
      await tester.pumpWidget(
        _button(onAdd: () async => true, reducedMotion: true),
      );

      await tester.tap(find.text('Add to cart'));
      await tester.pump();
      await tester.pump();
      expect(_shirt, findsNothing);
      expect(find.text('Added to cart'), findsOneWidget);
      await tester.pump(AnimatedAddToCartButton.holdSuccess);
    });

    testWidgets('keeps a proper touch target', (tester) async {
      await tester.pumpWidget(_button(onAdd: () async => true));
      expect(
        tester.getSize(find.byType(OutlinedButton)).height,
        greaterThanOrEqualTo(44),
      );
    });
  });

  group('on the product page, against the real cart', () {
    late FakeApi api;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AuthStore.instance.resetForTest();
      CartStore.instance.resetForTest();
      api = stubCatalog();
    });

    tearDown(clearApiStub);

    Future<void> openPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProductDetailScreen(
            product: sampleProduct,
            detail: sampleDetail,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<void> playOut(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    testWidgets('signed in: Added only after the account has the line', (
      tester,
    ) async {
      signInForTest();
      ApiClient_useStub(api);
      api.onCall('POST', '/cart', (call) => reply({...call.json, 'id': 's1'}));

      await openPage(tester);
      await tester.tap(find.text('Add to cart'));
      await playOut(tester);

      expect(
        api.calls.where((c) => c.method == 'POST' && c.path == '/cart'),
        hasLength(1),
      );
      final line = CartStore.instance.lines.single;
      expect(line.serverId, 's1');
      expect(line.variantLabel, 'Red', reason: 'the selected option');
      expect(line.quantity, 2, reason: 'the page quantity, MOQ respected');
      expect(find.text('Added to cart'), findsOneWidget);
      await tester.pump(AnimatedAddToCartButton.holdSuccess);
    });

    testWidgets('signed in: a failed save never says Added', (tester) async {
      signInForTest();
      ApiClient_useStub(api);
      api.on('POST', '/cart', status: 500, body: const {'message': 'boom'});

      await openPage(tester);
      await tester.tap(find.text('Add to cart'));
      await playOut(tester);

      expect(find.text('Added to cart'), findsNothing);
      expect(find.text('Add to cart'), findsOneWidget);
      expect(
        find.textContaining('Added to Cart'),
        findsNothing,
        reason: 'no success message either',
      );
    });

    testWidgets('a guest: the device cart is the cart', (tester) async {
      await openPage(tester);
      await tester.tap(find.text('Add to cart'));
      await playOut(tester);

      expect(CartStore.instance.lines.single.quantity, 2);
      expect(find.text('Added to cart'), findsOneWidget);
      expect(api.calls.where((c) => c.path.startsWith('/cart')), isEmpty);
      await tester.pump(AnimatedAddToCartButton.holdSuccess);
    });
  });
}

/// signInForTest parks a stub of its own; the page's cart has to talk to this
/// test's server.
// ignore: non_constant_identifier_names
void ApiClient_useStub(FakeApi api) => useStubbedApi(api);
