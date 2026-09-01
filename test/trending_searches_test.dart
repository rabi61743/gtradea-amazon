import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/features/search/data/search_suggestions.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/search/data/recent_search_store.dart';
import 'package:gtradea_amazon/features/search/data/trending_searches.dart';
import 'package:gtradea_amazon/features/search/presentation/search_entry_screen.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

late FakeApi api;

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// The shape the endpoint actually returns, taken from production.
List<Map<String, dynamic>> _rows(List<(String, int)> entries) => [
  for (final (query, count) in entries) {'query': query, 'search_count': count},
];

Future<void> _pump(WidgetTester tester) async {
  _tall(tester);
  await tester.pumpWidget(_wrap(const SearchEntryScreen()));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SearchSuggestionRepository.instance.resetForTest();
    SharedPreferences.setMockInitialValues({});
    RecentSearchStore.instance.resetForTest();
    api = stubCatalog();
    CatalogStore.instance.resetForTest();
  });

  group('what gets promoted', () {
    test('an ordinary query does', () {
      expect(isPromotable('shoes'), isTrue);
      expect(isPromotable('baby boy denim jumpsuit'), isTrue);
    });

    test('an adult one does not, however often it is searched', () {
      // Real data: at the time of writing this sat seventh in the live list.
      // Reporting what people search for is right; putting it on the front
      // door as a suggestion is a different act.
      expect(isPromotable('penis sleeve'), isFalse);
      expect(isPromotable('Penis Sleeve'), isFalse, reason: 'case matters not');
    });

    test('an empty query does not', () {
      expect(isPromotable(''), isFalse);
      expect(isPromotable('   '.trim()), isFalse);
    });

    test('the list is small enough to actually be read', () {
      // It is an editorial decision, not a spam filter. A list that grows to
      // hundreds of entries is one nobody reviews.
      expect(kNotPromoted.length, lessThan(30));
      for (final term in kNotPromoted) {
        expect(term, term.toLowerCase(), reason: 'matched case-insensitively');
      }
    });
  });

  group('the repository', () {
    test('reads the real shape and ranks as the server sent it', () async {
      api.on(
        'GET',
        '/feed/trending-searches',
        body: _rows([('kidsfashion', 111), ('lamp', 90), ('shoes', 85)]),
      );

      final rows = await TrendingSearchRepository.instance.list();

      expect(rows.map((r) => r.query), ['kidsfashion', 'lamp', 'shoes']);
      expect(rows.first.count, 111);
    });

    test('drops a filtered term and promotes the next real one', () async {
      // Filtering before the cap, not after. Filtering after would leave a
      // short list with a gap where the dropped term was.
      api.on(
        'GET',
        '/feed/trending-searches',
        body: _rows([
          ('one', 9),
          ('penis sleeve', 8),
          ('two', 7),
          ('three', 6),
        ]),
      );

      final rows = await TrendingSearchRepository.instance.list(limit: 3);

      expect(rows.map((r) => r.query), ['one', 'two', 'three']);
    });

    test('caps the list', () async {
      api.on(
        'GET',
        '/feed/trending-searches',
        body: _rows([for (var i = 0; i < 20; i++) ('query $i', 20 - i)]),
      );

      expect(
        await TrendingSearchRepository.instance.list(limit: 8),
        hasLength(8),
      );
    });

    test('sends no credential -- trending is public', () async {
      api.on('GET', '/feed/trending-searches', body: _rows([('shoes', 5)]));
      await TrendingSearchRepository.instance.list();

      final call = api.calls.lastWhere(
        (c) => c.path == '/feed/trending-searches',
      );
      expect(call.authorization, isNull);
    });
  });

  group('on the search screen', () {
    testWidgets('shows what the backend actually returned', (tester) async {
      api.on(
        'GET',
        '/feed/trending-searches',
        body: _rows([('kidsfashion', 111), ('lamp', 90)]),
      );

      await _pump(tester);

      expect(find.text('Trending searches'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'kidsfashion'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'lamp'), findsOneWidget);
    });

    testWidgets('never the count beside the term', (tester) async {
      // A bare "111" next to a product word reads as a stock level or a price.
      api.on(
        'GET',
        '/feed/trending-searches',
        body: _rows([('kidsfashion', 111)]),
      );

      await _pump(tester);

      expect(find.text('111'), findsNothing);
      expect(find.textContaining('111'), findsNothing);
    });

    testWidgets('tapping one searches for it', (tester) async {
      api.on('GET', '/feed/trending-searches', body: _rows([('lamp', 90)]));
      await _pump(tester);

      await tester.tap(find.widgetWithText(ActionChip, 'lamp'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchResultsScreen), findsOneWidget);
      final search = api.calls.lastWhere(isSearchCall).query;
      expect(search['q'], 'lamp');
    });

    testWidgets('and remembers it, like any other search', (tester) async {
      api.on('GET', '/feed/trending-searches', body: _rows([('lamp', 90)]));
      await _pump(tester);

      await tester.tap(find.widgetWithText(ActionChip, 'lamp'));
      await tester.pumpAndSettle();

      expect(RecentSearchStore.instance.queries, contains('lamp'));
    });

    testWidgets('a failure leaves no heading behind', (tester) async {
      // A suggestion block that fails should look like a search screen without
      // one, not like a broken search screen.
      api.on(
        'GET',
        '/feed/trending-searches',
        status: 500,
        body: {'error': 'down'},
      );

      await _pump(tester);

      expect(find.text('Trending searches'), findsNothing);
      expect(find.text('down'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      // The rest of the screen is untouched.
      expect(find.text('Browse departments'), findsOneWidget);
    });

    testWidgets('nothing trending shows nothing at all', (tester) async {
      api.on('GET', '/feed/trending-searches', body: const []);
      await _pump(tester);

      expect(find.text('Trending searches'), findsNothing);
      expect(find.text('Browse departments'), findsOneWidget);
    });

    testWidgets('a list that is entirely filtered shows nothing', (
      tester,
    ) async {
      api.on(
        'GET',
        '/feed/trending-searches',
        body: _rows([('penis sleeve', 33)]),
      );

      await _pump(tester);

      expect(find.text('Trending searches'), findsNothing);
      expect(find.textContaining('penis'), findsNothing);
    });
  });
}
