import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/search/data/recent_search_store.dart';
import 'package:gtradea_amazon/features/search/data/search_models.dart';
import 'package:gtradea_amazon/features/search/presentation/search_entry_screen.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
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

/// The query parameters of the most recent search request.
Map<String, dynamic> lastSearch() =>
    api.calls.lastWhere((c) => c.path == '/search/products').query;

void main() {
  setUp(() {
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
    testWidgets('leads with recent searches, once there are any',
        (tester) async {
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

    testWidgets('offers the real departments rather than invented queries',
        (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Browse departments'), findsOneWidget);
      expect(find.text('Women'), findsOneWidget);
      // The subtitle names what is inside, which is what makes the row worth
      // its height.
      expect(find.textContaining('Women item 0'), findsWidgets);
    });

    testWidgets('a department opens results for that category, not its name',
        (tester) async {
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

  group('results', () {
    testWidgets('come from the server, with the query attached',
        (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'geyser')));
      await tester.pumpAndSettle();

      expect(lastSearch()['q'], 'geyser');
      expect(find.text('Catalogue product 0'), findsOneWidget);
      expect(find.text('Rs. 300'), findsOneWidget);
    });

    testWidgets('a price filter is sent to the server, not applied locally',
        (tester) async {
      // The catalogue is millions of rows and the response is one page of
      // them. Filtering that page would narrow twenty-four products and claim
      // there was nothing else.
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'geyser')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilterChip, 'Rs. 500 - 2,000'));
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      expect(lastSearch()['min_price'], 500);
      expect(lastSearch()['max_price'], 2000);
      expect(find.text('Filters (1)'), findsOneWidget);
    });

    testWidgets('clearing the filter asks again without it', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'geyser')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Under Rs. 500'));
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
      expect(lastSearch()['max_price'], 500);

      await tester.tap(find.byTooltip('Clear filters'));
      await tester.pumpAndSettle();

      expect(lastSearch().containsKey('max_price'), isFalse);
      expect(find.text('Filters'), findsOneWidget);
    });

    testWidgets('dismissing the sheet keeps the previous selection',
        (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'geyser')));
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

    testWidgets('sorting re-asks the server rather than reordering a page',
        (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'geyser')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Relevance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Price: low to high'));
      await tester.pumpAndSettle();

      expect(lastSearch()['sort'], 'price_asc');
      expect(find.text('Price: low to high'), findsOneWidget);
    });

    testWidgets('no results names the query that found nothing',
        (tester) async {
      api.on('GET', '/search/products', body: const []);
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'zzzz')));
      await tester.pumpAndSettle();

      expect(find.text('No results for "zzzz"'), findsOneWidget);
    });

    testWidgets('a failed search says so and offers a retry', (tester) async {
      api.on('GET', '/search/products',
          status: 500, body: {'error': 'search is down'});
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'x')));
      await tester.pumpAndSettle();

      expect(find.text('search is down'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('scrolling to the end asks for the next page', (tester) async {
      // A full page back means there is probably more. Stopping at 24 rows
      // would quietly cap the catalogue at 24 rows.
      api.on('GET', '/search/products', body: feedRows(24));
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'x')));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -4000));
      await tester.pumpAndSettle();

      expect(lastSearch()['page_offset'], 24);
    });

    testWidgets('a short page means there is no next one', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'x')));
      await tester.pumpAndSettle();
      final before = api.calls.length;

      await tester.drag(find.byType(ListView), const Offset(0, -4000));
      await tester.pumpAndSettle();

      expect(api.calls.length, before, reason: 'six rows is the whole answer');
    });
  });
}
