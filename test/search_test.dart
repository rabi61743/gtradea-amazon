import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/features/search/data/search_suggestions.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/search/data/recent_search_store.dart';
import 'package:gtradea_amazon/features/search/data/search_filters.dart';
import 'package:gtradea_amazon/features/search/data/search_models.dart';
import 'package:gtradea_amazon/features/search/presentation/search_entry_screen.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
import 'package:gtradea_amazon/features/search/widgets/product_result_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

late FakeApi api;

/// A window tall enough that the results list is actually built.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// The query parameters of the most recent search request, whichever of the two
/// search endpoints served it.
///
/// A plain keyword search goes to the live 1688 catalogue and a filtered one to
/// `/search/products`. What these tests are about is what was *asked for*, not
/// which host answered.
Map<String, dynamic> lastSearch() => api.calls.lastWhere(isSearchCall).query;

/// How many searches have been asked for so far.
///
/// Counted rather than inspected, because the point of the debounce is the
/// requests that are *not* made: a burst of keystrokes has to cost one search,
/// and only a count can say so.
int searchCount() => api.calls.where(isSearchCall).length;

/// The price bounds the last search asked for, whichever endpoint answered.
///
/// The two spell them differently: the keyword endpoint reads `price_min` and
/// `price_max`, the gateway's cached index `min_price` and `max_price`. Reading
/// both is not laziness -- it is the point of these tests. What they are about
/// is that the bound reached the server rather than being applied to the page
/// in hand, and which endpoint served it is a routing decision tested on its
/// own further down.
Object? sentMinPrice() =>
    lastSearch()['price_min'] ?? lastSearch()['min_price'];

Object? sentMaxPrice() =>
    lastSearch()['price_max'] ?? lastSearch()['max_price'];

bool sentAnyMaxPrice() =>
    lastSearch().containsKey('price_max') ||
    lastSearch().containsKey('max_price');

void main() {
  setUp(() {
    SearchSuggestionRepository.instance.resetForTest();
    SharedPreferences.setMockInitialValues({});
    RecentSearchStore.instance.resetForTest();
    api = stubCatalog();
  });

  group('SearchResult.discountPercent', () {
    test('is null without a list price', () {
      const r = SearchResult(
        title: 'x',
        price: 100,
        rating: 4,
        reviewCount: 1,
        icon: Icons.abc,
        tint: Colors.blue,
      );
      expect(r.discountPercent, isNull);
    });

    test('is null when the list price is not actually higher', () {
      // A crossed-out number that is not a saving is a false discount claim.
      const same = SearchResult(
        title: 'x',
        price: 100,
        listPrice: 100,
        rating: 4,
        reviewCount: 1,
        icon: Icons.abc,
        tint: Colors.blue,
      );
      const lower = SearchResult(
        title: 'x',
        price: 100,
        listPrice: 80,
        rating: 4,
        reviewCount: 1,
        icon: Icons.abc,
        tint: Colors.blue,
      );
      expect(same.discountPercent, isNull);
      expect(lower.discountPercent, isNull);
    });

    test('rounds to a whole percent', () {
      const r = SearchResult(
        title: 'x',
        price: 3559,
        listPrice: 9990,
        rating: 4,
        reviewCount: 1,
        icon: Icons.abc,
        tint: Colors.blue,
      );
      expect(r.discountPercent, 64);
    });
  });

  group('the entry screen', () {
    testWidgets('leads with recent searches, once there are any', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      // Nothing invented: a shopper who has never searched has no history, and
      // showing a made-up one would be a lie about what they had done.
      expect(find.text('Recent searches'), findsNothing);

      RecentSearchStore.instance.record('water geyser');
      await tester.pumpAndSettle();

      expect(find.text('Recent searches'), findsOneWidget);
      expect(find.text('water geyser'), findsOneWidget);
    });

    testWidgets('offers the real departments rather than invented queries', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Browse departments'), findsOneWidget);
      expect(find.text('Women'), findsOneWidget);
      // The subtitle names what is inside, which is what makes the row worth
      // its height.
      expect(find.textContaining('Women item 0'), findsWidgets);
    });

    testWidgets('a department opens results for that category, not its name', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Men'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchResultsScreen), findsOneWidget);
      expect(lastSearch()['category'], 'dept-1');
      expect(lastSearch().containsKey('q'), isFalse);
    });

    testWidgets('searching records the query for next time', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'kettle');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(RecentSearchStore.instance.queries, ['kettle']);
    });
  });

  group('the results header', () {
    testWidgets('carries exactly one way back', (tester) async {
      // SearchField paints its own band and its own back arrow, so hosting it
      // in an AppBar title got the AppBar's automatic leading arrow too and the
      // page showed two. Pushed rather than pumped as home, because with
      // nothing to pop an AppBar draws no leading and the bug hides.
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Men'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchResultsScreen), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('and it goes back', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Men'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(SearchResultsScreen), findsNothing);
      expect(find.byType(SearchEntryScreen), findsOneWidget);
    });

    testWidgets('the camera opens visual search, not nothing', (tester) async {
      // It was drawn here and inert: the handler was only ever wired up on the
      // entry screen.
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'x')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search by image'));
      await tester.pumpAndSettle();

      expect(find.text('Search by photo'), findsOneWidget);
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
    });
  });

  group('results', () {
    testWidgets('come from the server, with the query attached', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      expect(lastSearch()['q'], 'geyser');
      expect(find.text('Catalogue product 0'), findsOneWidget);
      expect(find.text('Rs. 300'), findsOneWidget);
    });

    testWidgets('a price filter is sent to the server, not applied locally', (
      tester,
    ) async {
      // The catalogue is millions of rows and the response is one page of
      // them. Filtering that page would narrow twenty-four products and claim
      // there was nothing else.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilterChip, 'Rs. 500 - 2,000'));
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      expect(sentMinPrice(), 500);
      expect(sentMaxPrice(), 2000);
      expect(find.text('Filters (1)'), findsOneWidget);
    });

    testWidgets('clearing the filter asks again without it', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Under Rs. 500'));
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
      expect(sentMaxPrice(), 500);
      // What is narrowing the results is now stated above them, as a chip that
      // removes exactly itself.
      expect(find.widgetWithText(InputChip, 'Under Rs. 500'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputChip, 'Under Rs. 500'),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();

      expect(sentAnyMaxPrice(), isFalse);
      expect(find.text('Filters'), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('a typed price range is sent as min_price and max_price', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Min'), '750');
      await tester.enterText(find.widgetWithText(TextField, 'Max'), '4200');
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      expect(sentMinPrice(), 750);
      expect(sentMaxPrice(), 4200);
      expect(find.widgetWithText(InputChip, 'Rs. 750 - 4200'), findsOneWidget);
    });

    testWidgets('a typed range replaces a band rather than fighting it', (
      tester,
    ) async {
      // One price rule is ever in force, so the request can never carry a
      // window neither control is showing.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Under Rs. 500'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Min'), '9000');
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      expect(sentMinPrice(), 9000);
      expect(
        sentAnyMaxPrice(),
        isFalse,
        reason: 'the band\'s ceiling went with the band',
      );
    });

    testWidgets('an inverted range is swapped rather than finding nothing', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Min'), '4000');
      await tester.enterText(find.widgetWithText(TextField, 'Max'), '900');
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      expect(sentMinPrice(), 900);
      expect(sentMaxPrice(), 4000);
    });

    testWidgets('the sheet search box never reaches the server', (
      tester,
    ) async {
      // The whole point of it. It searches the filter controls, not the
      // catalogue -- so typing in it, and applying, must leave the request
      // exactly as it was.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();
      final before = searchCount();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Find a filter'),
        'price',
      );
      await tester.pumpAndSettle();

      expect(searchCount(), before, reason: 'typing asked for nothing');

      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      // The query is untouched: still what the header bar holds.
      expect(lastSearch()['q'], 'geyser');
    });

    testWidgets('it narrows the department chips as it is typed', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'Electronics'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Find a filter'),
        'men',
      );
      await tester.pumpAndSettle();

      // "Women" contains "men", which is the case a prefix match would get
      // wrong -- and getting it wrong means hiding a department whose name the
      // shopper can see contains what they typed.
      expect(find.widgetWithText(FilterChip, 'Women'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Electronics'), findsNothing);
    });

    testWidgets('a sub-category is reachable without picking its department', (
      tester,
    ) async {
      // What the box is really for. The Category section shows nothing until a
      // department is chosen, so this is otherwise a two-step hunt through
      // forty-eight chips.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Find a filter'),
        'Women item 1',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilterChip, 'Women item 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      // The child's own cid, with its department carried along so the chips
      // read as a coherent pair.
      expect(lastSearch()['category'], 'dept-0-child-1');
    });

    testWidgets('a section holding a selection is never hidden by the box', (
      tester,
    ) async {
      // The rule that stops the search box hiding a filter that is narrowing
      // the results, leaving a short list with nothing on screen to explain it.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Rs. 500 - 2,000'));
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextField, 'Find a filter'),
        'electronics',
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(FilterChip, 'Rs. 500 - 2,000'),
        findsOneWidget,
        reason: 'it is still filtering the results',
      );
    });

    testWidgets('a heading match brings back a section, not every option', (
      tester,
    ) async {
      // The bug this pins. "Department" contains "men", so letting a heading
      // match override the option filter kept all forty-eight departments for
      // anyone typing "men". A heading asks for a section; it is not a wildcard
      // over its contents -- so it only applies when nothing else matched.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Find a filter'),
        'price',
      );
      await tester.pumpAndSettle();

      // No band is named "price", so the heading brings the whole section back.
      expect(find.widgetWithText(FilterChip, 'Under Rs. 500'), findsOneWidget);
      expect(
        find.widgetWithText(FilterChip, 'Rs. 500 - 2,000'),
        findsOneWidget,
      );
    });

    testWidgets('the brand chips are shown and cannot be pressed', (
      tester,
    ) async {
      // Names from the server, control switched off: no listing in this
      // catalogue names a brand and the endpoint ignores `brand=`.
      api.on(
        'GET',
        '/brands',
        body: const [
          {'id': '1', 'name': 'Adidas', 'is_active': true},
        ],
      );
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();

      final chip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Adidas'),
      );
      expect(chip.onSelected, isNull);
      expect(find.textContaining('don\'t name a brand'), findsOneWidget);
    });

    testWidgets('and says so when nothing matches', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Find a filter'),
        'zzzznope',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No filter matches'), findsOneWidget);
    });

    testWidgets('the header bar still searches products, independently', (
      tester,
    ) async {
      // The two boxes are unrelated, asserted from the other side: the filter
      // box holding text changes nothing about what the header sends.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Find a filter'),
        'price',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'kettle');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(lastSearch()['q'], 'kettle');
    });

    testWidgets('search, price and department combine into one request', (
      tester,
    ) async {
      // The "filters apply together" requirement, asserted where it is decided:
      // one request carrying all three, rather than three that overwrite each
      // other.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const SearchResultsScreen(
            query: 'geyser',
            categoryCid: 'dept-1',
            categoryName: 'Electronics',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The pill already reads "Filters (1)" here -- the department it opened
      // with counts as one -- and the extra Category pill that a department
      // brings pushes it off the end of the control bar, which scrolls.
      final pill = find.textContaining('Filters');
      await tester.ensureVisible(pill);
      await tester.pumpAndSettle();
      await tester.tap(pill);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Min'), '600');
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      // The query comes from the header bar, where product search lives -- the
      // sheet no longer carries one. The price and the department come from the
      // sheet. All three reach the server together.
      final sent = lastSearch();
      expect(sent['q'], 'geyser');
      expect(sent['min_price'], 600);
      expect(sent['category'], 'dept-1');
    });

    testWidgets('typing in the header re-searches without pressing enter', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();
      final before = searchCount();

      await tester.enterText(find.byType(TextField).first, 'kettle');
      // Nothing yet: the debounce is what stops a request per keystroke.
      await tester.pump(const Duration(milliseconds: 100));
      expect(searchCount(), before, reason: 'still typing');

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(lastSearch()['q'], 'kettle');
      expect(
        searchCount(),
        before + 1,
        reason: 'one request for the burst, not one per letter',
      );
    });

    testWidgets('and a burst of typing asks only for the last word', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();
      final before = searchCount();

      for (final word in ['k', 'ke', 'ket', 'kett', 'kettle']) {
        await tester.enterText(find.byType(TextField).first, word);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(searchCount(), before + 1);
      expect(lastSearch()['q'], 'kettle');
    });

    testWidgets('the rating tiers are shown and cannot be pressed', (
      tester,
    ) async {
      // Every row in this catalogue has a null rating and the endpoint ignores
      // min_rating, so a working control would empty the grid whichever tier
      // was picked. This is the guard against someone wiring it up anyway.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();

      for (final tier in kRatingTiers) {
        final chip = tester.widget<FilterChip>(
          find.widgetWithText(FilterChip, '$tier+'),
        );
        expect(chip.onSelected, isNull, reason: '$tier+ must stay disabled');
      }
      expect(find.textContaining('don\'t carry ratings'), findsOneWidget);
    });

    testWidgets('dismissing the sheet keeps the previous selection', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();
      final before = api.calls.length;

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Under Rs. 500'));
      await tester.pump();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(api.calls.length, before, reason: 'nothing was re-fetched');
      expect(find.text('Filters'), findsOneWidget);
    });

    testWidgets('sorting re-asks the server rather than reordering a page', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Relevance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Price: low to high'));
      await tester.pumpAndSettle();

      expect(lastSearch()['sort'], 'price_asc');
      expect(find.text('Price: low to high'), findsOneWidget);
    });

    testWidgets('nothing matching falls back to related products, labelled', (
      tester,
    ) async {
      stubSearch(api, const []);
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'zzzz')));
      await tester.pumpAndSettle();

      // Substitutes have to say they are substitutes. A grid presented as hits
      // is how someone buys the wrong thing.
      expect(find.text('No exact matches for "zzzz"'), findsOneWidget);
      expect(find.text('Showing related products instead.'), findsOneWidget);
      expect(find.byType(ProductResultCard), findsWidgets);
    });

    testWidgets('a multi-word query drops a word before giving up', (
      tester,
    ) async {
      // "red cotton geyser" finding nothing does not mean "red cotton" will.
      stubSearchWith(api, (call) {
        final q = call.query['q'] as String?;
        return q == 'red cotton' ? feedRows(4) : const [];
      });
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'red cotton geyser')),
      );
      await tester.pumpAndSettle();

      expect(lastSearch()['q'], 'red cotton');
      expect(
        find.text('No exact matches for "red cotton geyser"'),
        findsOneWidget,
      );
    });

    testWidgets('no results names the query when even widening finds nothing', (
      tester,
    ) async {
      stubSearch(api, const []);
      api.on('GET', '/feed/discover', body: const []);
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'zzzz')));
      await tester.pumpAndSettle();

      // Naming the query is how someone spots the typo that caused this.
      expect(find.text('No results for "zzzz"'), findsOneWidget);
    });

    testWidgets('filters are not widened around -- the fix is to drop one', (
      tester,
    ) async {
      // Widening here would bury the actual remedy under a grid of things the
      // shopper did not ask for.
      stubSearchWith(
        api,
        (call) =>
            call.query.containsKey('max_price') ||
                call.query.containsKey('price_max')
            ? const []
            : feedRows(6),
      );
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: 'geyser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Under Rs. 500'));
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      // Names the filters as the cause. "No results for geyser" would send a
      // shopper off to edit a word that was never the problem.
      expect(
        find.text('No results for "geyser" with these filters'),
        findsOneWidget,
      );
      expect(find.text('Clear filters'), findsOneWidget);
      expect(find.textContaining('related products'), findsNothing);
    });

    testWidgets('a failed search says so and offers a retry', (tester) async {
      stubSearch(api, const [], status: 500);
      api.on(
        'GET',
        '/api/1688/search',
        status: 500,
        body: {'error': 'search is down'},
      );
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'x')));
      await tester.pumpAndSettle();

      expect(find.text('search is down'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('scrolling to the end asks for the next page', (tester) async {
      // A full page back means there is probably more. Stopping at 24 rows
      // would quietly cap the catalogue at 24 rows.
      stubSearch(api, feedRows(24));
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'x')));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await tester.pumpAndSettle();

      // A second request went out for more. A plain keyword search is served by
      // the live catalogue, which pages by number rather than by offset -- so
      // what this asserts is that reaching the bottom asked again, not which
      // parameter carried the ask.
      expect(api.calls.where(isSearchCall).length, greaterThan(1));
      expect(lastSearch()['page'], isNotNull);
    });

    testWidgets('a short page means there is no next one', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'x')));
      await tester.pumpAndSettle();
      final before = api.calls.length;

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await tester.pumpAndSettle();

      expect(api.calls.length, before, reason: 'six rows is the whole answer');
    });
  });

  group('which endpoint serves a search', () {
    testWidgets('a plain keyword search goes to the live catalogue', (
      tester,
    ) async {
      // The bug this fixes: /search/products matches "shoes" against shoe
      // boxes, shoe cabinets and shoe-material foam, and then ignores its own
      // relevance_score when ordering them -- rows scoring 0.61 came back above
      // rows scoring 0.83. The keyword endpoint returns footwear.
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'shoes')));
      await tester.pumpAndSettle();

      final call = api.calls.lastWhere(isSearchCall);
      expect(call.path, '/api/1688/search');
      expect(call.query['q'], 'shoes');
      expect(call.query['page'], 1);
    });

    testWidgets('a price filter stays on the keyword endpoint', (tester) async {
      // The bug this pins, and the test that used to assert the opposite.
      //
      // A filtered keyword search was sent to the gateway's cached index,
      // because this endpoint was believed to ignore price. It does ignore
      // `min_price` -- it reads `price_min`, which is what the storefront
      // sends and what was never tried. Measured: "geyser" returns fifty
      // products here and none from the cached index, so routing away from it
      // reported "No results" for a search that had just found fifty.
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'shoes')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Under Rs. 500'));
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      final call = api.calls.lastWhere(isSearchCall);
      expect(call.path, '/api/1688/search');
      expect(call.query['price_max'], 500);
    });

    testWidgets('and a category it cannot express does not', (tester) async {
      // The other half. This endpoint wants the numeric 1688 cid, so a cid of
      // any other shape cannot be sent -- and a filter dropped on the way out
      // is worse than a slower answer. Those go to the cached index, which can
      // express it.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const SearchResultsScreen(
            query: 'shoes',
            categoryCid: 'dept-1',
            categoryName: 'Electronics',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final call = api.calls.lastWhere(isSearchCall);
      expect(call.path, '/search/products');
      expect(call.query['category'], 'dept-1');
    });

    testWidgets('a numeric category rides along with the keyword', (
      tester,
    ) async {
      // The production shape: real cids are the 1688 numbers -- 57, 18, 6.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const SearchResultsScreen(
            query: 'shoes',
            categoryCid: '57',
            categoryName: 'Electronic components',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final call = api.calls.lastWhere(isSearchCall);
      expect(call.path, '/api/1688/search');
      expect(call.query['category_id'], '57');
    });

    testWidgets('and so does a chosen sort', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'shoes')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Relevance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Price: low to high'));
      await tester.pumpAndSettle();

      final call = api.calls.lastWhere(isSearchCall);
      expect(call.path, '/search/products');
      expect(call.query['sort'], 'price_asc');
    });

    testWidgets('browsing a department does too', (tester) async {
      // No query, just a category -- the keyword endpoint has nothing to search.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: '', categoryCid: 'dept-1')),
      );
      await tester.pumpAndSettle();

      final call = api.calls.lastWhere(isSearchCall);
      expect(call.path, '/search/products');
      expect(call.query['category'], 'dept-1');
    });
  });

  group('opening a subcategory', () {
    // The bug this group exists for. Of the thirty-two subcategory tiles the
    // home page shows, fourteen return nothing from the catalogue -- and one
    // department's four return nothing at all. Every one of those was a tap
    // that ended on an empty page, with a chip reading the literal word
    // "Department".

    testWidgets('asks the backend for that subcategory, not its parent', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const SearchResultsScreen(query: '', categoryCid: 'dept-1-child-0'),
        ),
      );
      await tester.pumpAndSettle();

      final call = api.calls.firstWhere(isSearchCall);
      expect(call.path, '/search/products');
      expect(call.query['category'], 'dept-1-child-0');
    });

    testWidgets('names the subcategory on its chip', (tester) async {
      // It used to read "Department" for as long as the page was open: the
      // lookup scanned the top level of the tree only, so a child cid never
      // matched anything and the placeholder was never replaced.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const SearchResultsScreen(query: '', categoryCid: 'dept-1-child-0'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Department'), findsNothing);
    });

    testWidgets('an empty one widens to its department, and says so', (
      tester,
    ) async {
      // Serves nothing for the child and the usual rows for anything else, so
      // the widening is exercised against the same endpoint the app uses.
      stubSearchWith(
        api,
        (call) =>
            call.query['category'] == 'dept-1-child-0' ? const [] : feedRows(3),
      );

      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const SearchResultsScreen(query: '', categoryCid: 'dept-1-child-0'),
        ),
      );
      await tester.pumpAndSettle();

      // It asked for the child first, and only then for the parent.
      final asked = api.calls
          .where(isSearchCall)
          .map((c) => c.query['category'])
          .toList();
      expect(asked, containsAllInOrder(['dept-1-child-0', 'dept-1']));

      // And the page says which is which rather than passing one off as the
      // other -- a wider set shown as the narrow one is how somebody buys the
      // wrong thing.
      expect(find.textContaining('Nothing in'), findsOneWidget);
      expect(find.textContaining('Showing all of'), findsOneWidget);
      expect(find.byType(ProductResultCard), findsWidgets);
    });

    testWidgets('a subcategory that has products is left alone', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const SearchResultsScreen(query: '', categoryCid: 'dept-1-child-0'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing in'), findsNothing);
      final asked = api.calls
          .where(isSearchCall)
          .map((c) => c.query['category'])
          .toSet();
      expect(asked, {'dept-1-child-0'}, reason: 'no second request');
    });

    testWidgets('a department with nothing does not widen to itself', (
      tester,
    ) async {
      // A top-level category has no parent to widen to, so it shows the plain
      // empty state rather than re-asking the same question.
      stubSearch(api, const []);

      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SearchResultsScreen(query: '', categoryCid: 'dept-1')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing in'), findsNothing);
      expect(find.text('Nothing matches these filters'), findsOneWidget);
    });
  });
}
