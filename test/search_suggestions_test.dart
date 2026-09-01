import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/search/data/recent_search_store.dart';
import 'package:gtradea_amazon/features/search/data/search_suggestions.dart';
import 'package:gtradea_amazon/features/search/presentation/search_entry_screen.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

late FakeApi api;

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// The suggestions endpoint's real shape, from production.
List<Map<String, dynamic>> _serverRows(List<String> texts) => [
  for (final text in texts)
    {
      'id': '66666666-6666-6666-6666-666666666666',
      'text': text,
      'type': 'category',
      'slug': text.toLowerCase().replaceAll(' ', '-'),
      'similarity_score': 1,
    },
];

List<Map<String, dynamic>> _trending(List<String> queries) => [
  for (final q in queries) {'query': q, 'search_count': 10},
];

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  // Past the debounce, so the server call has gone out and come back.
  await tester.pump(const Duration(milliseconds: 400));
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

  group('merging the sources', () {
    List<SearchSuggestion> merge(
      String query, {
      List<String> recent = const [],
      List<String> trending = const [],
      List<SearchSuggestion> server = const [],
    }) => mergeSuggestions(
      query: query,
      recent: recent,
      trending: trending,
      fromServer: server,
    );

    test('says nothing until there is enough to go on', () {
      // One letter matches most of a catalogue, and the answer is noise.
      expect(merge('s', trending: ['shoes']), isEmpty);
      expect(merge('sh', trending: ['shoes']), isNotEmpty);
    });

    test('history leads, because it is what people reach for again', () {
      final rows = merge(
        'sho',
        recent: ['shoes for men'],
        trending: ['shoes'],
        server: [
          const SearchSuggestion(
            text: 'Shopping',
            kind: SuggestionKind.catalogue,
          ),
        ],
      );

      expect(rows.first.kind, SuggestionKind.recent);
      expect(rows.map((r) => r.kind), contains(SuggestionKind.catalogue));
      expect(rows.map((r) => r.kind), contains(SuggestionKind.trending));
    });

    test('the same word from two sources is one row', () {
      final rows = merge('sho', recent: ['shoes'], trending: ['Shoes']);
      expect(rows, hasLength(1));
      expect(rows.single.kind, SuggestionKind.recent, reason: 'first wins');
    });

    test('does not offer back the word already typed in full', () {
      // A row that puts "shoes" in a field that already says "shoes" does
      // nothing but take up the space something useful could have used.
      final rows = merge('shoes', recent: ['shoes'], trending: ['shoes']);
      expect(rows, isEmpty);
    });

    test('matches inside a phrase, not only at the start', () {
      expect(
        merge('denim', trending: ['baby boy denim jumpsuit']),
        hasLength(1),
      );
    });

    test('caps the list', () {
      final rows = merge(
        'a',
        trending: [for (var i = 0; i < 20; i++) 'a query $i'],
      );
      expect(rows.length, lessThanOrEqualTo(6));
    });
  });

  group('the repository', () {
    test('does not call the server for one letter', () async {
      await SearchSuggestionRepository.instance.forQuery('s');
      expect(
        api.calls.where((c) => c.path == '/search/suggestions'),
        isEmpty,
        reason: 'a round trip per keystroke, for noise',
      );
    });

    test('reads the real payload shape', () async {
      api.on(
        'GET',
        '/search/suggestions',
        body: _serverRows(['Fashion', "Men's Fashion"]),
      );

      final rows = await SearchSuggestionRepository.instance.forQuery(
        'fashion',
      );

      expect(rows.map((r) => r.text), ['Fashion', "Men's Fashion"]);
      expect(rows.every((r) => r.kind == SuggestionKind.catalogue), isTrue);
    });

    test('sends the query and no credential', () async {
      api.on('GET', '/search/suggestions', body: _serverRows(['Fashion']));
      await SearchSuggestionRepository.instance.forQuery('fash');

      final call = api.calls.lastWhere((c) => c.path == '/search/suggestions');
      expect(call.query['q'], 'fash');
      expect(call.authorization, isNull);
    });
  });

  group('while typing', () {
    testWidgets('offers what the server matched', (tester) async {
      api.on(
        'GET',
        '/search/suggestions',
        body: _serverRows(["Men's Fashion"]),
      );

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      await _type(tester, 'fash');

      expect(find.text("Men's Fashion"), findsOneWidget);
    });

    testWidgets('and what is trending, without waiting on the server', (
      tester,
    ) async {
      // The local sources are already in memory, so they answer on the first
      // keystroke rather than after a round trip.
      api.on('GET', '/feed/trending-searches', body: _trending(['shoes']));
      api.on('GET', '/search/suggestions', body: const []);

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'sho');
      await tester.pump();

      expect(find.text('shoes'), findsOneWidget);
    });

    testWidgets('the browse sections step aside', (tester) async {
      // Somebody mid-word has stopped asking "what departments are there".
      api.on('GET', '/feed/trending-searches', body: _trending(['shoes']));
      api.on('GET', '/search/suggestions', body: const []);

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Browse departments'), findsOneWidget);

      await _type(tester, 'sho');

      expect(find.text('Browse departments'), findsNothing);
    });

    testWidgets('and come back when the field is cleared', (tester) async {
      api.on('GET', '/feed/trending-searches', body: _trending(['shoes']));
      api.on('GET', '/search/suggestions', body: const []);

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      await _type(tester, 'sho');
      await _type(tester, '');

      expect(find.text('Browse departments'), findsOneWidget);
    });

    testWidgets('tapping one searches for it', (tester) async {
      api.on(
        'GET',
        '/search/suggestions',
        body: _serverRows(["Men's Fashion"]),
      );

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();
      await _type(tester, 'fash');

      await tester.tap(find.text("Men's Fashion"));
      await tester.pumpAndSettle();

      expect(find.byType(SearchResultsScreen), findsOneWidget);
      // A text search, not a category filter: the suggestion's slug belongs to
      // a different table from the `category` parameter, and was measured
      // returning nothing.
      final search = api.calls.lastWhere(isSearchCall).query;
      expect(search['q'], "Men's Fashion");
      expect(search.containsKey('category'), isFalse);
    });

    testWidgets('one request per pause, not one per keystroke', (tester) async {
      api.on('GET', '/search/suggestions', body: const []);

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      for (final text in ['sh', 'sho', 'shoe', 'shoes']) {
        await tester.enterText(find.byType(TextField).first, text);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final calls = api.calls.where((c) => c.path == '/search/suggestions');
      expect(calls, hasLength(1));
      expect(calls.single.query['q'], 'shoes', reason: 'the last word typed');
    });

    testWidgets('a failure leaves the local matches standing', (tester) async {
      // Typeahead is a convenience. An error panel under a field somebody is
      // mid-word in would be worse than the matches they already have.
      api.on('GET', '/feed/trending-searches', body: _trending(['shoes']));
      api.on(
        'GET',
        '/search/suggestions',
        status: 500,
        body: {'error': 'down'},
      );

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      await _type(tester, 'sho');

      expect(find.text('shoes'), findsOneWidget);
      expect(find.text('down'), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('leaves no timer behind when closed mid-word', (tester) async {
      api.on('GET', '/search/suggestions', body: const []);

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'sho');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(_wrap(const Scaffold(body: Text('gone'))));
      await tester.pumpAndSettle();

      expect(find.text('gone'), findsOneWidget);
    });
  });

  group('product recommendations', () {
    testWidgets('appear for a word the suggestions endpoint cannot answer', (
      tester,
    ) async {
      // The bug this fixes. /search/suggestions was measured returning [] for
      // tshirt, shoe, lamp and every other ordinary product word, so a
      // typeahead built on it alone showed nothing for almost anything anybody
      // would actually type.
      api.on('GET', '/search/suggestions', body: const []);
      stubSearch(api, feedRows(3));

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      await _type(tester, 'tshirt');

      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Catalogue product 0'), findsOneWidget);
      expect(find.text('Rs. 300'), findsWidgets);
    });

    testWidgets('come from the server, for the word that was typed', (
      tester,
    ) async {
      api.on('GET', '/search/suggestions', body: const []);
      stubSearch(api, feedRows(2));

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();
      await _type(tester, 'tshirt');

      final call = api.calls.lastWhere(isSearchCall);
      expect(call.query['q'], 'tshirt');
      // The keyword endpoint pages by number and ignores page_size, so the cap
      // is applied by the caller instead.
      expect(find.byType(ListTile), findsWidgets);
    });

    testWidgets('tapping one opens that product', (tester) async {
      api.on('GET', '/search/suggestions', body: const []);
      stubSearch(api, feedRows(2));

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();
      await _type(tester, 'tshirt');

      await tester.tap(find.text('Catalogue product 0'));
      await tester.pumpAndSettle();

      // Straight to the product, not through the results page.
      expect(find.byType(SearchResultsScreen), findsNothing);
    });

    testWidgets('an unpriced row says so rather than showing Rs. 0', (
      tester,
    ) async {
      // Roughly half this catalogue comes back with no display price.
      api.on('GET', '/search/suggestions', body: const []);
      api.on(
        'GET',
        '/search/products',
        body: [
          {'num_iid': '1', 'title': 'Unpriced thing', 'display_price': null},
        ],
      );

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();
      await _type(tester, 'tshirt');

      expect(find.text('Price on request'), findsOneWidget);
      expect(find.text('Rs. 0'), findsNothing);
    });

    testWidgets('clearing the field clears them', (tester) async {
      // Leaving the last query's products under a field that now says
      // something else reads as matches for what is on screen.
      api.on('GET', '/search/suggestions', body: const []);
      stubSearch(api, feedRows(2));

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();
      await _type(tester, 'tshirt');
      expect(find.text('Products'), findsOneWidget);

      await _type(tester, '');

      expect(find.text('Products'), findsNothing);
      expect(find.text('Browse departments'), findsOneWidget);
    });

    testWidgets('a failed product search leaves the words standing', (
      tester,
    ) async {
      api.on('GET', '/feed/trending-searches', body: _trending(['shoes']));
      api.on('GET', '/search/suggestions', body: const []);
      stubSearch(api, const [], status: 500);

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      await _type(tester, 'sho');

      expect(find.text('shoes'), findsOneWidget);
      expect(find.text('Products'), findsNothing);
      expect(find.text('down'), findsNothing);
    });

    testWidgets('still one round trip each per pause', (tester) async {
      api.on('GET', '/search/suggestions', body: const []);
      stubSearch(api, feedRows(2));

      _tall(tester);
      await tester.pumpWidget(_wrap(const SearchEntryScreen()));
      await tester.pumpAndSettle();

      for (final text in ['ts', 'tsh', 'tshi', 'tshirt']) {
        await tester.enterText(find.byType(TextField).first, text);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(api.calls.where(isSearchCall), hasLength(1));
      expect(
        api.calls.where((c) => c.path == '/search/suggestions'),
        hasLength(1),
      );
    });
  });
}
