import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/cart/presentation/cart_screen.dart';
import 'package:gtradea_amazon/features/cart/widgets/cart_summary.dart';
import 'package:gtradea_amazon/features/catalog/presentation/browse_screen.dart';
// The cart's coupon block. Deliberately this one and not the home page's
// widget of the same name, which is a different class and keeps its own lift.
import 'package:gtradea_amazon/features/promo/presentation/promo_section.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/auth.dart';
import 'support/fake_api.dart';

late FakeApi api;

/// A line with a price, so it is one the saved list can hold.
const _polo = CartLine(
  productId: '5566778899',
  title: 'Quick-drying polo',
  unitPrice: 554,
  quantity: 2,
);

/// And one without, which cannot be filed under a figure nobody published.
const _unpriced = CartLine(
  productId: '9090909090',
  title: 'Made-to-order banner',
  unitPrice: 0,
  quantity: 1,
);

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(420, 1600),
}) async {
  tester.view.physicalSize = Size(size.width * 2, size.height * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: const CartScreen()),
  );
  await tester.pumpAndSettle();
}

/// The two actions. The whole card is the button, so each is found by the
/// words on it.
final _save = find.text('Save all to wishlist');
final _shop = find.text('Continue shopping');

/// The third, added with the Future Cart page: the way to what the shop
/// thinks comes next. Drawn by the same `_ActionCard` as the other two, so it
/// is the same deliberate exception to the sweep below.
final _future = find.text('Future Cart');

/// The card an action's words sit on.
Finder _cardOf(Finder words) =>
    find.ancestor(of: words, matching: find.byType(Card)).first;

/// Taps a button after making sure it is on the screen.
///
/// The cards sit under however many lines the cart holds, which on a short
/// viewport can be past the fold -- and a tap at a point outside the viewport
/// lands on nothing rather than failing.
Future<void> _tap(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    WishlistStore.instance.resetForTest();
    api = stubCatalog();
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/cart', body: const {'items': []});
    api.on('GET', '/wishlist', body: const {'items': []});
    api.on('POST', '/wishlist', body: const {'id': 'w-1'});
    // Echoed back with an id, the way the live gateway answers: a reply that
    // drops the product the line stands for makes the account's copy
    // unrecognisable and the reconcile throws the line away.
    api.onCall('POST', '/cart', (call) => reply({...call.json, 'id': 'c-1'}));
    api.on('DELETE', '/cart/c-1', status: 204);
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  group('the two action cards', () {
    testWidgets('each is one card that is the button, with a line on it', (
      tester,
    ) async {
      CartStore.instance.add(_polo);
      await _pump(tester);

      for (final words in [_save, _shop]) {
        expect(words, findsOneWidget);
        // Inside a card of the theme's own, not a bare row of buttons -- and
        // the card itself answers the tap, not only the words on it.
        expect(_cardOf(words), findsOneWidget);
        expect(
          find.descendant(of: _cardOf(words), matching: find.byType(InkWell)),
          findsWidgets,
        );
      }

      // The supporting lines: what each does, in the shopper's terms.
      expect(find.textContaining('saved list'), findsWidgets);
      expect(find.textContaining('browsing products'), findsOneWidget);
    });

    testWidgets('the rest of the page takes the theme\'s card shape', (
      tester,
    ) async {
      // Every other card on the page takes its corner from the theme -- they
      // are the page's cards, which keeps them consistent when the theme
      // moves. The action cards are the deliberate exception: filled, flat,
      // and on the theme's corner.
      //
      // Three of them now rather than two. Future Cart joined Save and
      // Continue shopping, drawn by the same `_ActionCard`, so it is excluded
      // here for the same reason they are -- what this sweep is actually about
      // is the page's own cards, and that rule is unchanged.
      //
      // Elevation is no longer part of this sweep. The line cards are flat by
      // request and say so themselves; the rule they still keep is the corner,
      // and the test below pins the flatness so it cannot quietly come back.
      CartStore.instance.add(_polo);
      await _pump(tester);

      final actions = [
        _cardOf(_save),
        _cardOf(_shop),
        _cardOf(_future),
      ].map((f) => tester.widget<Card>(f)).toSet();
      final cards = tester
          .widgetList<Card>(find.byType(Card))
          .where((card) => !actions.contains(card));
      expect(cards, isNotEmpty);
      for (final card in cards) {
        expect(card.shape, isNull, reason: 'shape comes from the theme');
      }
    });

    testWidgets('the line, the coupon block and the summary are all flat', (
      tester,
    ) async {
      // The theme gives every Card an elevation of 1. Down a cart that is a
      // column of blocks, the shadows read as a pile of floating slips rather
      // than one page, so the three that make up the page turn it off. The
      // border and the corner are the theme's and stay: with the shadow gone
      // they are what separates one block from the next.
      //
      // The line card went flat first; the coupon block and the summary
      // followed by request. This test used to assert the opposite of that
      // last part -- "the summary still lifts" -- so it is rewritten rather
      // than dropped, and the two-shadow page it described is now the thing
      // it would catch.
      CartStore.instance.add(_polo);
      await _pump(tester);

      Card cardAround(Finder inner) => tester.widget<Card>(
        find.ancestor(of: inner, matching: find.byType(Card)).first,
      );

      // The coupon block is the other way up. PromoSection *returns* the Card,
      // so the card is inside it rather than above it -- searching upwards
      // from it finds nothing at all.
      Card cardInside(Finder outer) => tester.widget<Card>(
        find.descendant(of: outer, matching: find.byType(Card)).first,
      );

      for (final (what, card) in [
        ('the product line', cardAround(find.text(_polo.title))),
        ('the coupon block', cardInside(find.byType(PromoSection))),
        ('the summary', cardAround(find.byType(CartSummary))),
      ]) {
        expect(card.elevation, 0, reason: 'no shadow on $what');
        expect(card.shadowColor, Colors.transparent, reason: what);
        expect(card.surfaceTintColor, Colors.transparent, reason: what);
        // Only the shadow goes. A corner of its own here would be this file
        // deciding a shape the theme is supposed to own.
        expect(card.shape, isNull, reason: '$what keeps the theme\'s corner');
      }
    });

    testWidgets('are filled orange and trust blue, flat, and white on top', (
      tester,
    ) async {
      CartStore.instance.add(_polo);
      await _pump(tester);

      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
      }

      for (final (words, fill, minimum) in [
        // Commerce Orange by request: white on it clears the 3:1 that bold
        // text needs, not the 4.5 body text does.
        (_save, AppColors.commerceOrange, 3.0),
        (_shop, AppColors.trustBlue, 4.5),
      ]) {
        final card = tester.widget<Card>(_cardOf(words));
        expect(card.color, fill);
        expect(card.elevation, 0, reason: 'no shadow');
        expect(card.shadowColor, Colors.transparent);

        final title = tester.widget<Text>(words);
        expect(title.style!.color, Colors.white);
        expect(
          contrast(Colors.white, fill),
          greaterThanOrEqualTo(minimum),
          reason: 'the words on it read',
        );
      }
    });

    testWidgets('Continue shopping comes after the recommendations', (
      tester,
    ) async {
      // Save stays under the lines it acts on; Continue shopping follows the
      // shelf of suggestions, on the page's own measure -- at every width.
      CartStore.instance.add(_polo);

      for (final size in const [Size(420, 1600), Size(840, 1600)]) {
        await _pump(tester, size: size);
        await tester.ensureVisible(_shop);
        await tester.pumpAndSettle();

        final save = tester.getRect(_cardOf(_save));
        final shop = tester.getRect(_cardOf(_shop));
        expect(shop.top, greaterThan(save.bottom), reason: 'below, at $size');
        expect(
          find.ancestor(of: _shop, matching: find.byType(GridView)),
          findsNothing,
          reason: 'not inside the product grid',
        );
        // Centred on the page's 97%.
        expect(shop.width / size.width, closeTo(0.97, 0.01));
        expect(shop.left, closeTo(size.width - shop.right, 1));
      }
    });

    testWidgets('Continue shopping reaches the catalogue', (tester) async {
      CartStore.instance.add(_polo);
      await _pump(tester);

      await _tap(tester, _shop);
      await tester.pumpAndSettle();

      expect(find.byType(BrowseScreen), findsOneWidget);
      // The cart is left as it was: this is a way out, not a change.
      expect(CartStore.instance.lines, hasLength(1));
    });
  });

  group('saving the whole basket', () {
    testWidgets('says so while it runs, and cannot be tapped twice', (
      tester,
    ) async {
      // The account write is what takes the time, so the button is held for as
      // long as the server is: a second tap would file the half of a cart the
      // first is still emptying.
      signInForTest();
      // The account's own copy of the basket, so the cart's sync has the line
      // to reconcile against rather than an empty list.
      api.on(
        'GET',
        '/cart',
        body: {
          'items': [
            {
              'id': 'c-1',
              'source_product_id': _polo.productId,
              'quantity': _polo.quantity,
              'product_data': {'title': _polo.title, 'price': _polo.unitPrice},
            },
          ],
        },
      );

      CartStore.instance.add(_polo);
      await _pump(tester);

      // Slowed only now. The screen syncs the saved list as it opens, and a
      // slow answer to that one would still be in flight when the button is
      // pressed -- and a sync already running is one this returns straight out
      // of, which is the opposite of the wait being measured.
      api.onCall(
        'GET',
        '/wishlist',
        (_) => reply(const [], delay: const Duration(milliseconds: 300)),
      );

      await _tap(tester, _save);
      await tester.pump();

      const saving = 'Saving to your list...';
      expect(find.text(saving), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      // The card's own tap, which is the whole button, is off while it runs.
      final card = find
          .ancestor(of: find.text(saving), matching: find.byType(InkWell))
          .first;
      expect(
        tester.widget<InkWell>(card).onTap,
        isNull,
        reason: 'dead while it runs',
      );

      await tester.pumpAndSettle();

      expect(find.text(saving), findsNothing);

      // The cart debounces its own write to the account; left pending it
      // outlives the widget tree and the harness calls that a leak.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('empties the cart only once the saves have landed', (
      tester,
    ) async {
      CartStore.instance.add(_polo);
      await _pump(tester);

      await _tap(tester, _save);
      await tester.pumpAndSettle();

      expect(WishlistStore.instance.count, 1);
      expect(CartStore.instance.lines, isEmpty);
      // The card goes with the cart it belonged to, so what is said about the
      // run is said in the snack bar.
      expect(find.textContaining('1 saved'), findsOneWidget);
      expect(_save, findsNothing);
    });

    testWidgets('and says in the card what is left behind', (tester) async {
      // A line with no price cannot be filed under one, so it stays -- and the
      // card stays with it, which is where the count belongs.
      CartStore.instance
        ..add(_polo)
        ..add(_unpriced);
      await _pump(tester);

      await _tap(tester, _save);
      await tester.pumpAndSettle();

      expect(CartStore.instance.lines, hasLength(1));
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.textContaining('no price'), findsWidgets);
    });

    testWidgets('and says when the account would not take them', (
      tester,
    ) async {
      // The saves stand on the device either way -- what fails is the account
      // copy, and the shopper is told that rather than left to assume.
      signInForTest();
      api.on('GET', '/wishlist', status: 500, body: const {'message': 'nope'});

      CartStore.instance.add(_polo);
      await _pump(tester);

      await _tap(tester, _save);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsWidgets);
      expect(find.textContaining('Not saved to your account'), findsWidgets);
      // Saved on the device regardless -- and the cart is left as it was, so
      // nothing is taken out on the strength of a write that did not land.
      expect(WishlistStore.instance.count, 1);
      expect(CartStore.instance.lines, hasLength(1));
    });
  });
}
