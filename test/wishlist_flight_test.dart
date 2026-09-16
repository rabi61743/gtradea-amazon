import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/search/widgets/product_result_card.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:gtradea_amazon/shared/motion/motion_curves.dart';
import 'package:gtradea_amazon/shared/widgets/app_bottom_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/catalog.dart';

/// The card and the bar together, which is what the flight needs: a heart to
/// leave from and a heart to land on, both really laid out.
Widget _page({
  required bool saved,
  required VoidCallback onToggle,
  required int savedCount,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 200,
          child: ProductResultCard(
            product: sampleProduct,
            saved: saved,
            onToggleSaved: onToggle,
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 0,
        onSelected: (_) {},
        savedCount: savedCount,
      ),
    ),
  );
}

Finder get _cardHeart => find.descendant(
  of: find.byType(ProductResultCard),
  matching: find.byIcon(Icons.favorite_border),
);

/// Hearts in the air: the ones drawn by the overlay, which are neither the
/// card's nor the bar's.
int _heartsInFlight(WidgetTester tester) {
  final all = tester.widgetList<Icon>(find.byIcon(Icons.favorite)).length;
  final inCard = find
      .descendant(
        of: find.byType(ProductResultCard),
        matching: find.byIcon(Icons.favorite),
      )
      .evaluate()
      .length;
  final inBar = find
      .descendant(
        of: find.byType(AppBottomNav),
        matching: find.byIcon(Icons.favorite),
      )
      .evaluate()
      .length;
  return all - inCard - inBar;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WishlistStore.instance.resetForTest();
  });

  testWidgets('saving sends a heart across the page and takes it away again', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _page(saved: false, onToggle: () => taps++, savedCount: 0),
    );
    await tester.pump();

    expect(_heartsInFlight(tester), 0, reason: 'nothing is flying at rest');

    await tester.tap(_cardHeart);
    await tester.pump();

    // The real wishlist action happens on the tap, not when the animation
    // finishes: the flight is never what saves anything.
    expect(taps, 1);

    // Mid-flight there is exactly one heart over the page.
    await tester.pump(const Duration(milliseconds: 400));
    expect(_heartsInFlight(tester), 1, reason: 'one heart, in the air');

    // And it is gone once the sequence ends -- no overlay left behind.
    await tester.pumpAndSettle();
    expect(_heartsInFlight(tester), 0, reason: 'removed when it lands');
  });

  testWidgets('the heart flies along an arc, not a straight line', (
    tester,
  ) async {
    await tester.pumpWidget(
      _page(saved: false, onToggle: () {}, savedCount: 0),
    );
    await tester.pump();

    final start = tester.getCenter(_cardHeart);
    final target = tester.getCenter(
      find.descendant(
        of: find.byType(AppBottomNav),
        matching: find.byIcon(Icons.favorite_border),
      ),
    );

    await tester.tap(_cardHeart);
    await tester.pump();

    final path = <Offset>[];
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      final flying = find.byWidgetPredicate(
        (w) => w is Icon && w.icon == Icons.favorite && w.size == 24,
      );
      if (flying.evaluate().isNotEmpty) path.add(tester.getCenter(flying));
    }
    expect(path.length, greaterThan(3), reason: 'it was seen in flight');

    // It rises above both ends before it comes down: a straight line between
    // a card in the middle of the page and a bar below it never would.
    final highest = path.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
    expect(
      highest,
      lessThan(start.dy - 40),
      reason: 'rose above the card heart',
    );
    expect(highest, lessThan(target.dy), reason: 'and above the bar');

    // And it travels the whole way across.
    expect(path.last.dx, closeTo(target.dx, 60));

    await tester.pumpAndSettle();
  });

  testWidgets('a second tap while it is flying does not send another', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _page(saved: false, onToggle: () => taps++, savedCount: 0),
    );
    await tester.pump();

    await tester.tap(_cardHeart);
    await tester.pump(const Duration(milliseconds: 200));

    // The card heart is filled and locked while its heart is away.
    final locked = find.descendant(
      of: find.byType(ProductResultCard),
      matching: find.byIcon(Icons.favorite),
    );
    await tester.tap(locked);
    await tester.tap(locked);
    await tester.pump(const Duration(milliseconds: 200));

    expect(taps, 1, reason: 'the wishlist was asked once');
    expect(_heartsInFlight(tester), 1, reason: 'one heart, not three');

    await tester.pumpAndSettle();
    expect(_heartsInFlight(tester), 0);
  });

  testWidgets('the card heart goes back to its outline afterwards', (
    tester,
  ) async {
    // The store is what says whether a product is saved; this only animates
    // the moment. With the card still told `saved: false`, it must end as it
    // began.
    await tester.pumpWidget(
      _page(saved: false, onToggle: () {}, savedCount: 0),
    );
    await tester.pump();

    await tester.tap(_cardHeart);
    await tester.pumpAndSettle();

    expect(_cardHeart, findsOneWidget);
  });

  testWidgets('un-saving is the plain toggle it always was', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _page(saved: true, onToggle: () => taps++, savedCount: 3),
    );
    await tester.pump();

    await tester.tap(
      find
          .descendant(
            of: find.byType(ProductResultCard),
            matching: find.byIcon(Icons.favorite),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(taps, 1);
    expect(_heartsInFlight(tester), 0, reason: 'nothing flies to the wishlist');
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion still saves, and still leaves nothing behind', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _page(saved: false, onToggle: () => taps++, savedCount: 0),
      ),
    );
    await tester.pump();

    await tester.tap(_cardHeart);
    await tester.pump();
    expect(taps, 1, reason: 'the real wishlist action is unconditional');

    await tester.pumpAndSettle();
    expect(_heartsInFlight(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the badge still shows the real count', (tester) async {
    await tester.pumpWidget(
      _page(saved: false, onToggle: () {}, savedCount: 4),
    );
    await tester.pump();

    expect(
      find.descendant(of: find.byType(AppBottomNav), matching: find.text('4')),
      findsOneWidget,
    );

    // And when the count grows, the number that appears is the new one.
    await tester.pumpWidget(
      _page(saved: false, onToggle: () {}, savedCount: 5),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBottomNav), matching: find.text('5')),
      findsOneWidget,
    );
  });

  group('the curves the interaction is drawn to', () {
    test('back.out(3) overshoots and returns', () {
      expect(backOut3.transform(0), closeTo(0, 0.001));
      expect(backOut3.transform(1), closeTo(1, 0.001));
      final peak = List.generate(
        100,
        (i) => backOut3.transform(i / 99),
      ).reduce((a, b) => a > b ? a : b);
      expect(peak, greaterThan(1.05), reason: 'it goes past its end');
    });

    test('elastic.out(1, 0.55) settles on one', () {
      expect(elasticOutSoft.transform(0), closeTo(0, 0.01));
      expect(elasticOutSoft.transform(1), closeTo(1, 0.01));
    });
  });
}
