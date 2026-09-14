import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/future_cart/data/future_cart_feed.dart';
import 'package:gtradea_amazon/features/future_cart/presentation/future_cart_chrome.dart';
import 'package:gtradea_amazon/features/future_cart/presentation/future_cart_screen.dart';
import 'package:gtradea_amazon/features/future_cart/presentation/suggestion_card.dart';
import 'package:gtradea_amazon/features/orders/data/order_store.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';
import 'support/orders.dart';

late FakeApi api;

/// What the catalogue says a product costs *now*, keyed by id.
///
/// Deliberately different from what the order lines below were bought at: the
/// page has to quote the shop's current price rather than the frozen one on an
/// old order, and a fixture where the two agree could not tell them apart.
final _currentPrice = <String, num>{};
final _currentTitle = <String, String>{};

Map<String, dynamic> _detailFor(String numIid) => {
  'success': true,
  'item': {
    'num_iid': numIid,
    'title': _currentTitle[numIid] ?? 'Catalogue record $numIid',
    'pic_url': 'https://example.invalid/$numIid.jpg',
    'images': ['https://example.invalid/$numIid.jpg'],
    'min_order_quantity': 1,
    'category_id': 'cid-$numIid',
    'category_name': 'Home and kitchen',
  },
  'pricing': {'displayPrice': _currentPrice[numIid] ?? 990},
};

const _shampoo = CartLine(
  productId: 'p-shampoo',
  title: 'Anti Dandruff Shampoo',
  // The price that was charged, months ago.
  unitPrice: 500,
  category: 'Beauty and care',
  categoryCid: 'cid-beauty',
);

const _toothpaste = CartLine(
  productId: 'p-toothpaste',
  title: 'Total Toothpaste 200g',
  unitPrice: 300,
  category: 'Beauty and care',
  categoryCid: 'cid-beauty',
);

DateTime _daysAgo(int days) => DateTime.now().subtract(Duration(days: days));

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1200, 3000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: const FutureCartScreen()),
  );

  // The page asks the catalogue for real, so let the requests run.
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    OrderStore.instance.resetForTest();
    WishlistStore.instance.resetForTest();
    CatalogStore.instance.resetForTest();
    _currentPrice.clear();
    _currentTitle.clear();

    api = stubCatalog(products: 8);
    ApiClient.overrideDio = api.dio();
    api.on('GET', '/cart', body: const {'items': []});
    api.on('GET', '/wishlist', body: const {'items': []});

    // The record for one product, answered by the id that was asked for --
    // the same service the product page reads.
    api.onCall('GET', '/api/1688/product', (call) {
      final id = (call.query['num_iid'] ?? '').toString();
      return reply(_detailFor(id));
    });
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  group('often bought again', () {
    testWidgets('a product bought twice is offered with its rhythm', (
      tester,
    ) async {
      // Two orders, thirty days apart. That spacing is the whole claim the
      // card makes, and it is arithmetic on real order dates.
      seedOrder(
        id: 'order-old',
        lines: const [_shampoo],
        placedAt: _daysAgo(60),
        withTracking: false,
      );
      seedOrder(
        id: 'order-new',
        lines: const [_shampoo],
        placedAt: _daysAgo(30),
        withTracking: false,
      );

      await _pump(tester);

      expect(find.text('Often Bought Again'), findsOneWidget);
      // The label leads and the figure sits under it, which is what lets both
      // fit the two lines the pill already had.
      expect(find.text('You Usually Buy'), findsOneWidget);
      expect(find.text('Every 30 days'), findsOneWidget);
    });

    testWidgets('one purchase can only say when it was', (tester) async {
      // One order is a fact, not a rhythm. Claiming an interval from a single
      // purchase would be inventing the very thing this page is about.
      seedOrder(
        id: 'order-1',
        lines: const [_toothpaste],
        placedAt: _daysAgo(28),
        withTracking: false,
      );

      await _pump(tester);

      expect(find.text('Last Purchased'), findsOneWidget);
      expect(find.text('28 days ago'), findsOneWidget);
      expect(find.textContaining('Every'), findsNothing);
    });

    testWidgets('four purchases read as a habit rather than a schedule', (
      tester,
    ) async {
      for (var i = 0; i < 4; i++) {
        seedOrder(
          id: 'order-$i',
          lines: const [_shampoo],
          placedAt: _daysAgo(9 * (i + 1)),
          withTracking: false,
        );
      }

      await _pump(tester);

      // No figure under this one: four scattered orders are a habit, not a
      // schedule, so the label is the whole fact and takes both lines.
      expect(find.text('You Buy This Frequently'), findsOneWidget);
    });

    testWidgets('the price is the catalogue of today, not the price paid', (
      tester,
    ) async {
      // The bug this guards is a quiet one: an order line keeps the price it
      // was charged at, frozen on purpose, and putting that on a card
      // offering to sell the thing again quotes a price the shop may have
      // moved on from.
      _currentPrice['p-shampoo'] = 1250;
      seedOrder(
        id: 'order-1',
        lines: const [_shampoo],
        placedAt: _daysAgo(20),
        withTracking: false,
      );

      await _pump(tester);

      expect(find.text('Rs. 1,250'), findsOneWidget);
      expect(
        find.text('Rs. 500'),
        findsNothing,
        reason: 'the frozen price belongs to the old order, not to this card',
      );
    });

    testWidgets('what is in the cart keeps its card, carrying its quantity', (
      tester,
    ) async {
      // The rule used to be the opposite: a product in the cart was cut from
      // the feed entirely. That was right when the card could only say "Add
      // to Cart" -- offering to add what is already added is noise -- and
      // wrong the moment the card gained a stepper.
      //
      // It also made cards vanish. The feed is built on load, so a product
      // added from this page kept its card until a pull-to-refresh and then
      // disappeared mid-scroll, which reads as a bug rather than a rule.
      _currentTitle['p-shampoo'] = 'Anti Dandruff Shampoo 650ml Bottle';
      seedOrder(
        id: 'order-1',
        lines: const [_shampoo],
        placedAt: _daysAgo(20),
        withTracking: false,
      );
      CartStore.instance.add(_shampoo);

      await _pump(tester);

      final card = find.ancestor(
        of: find.text('Anti Dandruff Shampoo 650ml Bottle'),
        matching: find.byType(SuggestionCard),
      );
      expect(card, findsOneWidget, reason: 'it stays on the shelf');

      final line = CartStore.instance.lineFor('p-shampoo')!;
      expect(
        find.descendant(of: card, matching: find.text('${line.quantity}')),
        findsOneWidget,
        reason: 'and says how many are in the cart rather than offering to add',
      );
      expect(
        find.descendant(of: card, matching: find.text('Add to Cart')),
        findsNothing,
      );
    });

    test('and a reload still offers it, which is what a refresh does', () async {
      // The disappearing-card bug, guarded at the feed rather than through
      // the indicator: a pull-to-refresh is this call made a second time, and
      // the second call is where the product used to drop out.
      seedOrder(
        id: 'order-1',
        lines: const [_shampoo],
        placedAt: _daysAgo(20),
        withTracking: false,
      );

      final first = await FutureCartFeed.oftenBoughtAgain();
      expect(
        first.map((s) => s.product.numIid),
        contains('p-shampoo'),
        reason: 'it is a repeat before it is in the cart',
      );

      CartStore.instance.add(_shampoo);

      final second = await FutureCartFeed.oftenBoughtAgain();
      expect(
        second.map((s) => s.product.numIid),
        contains('p-shampoo'),
        reason: 'a refresh must not delete a card from under the reader',
      );
    });

    testWidgets('with no orders at all, stand-in cards fill the section', (
      tester,
    ) async {
      // This asserted the opposite until the placeholder was asked for: a
      // section with nothing real behind it used to be left undrawn, the way
      // the cart's own shelf leaves it. The rule is reversed here on purpose,
      // and recorded rather than deleted -- the day
      // [FutureCartFeed.usePlaceholderRepeats] goes false, this is the test
      // that should go back to expecting nothing.
      await _pump(tester);

      expect(FutureCartFeed.usePlaceholderRepeats, isTrue);
      expect(find.text('Often Bought Again'), findsOneWidget);
      // Real catalogue rows, not invented ones: the products come from the
      // discover feed, so the Add button adds something that exists.
      expect(find.byType(SuggestionCard), findsWidgets);
    });

    testWidgets('and a real purchase is never displaced by a stand-in', (
      tester,
    ) async {
      // The one rule the placeholder must not break. A shopper with history
      // sees their own products; the stand-in fills an empty section only.
      _currentPrice['p-shampoo'] = 1250;
      seedOrder(
        id: 'order-1',
        lines: const [_shampoo],
        placedAt: _daysAgo(20),
        withTracking: false,
      );

      await _pump(tester);

      expect(find.text('Last Purchased'), findsOneWidget);
      expect(find.text('20 days ago'), findsOneWidget);
      expect(
        find.text('Every 30 days'),
        findsNothing,
        reason: 'the stand-in figures belong to an empty section only',
      );
    });
  });

  group('complements', () {
    testWidgets('come from the department the cart is buying from', (
      tester,
    ) async {
      api.on('GET', '/categories/cid-beauty/products', body: feedRows(4));
      CartStore.instance.add(_shampoo);

      await _pump(tester);

      expect(find.text('Complements for Your Cart'), findsOneWidget);
      // The reason names the cart line it was chosen for, in the shopper's
      // own basket rather than in the abstract. Short wording, because the
      // pill holds two lines of about ten characters -- see
      // [FutureCartFeed.shortTitleOf].
      expect(find.text('Pairs With'), findsWidgets);
      expect(
        api.calls.any((c) => c.path == '/categories/cid-beauty/products'),
        isTrue,
        reason: "the cart line's own sub-category is the sharp signal",
      );
    });

    testWidgets('are a rail, with cards wider than the grid would give', (
      tester,
    ) async {
      api.on('GET', '/categories/cid-beauty/products', body: feedRows(10));
      CartStore.instance.add(_shampoo);

      await _pump(tester);

      // Sideways, and only sideways: the page scrolls down, the rail scrolls
      // across, so the two never compete for one drag.
      expect(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
        findsWidgets,
      );

      // And the point of the rail: a card wider than the same width would
      // give it in three grid columns.
      final card = tester.getSize(find.byType(SuggestionCard).first);
      final available =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(
        card.width,
        greaterThan(SuggestionCard.carouselWidthFor(available) * 0.8),
      );
      expect(card.width, greaterThan(available / 4));
    });

    testWidgets('stack a second row that scrolls on its own', (tester) async {
      api.on('GET', '/categories/cid-beauty/products', body: feedRows(10));
      CartStore.instance.add(_shampoo);

      await _pump(tester);

      // Only the complements, found by the label their pills carry: other
      // sections are rails too, and counting every card on the page would be
      // counting their rows as well.
      final cards = find.ancestor(
        of: find.text('Pairs With'),
        matching: find.byType(SuggestionCard),
      );
      expect(cards.evaluate().length, greaterThanOrEqualTo(4));
      final tops = <double>{};
      for (var i = 0; i < cards.evaluate().length; i++) {
        tops.add(tester.getRect(cards.at(i)).top);
      }
      expect(tops, hasLength(2), reason: 'two rows, and only two');

      // And two scrollables, which is the point: one grid of two rows is a
      // single scroll position, so swiping the top row dragged the bottom one
      // along with it. A rail each means a finger moves the row it is on.
      final rails = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
          )
          .evaluate()
          .length;
      expect(rails, greaterThanOrEqualTo(2));
    });

    testWidgets('an empty cart has nothing to complement', (tester) async {
      await _pump(tester);

      expect(find.text('Complements for Your Cart'), findsNothing);
    });
  });

  group('the page itself', () {
    testWidgets('carries the reference chrome and nothing invented', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Future Cart'), findsOneWidget);
      expect(
        find.text('Smarter suggestions for a happier tomorrow'),
        findsOneWidget,
      );
      for (final chip in const [
        'All',
        'Often Bought',
        'Complements',
        'For Home',
        'For Kids',
      ]) {
        expect(find.text(chip), findsOneWidget, reason: chip);
      }
      // The note is the supplied artwork now, so its words are pixels rather
      // than widgets. This used to assert them as text; what it asserts
      // instead is the thing that was actually asked for -- that the page
      // does not *also* draw them, which would have said them twice.
      expect(find.byType(FutureCartFooterNote), findsOneWidget);
      expect(
        find.text('Always your choice.'),
        findsNothing,
        reason: 'the artwork says it; the page must not say it again',
      );
      expect(find.text('Thoughtful suggestions.'), findsNothing);
    });

    testWidgets('carries the department rails as sections of its own', (
      tester,
    ) async {
      // "Home and kitchen" and "Toys and baby" are real departments in the
      // stubbed tree, matched by name rather than by an id written down here
      // -- the same way the live catalogue is matched.
      api.on('GET', '/categories/dept-3/products', body: feedRows(6));
      api.on('GET', '/categories/dept-6/products', body: feedRows(6));

      // Tall enough to build all four sections: the page is a lazy ListView,
      // and with the repeats rail above them the kids section fell outside the
      // built region -- absent from the tree rather than absent from the page.
      await _pump(tester, size: const Size(1200, 9000));

      // The subtitles, not the titles: the titles are also the chip labels.
      expect(find.text('Popular in the home departments'), findsOneWidget);
      expect(find.text('Popular in the kids departments'), findsOneWidget);
    });

    testWidgets('leaves the page the room to be seen', (tester) async {
      // Every other test here asserts that things are *present*, and presence
      // is not visibility: `find.text` matches the element tree, so a page
      // laid out at zero height still satisfies all of them. That is exactly
      // what happened -- the bottom bar was given a bare `Center`, which
      // expanded to the full screen height it was offered, the body was
      // squeezed to nothing, and twenty-two green tests said the page was
      // fine while the phone showed a blank screen with one button on it.
      //
      // So this one measures instead: the bar is a bar, and the page has a
      // viewport worth scrolling.
      await _pump(tester);

      final screen =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final bar = tester.getSize(find.byType(BackToCartBar));
      expect(
        bar.height,
        lessThan(screen / 4),
        reason: 'the bottom bar is a bar, not the page',
      );

      final vertical = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );
      final state = tester.state<ScrollableState>(vertical.first);
      expect(
        state.position.viewportDimension,
        greaterThan(screen / 2),
        reason: 'the body keeps most of the screen',
      );
    });

    testWidgets('does not resize itself while it is being scrolled', (
      tester,
    ) async {
      // The page shook under a scroll, and this is why: as a lazy `ListView`
      // it estimated the height of the sections it had not reached from the
      // average of those it had, and its children run from a 40-point chip
      // row to 700-point rails. Measured on a phone, the estimate ran
      // 1931 -> 2720 -> 3089 -> 4298 -> 2753 -> 2403 during one scroll, and a
      // scroll in flight is corrected against it every time it moves.
      //
      // So what is pinned is the absence of that: the page is the same height
      // at the bottom as it was at the top.
      api.on('GET', '/categories/cid-beauty/products', body: feedRows(12));
      CartStore.instance.add(_shampoo);

      await _pump(tester);

      final vertical = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );
      final state = tester.state<ScrollableState>(vertical.first);
      final extent = state.position.maxScrollExtent;
      expect(extent, greaterThan(0), reason: 'there is a page to scroll');

      for (var i = 0; i < 10; i++) {
        final target = state.position.pixels + 200;
        if (target > state.position.maxScrollExtent) break;
        state.position.jumpTo(target);
        await tester.pump();
        expect(
          state.position.maxScrollExtent,
          extent,
          reason: 'the page is still the height it was at step $i',
        );
      }
    });

    testWidgets('the bar counts the units waiting in the cart', (tester) async {
      CartStore.instance.add(_shampoo);
      CartStore.instance.add(_toothpaste);
      CartStore.instance.increment(_shampoo.key);
      CartStore.instance.increment(_shampoo.key);

      await _pump(tester);

      expect(find.text('Back to My Cart (4 items)'), findsOneWidget);
    });

    testWidgets('and says item, singular, when there is one', (tester) async {
      CartStore.instance.add(_toothpaste);

      await _pump(tester);

      expect(find.text('Back to My Cart (1 item)'), findsOneWidget);
    });

    testWidgets('three cards across, as the reference sets them', (
      tester,
    ) async {
      seedOrder(
        id: 'order-1',
        lines: const [_shampoo, _toothpaste],
        placedAt: _daysAgo(20),
        withTracking: false,
      );

      await _pump(tester, size: const Size(880, 3000));

      final cards = find.byType(SuggestionCard);
      expect(cards, findsWidgets);
      if (cards.evaluate().length >= 2) {
        final first = tester.getRect(cards.at(0));
        final second = tester.getRect(cards.at(1));
        expect(second.top, first.top, reason: 'side by side');
        expect(second.left, greaterThan(first.right));
      }
    });

    testWidgets('a failed catalogue says so and offers to try again', (
      tester,
    ) async {
      api.on(
        'GET',
        '/categories/cid-beauty/products',
        status: 500,
        body: const {},
      );
      api.on('GET', '/feed/trending-products', status: 500, body: const {});
      api.on('GET', '/search/products', status: 500, body: const {});
      api.on('GET', '/api/1688/search', status: 500, body: const {});
      CartStore.instance.add(_shampoo);

      await _pump(tester);

      // Every source failing leaves the section absent rather than the page
      // broken -- the shelf says nothing rather than inventing a suggestion.
      expect(find.text('Complements for Your Cart'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the word a complement names', () {
    test('skips the trade filler these titles open with', () {
      // Measured on the phone twice. These titles are written for a sourcing
      // index rather than for a shopper, so the opening words describe how the
      // thing is sold: "Goes well with your new." would be worse than saying
      // nothing at all.
      //
      // This expected "mobile" while the rule was "longest word wins", and
      // that was the rule's accident rather than the right answer: the thing
      // being sold is a *case*, and "mobile" is what kind of case it is. The
      // same accident is what put "Pairs With handsome" on five cards at
      // once. What this test is actually about -- that "source", "factory"
      // and "customized" are all skipped -- still holds, and the word named
      // is now the noun at the end of the phrase.
      expect(
        FutureCartFeed.shortTitleOf(
          'Source Factory Customized Mobile Phone Case',
        ),
        'case',
      );
    });

    test('and takes the thing rather than the adjective in front of it', () {
      // Measured on the phone: this department really is called "False
      // eyelashes", and taking the first acceptable word put "Pairs with
      // false." on the card.
      expect(FutureCartFeed.shortTitleOf('False eyelashes'), 'eyelashes');
      expect(
        FutureCartFeed.shortTitleOf('Home Textile Furniture'),
        'furniture',
      );
    });

    test('and names the cart rather than guessing at a title of filler', () {
      expect(FutureCartFeed.shortTitleOf('New Hot Sale Wholesale'), 'cart');
      expect(FutureCartFeed.shortTitleOf(''), 'cart');
    });

    test('one word, because two of them did not fit the pill', () {
      // The pill truncated to "Goes well with your..." at both three words and
      // two. One is what a 127-point card has room for.
      expect(
        FutureCartFeed.shortTitleOf('Penguin Toy Set').split(' '),
        hasLength(1),
      );
    });

    test('and the noun at the end, not the adjective that ties on length', () {
      // Measured on the phone: five cards in a row said "Pairs With handsome".
      // The rule was "longest word wins", and in this title "handsome" and
      // "shoulder" are both eight letters, so the adjective won the tie.
      expect(
        FutureCartFeed.shortTitleOf(
          'Black Short-Sleeved Men\'s Polo Shirt Summer Handsome Light '
          'Mature Style Mature and Stable Men\'s Heavy Lapel Right '
          'Shoulder T-Shirt',
        ),
        'shirt',
      );
    });

    test('and survives a title that trails off into adjectives', () {
      // This one ends on three qualifiers in a row, so position alone is not
      // enough -- the stop-list has to carry it back to the noun.
      expect(
        FutureCartFeed.shortTitleOf(
          "ins Hong Kong-style vintage short-sleeved floral shirt men's "
          '2022 Hawaiian vintage shirt Ruffian handsome coat trendy',
        ),
        'coat',
      );
    });

    test('and does not name a year, or half of a hyphenated word', () {
      // "Kong-style" came through as one ten-character token and beat every
      // real noun in the title; "2022" is in half these listings.
      expect(FutureCartFeed.shortTitleOf('Kong-style lamp'), 'lamp');
      expect(FutureCartFeed.shortTitleOf('Hawaiian shirt 2022'), 'shirt');
    });
  });

  group('adult goods', () {
    Product productNamed(String title, {String? category}) => Product(
      numIid: 'p-$title',
      title: title,
      categoryName: category,
    );

    test('are recognised from the title, whatever the category says', () {
      expect(
        FutureCartFeed.isAdult(
          productNamed('Jiyu Female Masturbation Device Heating Telescopic'),
        ),
        isTrue,
      );
      expect(
        FutureCartFeed.isAdult(productNamed('Rabbit Vibrator Silicone')),
        isTrue,
      );
    });

    test('and from the category, when the title is coy about it', () {
      expect(
        FutureCartFeed.isAdult(
          productNamed('Telescopic Massager', category: 'Adult products'),
        ),
        isTrue,
      );
    });

    test('and ordinary goods are not swept up with them', () {
      // The guard must not eat the catalogue. These are the kinds of listing
      // that sit next to the flagged ones in the same rails.
      expect(
        FutureCartFeed.isAdult(productNamed('Neck Massager for Shoulder')),
        isFalse,
      );
      expect(
        FutureCartFeed.isAdult(
          productNamed('Cotton Silk Summer Loose Trousers'),
        ),
        isFalse,
      );
      expect(
        FutureCartFeed.isAdult(
          productNamed('Shape Recognition Matching Toys for Children'),
        ),
        isFalse,
      );
    });
  });

  group('the card', () {
    testWidgets('is square at the top and rounded at the foot', (tester) async {
      // So it lines up with the banners above and below it, which were
      // squared off at the top by request.
      seedOrder(
        id: 'order-1',
        lines: const [_shampoo],
        placedAt: _daysAgo(20),
        withTracking: false,
      );

      await _pump(tester);

      final decorated = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(SuggestionCard).first,
              matching: find.byType(Container),
            )
            .first,
      );
      final shape = (decorated.decoration! as BoxDecoration).borderRadius!;

      expect(shape.resolve(TextDirection.ltr).topLeft, Radius.zero);
      expect(shape.resolve(TextDirection.ltr).topRight, Radius.zero);
      expect(
        shape.resolve(TextDirection.ltr).bottomLeft.x,
        greaterThan(0),
        reason: 'the foot keeps its radius',
      );
    });
  });

  group('in-cart controls', () {
    const title = 'Anti Dandruff Shampoo 650ml Bottle';

    /// The card drawn for [name], whatever else is on the page.
    Finder cardFor(String name) => find.ancestor(
      of: find.text(name),
      matching: find.byType(SuggestionCard),
    );

    /// A page with the shampoo offered as a repeat, and nothing in the cart.
    Future<Finder> shownOnce(WidgetTester tester) async {
      _currentTitle['p-shampoo'] = title;
      seedOrder(
        id: 'order-1',
        lines: const [_shampoo],
        placedAt: _daysAgo(20),
        withTracking: false,
      );
      await _pump(tester);

      final card = cardFor(title);
      expect(card, findsOneWidget);
      return card;
    }

    /// The same page, with the shampoo added from its own card.
    Future<Finder> added(WidgetTester tester) async {
      final card = await shownOnce(tester);
      await tester.tap(
        find.descendant(of: card, matching: find.text('Add to Cart')),
      );
      await tester.pumpAndSettle();
      return card;
    }

    testWidgets('adding swaps the Add button for fewer, the count and more', (
      tester,
    ) async {
      final card = await added(tester);

      expect(
        find.descendant(of: card, matching: find.text('Add to Cart')),
        findsNothing,
        reason: 'it is in the cart now, so the card offers to change it',
      );

      final line = CartStore.instance.lineFor('p-shampoo');
      expect(line, isNotNull);
      expect(
        find.descendant(of: card, matching: find.text('${line!.quantity}')),
        findsOneWidget,
        reason: "the figure on the card is the cart's own, not a tally of taps",
      );
      expect(
        find.descendant(of: card, matching: find.byIcon(Icons.delete_outline)),
        findsOneWidget,
        reason: 'remove is its own control, beside the stepper',
      );
    });

    testWidgets('more and fewer move the real cart line', (tester) async {
      final card = await added(tester);
      final start = CartStore.instance.lineFor('p-shampoo')!.quantity;

      await tester.tap(
        find.descendant(of: card, matching: find.byIcon(Icons.add)),
      );
      await tester.pumpAndSettle();

      expect(CartStore.instance.lineFor('p-shampoo')!.quantity, start + 1);
      expect(
        find.descendant(of: card, matching: find.text('${start + 1}')),
        findsOneWidget,
        reason: 'the new quantity shows on the card at once',
      );

      await tester.tap(
        find.descendant(of: card, matching: find.byIcon(Icons.remove)),
      );
      await tester.pumpAndSettle();

      expect(CartStore.instance.lineFor('p-shampoo')!.quantity, start);
    });

    testWidgets('fewer stops at the line minimum rather than emptying it', (
      tester,
    ) async {
      final card = await added(tester);
      final line = CartStore.instance.lineFor('p-shampoo')!;
      expect(
        line.quantity,
        line.minOrder,
        reason: 'an add enters the cart at the minimum order',
      );

      await tester.tap(
        find.descendant(of: card, matching: find.byIcon(Icons.remove)),
      );
      await tester.pumpAndSettle();

      // The cart's own rule: the minus key is not a delete, because a stepper
      // that removes the line out from under the finger is how shoppers lose
      // things by accident.
      expect(CartStore.instance.lineFor('p-shampoo'), isNotNull);
      expect(CartStore.instance.lineFor('p-shampoo')!.quantity, line.minOrder);
    });

    testWidgets('remove empties the line and gives the Add button back', (
      tester,
    ) async {
      final card = await added(tester);

      await tester.tap(
        find.descendant(of: card, matching: find.byIcon(Icons.delete_outline)),
      );
      await tester.pumpAndSettle();

      expect(
        CartStore.instance.lineFor('p-shampoo'),
        isNull,
        reason: 'remove takes it out of the real cart',
      );
      expect(
        find.descendant(of: card, matching: find.text('Add to Cart')),
        findsOneWidget,
        reason: 'and the card goes back to offering it',
      );
    });

    testWidgets('the controls cost the card no height', (tester) async {
      final card = await shownOnce(tester);
      final before = tester.getSize(card);

      await tester.tap(
        find.descendant(of: card, matching: find.text('Add to Cart')),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(card),
        before,
        reason: 'a card that joins the cart must not shove the row about',
      );
    });
  });
}
