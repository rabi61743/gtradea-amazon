import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_client.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/free_delivery/data/free_delivery_search.dart';
import 'package:gtradea_amazon/features/free_delivery/presentation/free_delivery_screen.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

/// One row in the shape `/free-delivery` answers with.
Map<String, dynamic> _row({
  required String numIid,
  required String title,
  String? category,
  String? brand,
}) => {
  'source': '1688',
  'num_iid': numIid,
  'free_delivery': true,
  'product_data': {
    'item': {
      'num_iid': numIid,
      'title': title,
      'pic_url': 'https://cdn.invalid/$numIid.jpg',
      'category_name': category,
      'brand': brand,
    },
    'pricing': {'displayPrice': 1200, 'displayCurrency': 'NPR'},
  },
};

FreeDeliveryListing _listing(
  String title, {
  String? category,
  String? brand,
  String numIid = '1',
}) => FreeDeliveryListing(
  category: category,
  brand: brand,
  product: Product(numIid: numIid, title: title, displayPrice: 1200),
);

void main() {
  late FakeApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WishlistStore.instance.resetForTest();
    api = FakeApi();
    ApiClient.overrideDio = api.dio();
  });

  tearDown(() {
    ApiClient.overrideDio = null;
    clearApiStub();
  });

  group('the words a term is compared as', () {
    test('case and punctuation stop mattering', () {
      expect(normalizeSearch("Men's T-Shirt"), 'mens t shirt');
      expect(normalizeSearch('  POLO   shirt  '), 'polo shirt');
    });

    test('accents fold to their plain letters', () {
      expect(normalizeSearch('Café Crème'), 'cafe creme');
    });

    test('and the seller Chinese survives', () {
      // Half this collection is filed under it; stripping it would make those
      // rows unsearchable rather than tidier.
      expect(normalizeSearch('休闲 POLO衫'), '休闲 polo衫');
    });
  });

  group('searching the collection', () {
    final index = FreeDeliveryIndex([
      _listing('Summer Polo Shirt for Men', category: 'Menswear', numIid: 'a'),
      _listing('Refrigerator storage box', category: 'Kitchen', numIid: 'b'),
      _listing(
        'Wireless earbuds',
        category: 'Audio',
        brand: 'Anker',
        numIid: 'c',
      ),
      _listing("Women's polo dress", category: 'Womenswear', numIid: 'd'),
    ]);

    test('an empty query is the whole collection, in the curator order', () {
      expect(index.search('').map((p) => p.numIid), ['a', 'b', 'c', 'd']);
    });

    test('a partial word matches, whatever the case', () {
      expect(index.search('POL').map((p) => p.numIid), containsAll(['a', 'd']));
    });

    test('a category is searchable, not just the title', () {
      expect(index.search('kitchen').single.numIid, 'b');
    });

    test('and a brand where the seller set one', () {
      expect(index.search('anker').single.numIid, 'c');
    });

    test('every word has to land, so a second word narrows', () {
      // "polo" alone finds two; adding "women" must not find both.
      expect(index.search('polo').length, 2);
      expect(index.search('women polo').single.numIid, 'd');
    });

    test('a word starting the title beats one buried in a category', () {
      // Title match outranks the row that only matches by category.
      final hits = index.search('polo menswear');
      expect(hits.first.numIid, 'a');
    });

    test('nothing matching gives nothing, not everything', () {
      expect(index.search('helicopter'), isEmpty);
    });
  });

  group('what it offers as you type', () {
    final index = FreeDeliveryIndex([
      _listing('Summer Polo Shirt', category: 'Menswear', numIid: 'a'),
      _listing('Polo dress', category: 'Menswear', numIid: 'b'),
      _listing('Kettle', category: 'Kitchen', numIid: 'c'),
    ]);

    test('nothing at all until something is typed', () {
      expect(index.suggest(''), isEmpty);
    });

    test('the category leads, because it stands for a group', () {
      expect(index.suggest('men').first, 'Menswear');
    });

    test('a category is offered once, however many rows carry it', () {
      expect(
        index.suggest('men').where((term) => term == 'Menswear'),
        hasLength(1),
      );
    });

    test('products fill the rest', () {
      expect(index.suggest('polo'), contains('Summer Polo Shirt'));
    });

    test('and it never offers what is not in the collection', () {
      // The guarantee this whole feature rests on.
      expect(index.suggest('kettle'), isNot(contains('Refrigerator')));
      expect(index.suggest('helicopter'), isEmpty);
    });
  });

  group('on the screen', () {
    Future<void> open(WidgetTester tester) async {
      api.on(
        'GET',
        '/free-delivery',
        body: [
          _row(numIid: 'a', title: 'Summer Polo Shirt', category: 'Menswear'),
          _row(numIid: 'b', title: 'Refrigerator box', category: 'Kitchen'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const FreeDeliveryScreen()),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the collection is listed, with a box to search it', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Summer Polo Shirt'), findsOneWidget);
      expect(find.text('Refrigerator box'), findsOneWidget);
      expect(find.widgetWithText(TextField, ''), findsOneWidget);
      expect(find.text('Search free delivery products'), findsOneWidget);
    });

    testWidgets('typing narrows it to the matches', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'polo');
      // Past the debounce.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('Summer Polo Shirt'), findsWidgets);
      expect(find.text('Refrigerator box'), findsNothing);
    });

    testWidgets('the results wait for the typing to settle', (tester) async {
      // The debounce is the point: a keystroke must not re-run the search.
      await open(tester);

      await tester.enterText(find.byType(TextField), 'polo');
      await tester.pump(const Duration(milliseconds: 60));

      expect(
        find.text('Refrigerator box'),
        findsOneWidget,
        reason: 'still showing the unfiltered list mid-keystroke',
      );

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('Refrigerator box'), findsNothing);
    });

    testWidgets('nothing matching says so rather than showing nothing', (
      tester,
    ) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'helicopter');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.textContaining('No free delivery products match'), findsOne);
    });

    testWidgets('clearing it puts the collection back', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'polo');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('Refrigerator box'), findsNothing);

      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();

      expect(find.text('Refrigerator box'), findsOneWidget);
    });

    testWidgets('it asks the free-delivery endpoint and no other', (
      tester,
    ) async {
      // The guarantee stated as a request: no catalogue search goes out, so a
      // product that is not on free delivery cannot come back.
      await open(tester);

      await tester.enterText(find.byType(TextField), 'polo');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(api.calls.map((call) => call.path).toSet(), {'/free-delivery'});
    });
  });

  group('the heart on a free delivery card', () {
    /// The collection, polo shirt first.
    Future<void> open(WidgetTester tester) async {
      api.on(
        'GET',
        '/free-delivery',
        body: [
          _row(numIid: 'a', title: 'Summer Polo Shirt', category: 'Menswear'),
          _row(numIid: 'b', title: 'Refrigerator box', category: 'Kitchen'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const FreeDeliveryScreen()),
      );
      await tester.pumpAndSettle();
    }

    /// How many cards are drawing a filled heart.
    int filled() => find.byIcon(Icons.favorite).evaluate().length;

    /// How many are drawing the outline.
    int outlined() => find.byIcon(Icons.favorite_border).evaluate().length;

    /// Taps the heart on the first card, whichever way it is drawn.
    Future<void> tapFirstHeart(WidgetTester tester) async {
      await tester.tap(
        find
            .byIcon(filled() > 0 ? Icons.favorite : Icons.favorite_border)
            .first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('starts empty on products that are not saved', (tester) async {
      await open(tester);

      expect(filled(), 0);
      expect(outlined(), 2);
    });

    testWidgets('fills the moment the product is saved', (tester) async {
      // The bug: the tap saved the product and the card went on drawing the
      // outline heart until the screen was left and come back to.
      await open(tester);

      await tapFirstHeart(tester);

      expect(WishlistStore.instance.contains('a'), isTrue);
      expect(filled(), 1, reason: 'the card it was tapped on');
    });

    testWidgets('and empties again the moment it is removed', (tester) async {
      await open(tester);
      await tapFirstHeart(tester);
      expect(filled(), 1);

      await tapFirstHeart(tester);

      expect(WishlistStore.instance.contains('a'), isFalse);
      expect(filled(), 0);
      expect(outlined(), 2);
    });

    testWidgets('only that card changes', (tester) async {
      await open(tester);

      await tapFirstHeart(tester);

      expect(filled(), 1);
      expect(outlined(), 1, reason: 'the other card is untouched');
    });

    testWidgets('a product saved before the page opens arrives filled', (
      tester,
    ) async {
      // Saved somewhere else in the app -- the product page, a search result.
      WishlistStore.instance.toggle(
        const SavedProduct(id: 'a', title: 'Summer Polo Shirt', price: 1200),
      );

      await open(tester);

      expect(filled(), 1);
      expect(outlined(), 1);
    });

    testWidgets('a list saved on a previous run arrives filled too', (
      tester,
    ) async {
      // The wishlist is on disk from an earlier session and has not been read
      // into memory yet. This screen has to ask for it: without that the cards
      // drew unsaved until some other part of the app happened to load it.
      SharedPreferences.setMockInitialValues({
        'gtradea_wishlist':
            '[{"id":"a","title":"Summer Polo Shirt","price":1200}]',
      });
      WishlistStore.instance.resetForTest();

      await open(tester);

      expect(WishlistStore.instance.contains('a'), isTrue);
      expect(filled(), 1);
    });

    testWidgets('the state survives a search', (tester) async {
      // Filtering rebuilds the grid from a different list; the heart must
      // follow the product, not the position.
      await open(tester);
      await tapFirstHeart(tester);

      await tester.enterText(find.byType(TextField), 'polo');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('Refrigerator box'), findsNothing, reason: 'filtered');
      expect(filled(), 1, reason: 'the polo shirt is still saved');
    });
  });
}
