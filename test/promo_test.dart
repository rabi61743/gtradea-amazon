import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';

import 'support/auth.dart';

import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/cart/presentation/cart_screen.dart';
import 'package:gtradea_amazon/features/promo/data/coupon.dart';
import 'package:gtradea_amazon/features/promo/data/coupon_store.dart';
import 'package:gtradea_amazon/features/promo/presentation/coupon_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rs. 1,130 of Fashion.
const _jacket = CartLine(
  productId: 'jacket',
  variantLabel: 'Blush pink',
  title: 'Ice silk jacket',
  unitPrice: 1130,
  listPrice: 1568,
  freeDelivery: true,
  category: 'Fashion',
);

/// Rs. 4,000 of Electronics.
const _headphones = CartLine(
  productId: 'headphones',
  title: 'Headphones',
  unitPrice: 4000,
  category: 'Electronics',
);

/// No category at all, as a line saved before categories existed would be.
const _untagged = CartLine(
  productId: 'mystery',
  title: 'Something old',
  unitPrice: 2500,
);

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void _useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Coupon _coupon(String code) => CouponContent.byCode(code)!;

void main() {
  setUp(() async {
    CouponStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    // Let the previous test's fire-and-forget writes land BEFORE wiping the
    // store. Clearing first lets a late write put the old coupon back, and the
    // next test then loads a basket that already has one on it.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    SharedPreferences.setMockInitialValues({});
  });

  group('the offers themselves', () {
    test('codes are unique and match themselves case-insensitively', () {
      final codes = CouponContent.all.map((c) => c.code).toList();
      expect(codes.toSet().length, codes.length);
      expect(CouponContent.byCode('dashain20')?.code, 'DASHAIN20');
      expect(CouponContent.byCode('  DASHAIN20 ')?.code, 'DASHAIN20');
      expect(CouponContent.byCode('NOPE'), isNull);
    });

    test('a percentage discount respects its cap', () {
      final coupon = _coupon('DASHAIN20');
      // 20% of 4,000 is 800, but the offer caps at 500.
      expect(coupon.discountFor([_headphones]), 500);
      // 20% of 1,130 is 226, under the cap, so it is taken in full.
      expect(coupon.discountFor([_jacket]), 226);
    });

    test('a fixed discount never exceeds the basket', () {
      const tiny = CartLine(
        productId: 'x',
        title: 'Small thing',
        unitPrice: 120,
      );
      // Rs. 200 off a Rs. 120 basket takes 120, and certainly hands back
      // nothing.
      expect(_coupon('WELCOME200').discountFor([tiny]), 120);
    });

    test('a category coupon discounts only its own lines', () {
      final coupon = _coupon('FASHION15');
      // 15% of the jacket alone, not of the jacket plus the headphones.
      expect(coupon.discountFor([_jacket, _headphones]), 170);
      expect(coupon.discountFor([_headphones]), 0);
    });

    test('an untagged line matches no category coupon', () {
      expect(_coupon('FASHION15').discountFor([_untagged]), 0);
      // A sitewide offer still applies to it.
      expect(_coupon('WELCOME200').discountFor([_untagged]), 200);
    });

    test('discounts are whole rupees', () {
      final discount = _coupon('FASHION15').discountFor([_jacket]);
      expect(discount, discount.roundToDouble());
    });
  });

  group('applying a code', () {
    test('a good code goes on and reports what it saved', () {
      final outcome = CouponStore.instance.apply('DASHAIN20', [
        _jacket,
        _headphones,
      ]);

      expect(outcome, isA<CouponApplied>());
      expect((outcome as CouponApplied).discount, 500);
      expect(CouponStore.instance.applied?.code, 'DASHAIN20');
    });

    test('lower case and stray spaces still work', () {
      final outcome = CouponStore.instance.apply('  dashain20 ', [
        _jacket,
        _headphones,
      ]);
      expect(outcome, isA<CouponApplied>());
    });

    test('an unknown code is named back so the shopper can check it', () {
      final outcome = CouponStore.instance.apply('NOTREAL', [_jacket]);
      expect(outcome, isA<CouponUnknown>());
      expect((outcome as CouponUnknown).code, 'NOTREAL');
      expect(CouponStore.instance.hasApplied, isFalse);
    });

    test('an expired code is refused as expired', () {
      final outcome = CouponStore.instance.apply('TIHAR50', [_jacket]);
      expect(outcome, isA<CouponExpired>());
    });

    test('a spent code is refused as already used', () {
      CouponStore.instance.redeem('DASHAIN20');
      final outcome = CouponStore.instance.apply('DASHAIN20', [
        _jacket,
        _headphones,
      ]);
      expect(outcome, isA<CouponAlreadyUsed>());
    });

    test('a short basket is told how much short', () {
      // WELCOME200 needs 2,000 and the jacket is 1,130.
      final outcome = CouponStore.instance.apply('WELCOME200', [_jacket]);

      expect(outcome, isA<CouponBelowMinimum>());
      // "Spend Rs. 870 more" beats "spend more".
      expect((outcome as CouponBelowMinimum).shortfall, 870);
    });

    test('a category coupon is refused when nothing qualifies', () {
      final outcome = CouponStore.instance.apply('ELECTRO10', [_jacket]);
      expect(outcome, isA<CouponNotApplicable>());
    });

    test(
      'the minimum is judged on the whole basket, not the eligible part',
      () {
        // FASHION15 needs an order of 1,000. The jacket alone is 1,130, so it
        // qualifies -- and the discount still only touches the jacket.
        final outcome = CouponStore.instance.apply('FASHION15', [_jacket]);
        expect(outcome, isA<CouponApplied>());
        expect((outcome as CouponApplied).discount, 170);
      },
    );

    test('a second code is refused while one is on', () {
      CouponStore.instance.apply('DASHAIN20', [_jacket, _headphones]);
      final outcome = CouponStore.instance.apply('WELCOME200', [
        _jacket,
        _headphones,
      ]);

      expect(outcome, isA<CouponConflict>());
      expect((outcome as CouponConflict).existing.code, 'DASHAIN20');
      expect(
        CouponStore.instance.applied?.code,
        'DASHAIN20',
        reason: 'the first one stays put',
      );
    });

    test('the conflict is reported before anything else about the new code', () {
      CouponStore.instance.apply('DASHAIN20', [_jacket, _headphones]);
      // TIHAR50 is expired too. Saying so would send the shopper hunting for a
      // third code when the real problem is the one already applied.
      final outcome = CouponStore.instance.apply('TIHAR50', [_jacket]);
      expect(outcome, isA<CouponConflict>());
    });

    test('reapplying the code already on is not a conflict', () {
      CouponStore.instance.apply('DASHAIN20', [_jacket, _headphones]);
      final outcome = CouponStore.instance.apply('DASHAIN20', [
        _jacket,
        _headphones,
      ]);
      expect(outcome, isA<CouponApplied>());
    });

    test('removing takes it off', () {
      CouponStore.instance.apply('DASHAIN20', [_jacket, _headphones]);
      CouponStore.instance.remove();
      expect(CouponStore.instance.hasApplied, isFalse);
    });
  });

  group('the basket moving underneath a coupon', () {
    test('a basket that drops below the minimum loses the coupon', () {
      CouponStore.instance.apply('WELCOME200', [_jacket, _headphones]);
      expect(CouponStore.instance.hasApplied, isTrue);

      // The headphones come out and the basket is 1,130, under the 2,000
      // minimum. A discount that quietly stayed would be a price the shop
      // could not honour.
      final dropped = CouponStore.instance.revalidate([_jacket]);
      expect(dropped?.code, 'WELCOME200');
      expect(CouponStore.instance.hasApplied, isFalse);
    });

    test('an emptied basket loses the coupon', () {
      CouponStore.instance.apply('DASHAIN20', [_jacket, _headphones]);
      expect(CouponStore.instance.revalidate([])?.code, 'DASHAIN20');
    });

    test('a basket that still qualifies keeps it', () {
      CouponStore.instance.apply('DASHAIN20', [_jacket, _headphones]);
      expect(CouponStore.instance.revalidate([_jacket, _headphones]), isNull);
      expect(CouponStore.instance.hasApplied, isTrue);
    });
  });

  group('what it does to the total', () {
    test('the discount comes off, and VAT follows it down', () {
      final totals = CartTotals.of(
        [_jacket],
        discount: 130,
        couponCode: 'TEST',
      );

      expect(totals.subtotal, 1130);
      expect(totals.discount, 130);
      expect(totals.total, 1000, reason: 'free delivery on this line');
      // VAT is inside what is actually charged for goods. Quoting the
      // pre-discount figure would overstate the tax on the receipt.
      expect(totals.vatIncluded.round(), 115);
      expect(totals.couponCode, 'TEST');
    });

    test('a discount can never exceed the basket', () {
      final totals = CartTotals.of([_jacket], discount: 99999);
      expect(totals.discount, 1130);
      expect(totals.total, 0, reason: 'never negative, never a refund');
    });

    test('no coupon means no discount line and no code', () {
      final totals = CartTotals.of([_jacket]);
      expect(totals.discount, 0);
      expect(totals.couponCode, isNull);
    });

    test('a zero discount does not claim a code', () {
      final totals = CartTotals.of([_jacket], discount: 0, couponCode: 'X');
      expect(
        totals.couponCode,
        isNull,
        reason: 'a named line taking off nothing reads as a bug',
      );
    });

    test('savings and discount stay separate', () {
      final totals = CartTotals.of([_jacket], discount: 100);
      // The jacket already had 438 off the list price. Rolling that into the
      // coupon line would let one order claim the same rupee twice.
      expect(totals.savings, 438);
      expect(totals.discount, 100);
    });

    test('the cart store folds the applied coupon into its totals', () {
      CartStore.instance.add(_jacket);
      CartStore.instance.add(_headphones);
      CouponStore.instance.apply('DASHAIN20', CartStore.instance.lines);

      final totals = CartStore.instance.totals;
      expect(totals.discount, 500);
      expect(totals.couponCode, 'DASHAIN20');
      // Goods less the discount. No delivery is added until the server has
      // quoted one, which it has not here.
      expect(totals.total, 5130 - 500);
    });
  });

  group('persistence and identity', () {
    test('what is applied and what is spent survives a reload', () async {
      CouponStore.instance.apply('DASHAIN20', [_jacket, _headphones]);
      CouponStore.instance.redeem('WELCOME200');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      CouponStore.instance.resetForTest();
      await CouponStore.instance.load();

      expect(CouponStore.instance.applied?.code, 'DASHAIN20');
      expect(CouponStore.instance.hasUsed('WELCOME200'), isTrue);
    });

    test('a corrupt store degrades to nothing applied', () async {
      SharedPreferences.setMockInitialValues({'gtradea_coupons': 'not json'});
      CouponStore.instance.resetForTest();
      await CouponStore.instance.load();
      expect(CouponStore.instance.hasApplied, isFalse);
    });

    test('a stored code that no longer exists is ignored', () async {
      SharedPreferences.setMockInitialValues({
        'gtradea_coupons': '{"applied":"RETIRED99","used":[]}',
      });
      CouponStore.instance.resetForTest();
      await CouponStore.instance.load();
      // A pulled offer must not keep discounting.
      expect(CouponStore.instance.hasApplied, isFalse);
    });

    test('signing up does not reset a one-per-shopper offer', () async {
      CouponStore.instance.redeem('DASHAIN20');
      CouponStore.instance.bindToAuth();

      signInForTest(email: 'rabi@example.com');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        CouponStore.instance.hasUsed('DASHAIN20'),
        isTrue,
        reason: 'creating an account is not a way to claim it twice',
      );
    });

    test('redeeming takes the code off the basket', () {
      CouponStore.instance.apply('DASHAIN20', [_jacket, _headphones]);
      CouponStore.instance.redeem('DASHAIN20');

      expect(
        CouponStore.instance.hasApplied,
        isFalse,
        reason: 'the next order must not silently reuse it',
      );
    });
  });

  group('the cart screen', () {
    Future<void> pumpCart(WidgetTester tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const CartScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('offers a code field and a way to browse', (tester) async {
      CartStore.instance.add(_jacket);
      await pumpCart(tester);

      expect(find.text('Offers and coupons'), findsOneWidget);
      expect(find.text('Enter a promo code'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
      expect(find.text('View offers'), findsOneWidget);
    });

    testWidgets('Apply is dead until there is something to apply', (
      tester,
    ) async {
      CartStore.instance.add(_jacket);
      await pumpCart(tester);

      final before = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply'),
      );
      expect(before.onPressed, isNull);

      await tester.enterText(find.byType(TextField).last, 'DASHAIN20');
      await tester.pumpAndSettle();

      final after = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply'),
      );
      expect(after.onPressed, isNotNull);
    });

    testWidgets('a good code updates the total in place', (tester) async {
      CartStore.instance.add(_jacket);
      CartStore.instance.add(_headphones);
      await pumpCart(tester);

      expect(
        find.text('Rs. 5,130'),
        findsWidgets,
        reason: 'goods only; freight is not quoted yet',
      );

      await tester.enterText(find.byType(TextField).last, 'DASHAIN20');
      // Apply is disabled until the field has something in it, so the button
      // needs a frame to catch up before it can be tapped.
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      expect(find.textContaining('DASHAIN20 applied'), findsOneWidget);
      expect(find.text('Coupon DASHAIN20'), findsOneWidget);
      expect(find.text('-Rs. 500'), findsOneWidget);
      expect(find.text('Rs. 4,630'), findsWidgets, reason: '5,130 less 500');
    });

    testWidgets('a refused code says why, in words that help', (tester) async {
      CartStore.instance.add(_jacket);
      await pumpCart(tester);

      await tester.enterText(find.byType(TextField).last, 'WELCOME200');
      // Apply is disabled until the field has something in it, so the button
      // needs a frame to catch up before it can be tapped.
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Spend Rs. 870 more'), findsOneWidget);
      expect(find.text('Coupon WELCOME200'), findsNothing);
    });

    testWidgets('an applied code can be removed and the total goes back', (
      tester,
    ) async {
      CartStore.instance.add(_jacket);
      CartStore.instance.add(_headphones);
      await pumpCart(tester);

      await tester.enterText(find.byType(TextField).last, 'DASHAIN20');
      // Apply is disabled until the field has something in it, so the button
      // needs a frame to catch up before it can be tapped.
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Remove'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Coupon DASHAIN20'), findsNothing);
      expect(find.text('Rs. 5,130'), findsWidgets);
    });

    testWidgets('emptying the cart under a coupon drops it and says so', (
      tester,
    ) async {
      CartStore.instance.add(_jacket);
      CartStore.instance.add(_headphones);
      await pumpCart(tester);

      await tester.enterText(find.byType(TextField).last, 'WELCOME200');
      // Apply is disabled until the field has something in it, so the button
      // needs a frame to catch up before it can be tapped.
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(CouponStore.instance.hasApplied, isTrue);

      // Take the headphones out: 1,130 left, under the 2,000 minimum.
      CartStore.instance.remove(_headphones.key);
      await tester.pumpAndSettle();

      expect(CouponStore.instance.hasApplied, isFalse);
      expect(
        find.textContaining('WELCOME200 no longer applies'),
        findsOneWidget,
      );
    });
  });

  group('the offers sheet', () {
    testWidgets('shows the terms on the card, not behind a link', (
      tester,
    ) async {
      _useTallWindow(tester);
      await tester.pumpWidget(
        _wrap(const Scaffold(body: CouponSheet(lines: [_jacket, _headphones]))),
      );
      await tester.pumpAndSettle();

      expect(find.text('DASHAIN20'), findsOneWidget);
      expect(find.text('20% off'), findsOneWidget);
      // Two offers share this minimum.
      expect(find.text('Min Rs. 1,000'), findsWidgets);
      expect(find.text('Up to Rs. 500'), findsOneWidget);
      expect(find.text('All departments'), findsWidgets);
      expect(find.text('One per shopper'), findsWidgets);
    });

    testWidgets('an offer that cannot be used says why on its own card', (
      tester,
    ) async {
      _useTallWindow(tester);
      // A jacket only: WELCOME200 needs 2,000 and ELECTRO10 needs electronics.
      await tester.pumpWidget(
        _wrap(const Scaffold(body: CouponSheet(lines: [_jacket]))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Add Rs. 870 more'), findsOneWidget);
      expect(find.textContaining('Nothing from Electronics'), findsOneWidget);
      expect(find.text('This offer has ended'), findsOneWidget);
    });

    testWidgets('a usable offer shows what it would save', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(
        _wrap(const Scaffold(body: CouponSheet(lines: [_jacket, _headphones]))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Saves Rs. 500'), findsOneWidget);
    });

    testWidgets('tapping Apply returns the code to the caller', (tester) async {
      _useTallWindow(tester);
      String? chosen;

      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  chosen = await CouponSheet.show(
                    context,
                    lines: const [_jacket, _headphones],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply').first);
      await tester.pumpAndSettle();

      expect(chosen, isNotNull);
      expect(CouponContent.byCode(chosen!), isNotNull);
    });
  });
}
