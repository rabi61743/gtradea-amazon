import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/search/data/recent_search_store.dart';
import 'package:gtradea_amazon/features/search/data/search_suggestions.dart';
import 'package:gtradea_amazon/features/search/presentation/search_entry_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/catalog.dart';
import 'support/fake_api.dart';

late FakeApi api;

/// The two endpoints behind the typeahead, and what production charges for
/// them: suggestions answers in about 150ms, the keyword search in 1.4 to 2.3
/// seconds for about forty kilobytes.
const _fast = Duration(milliseconds: 150);
const _slow = Duration(seconds: 2);

Widget _wrap() => const MaterialApp(home: SearchEntryScreen());

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// Serves each endpoint after its real-world delay.
void _stubWithLatency({List<Map<String, dynamic>>? suggestions}) {
  api.onCall(
    'GET',
    '/search/suggestions',
    (call) => reply({
      'suggestions':
          suggestions ??
          [
            {'text': "Men's Fashion"},
          ],
    }, delay: _fast),
  );
  api.onCall(
    'GET',
    '/api/1688/search',
    (call) => reply({'items': feedRows(6)}, delay: _slow),
  );
}

int _callsTo(String path) =>
    api.calls.where((c) => c.path.contains(path)).length;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CatalogStore.instance.resetForTest();
    RecentSearchStore.instance.resetForTest();
    SearchSuggestionRepository.instance.resetForTest();
  });

  testWidgets('suggestions do not wait on the slow product call', (
    tester,
  ) async {
    // The whole point. These used to be joined with Future.wait, so the half
    // that answers in 150ms sat finished in memory for nearly two seconds
    // waiting for the half that does not -- and a shopper mid-word saw nothing
    // in the meantime.
    _tall(tester);
    _stubWithLatency();

    await tester.pumpWidget(_wrap());
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'men');

    // Past the debounce and past the fast endpoint, but nowhere near the slow
    // one.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(_fast);
    await tester.pump();

    expect(find.text("Men's Fashion"), findsOneWidget);
    expect(find.textContaining('Catalogue product'), findsNothing);

    // And the products fill in underneath when they land.
    await tester.pump(_slow);
    await tester.pumpAndSettle();
    expect(find.textContaining('Catalogue product'), findsWidgets);
  });

  testWidgets('a prefix already asked about answers without a request', (
    tester,
  ) async {
    // Typing is not a straight line: people overshoot and backspace.
    _tall(tester);
    _stubWithLatency();

    await tester.pumpWidget(_wrap());
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'men');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(_fast);
    await tester.pumpAndSettle();
    expect(_callsTo('/search/suggestions'), 1);

    // On to "mens" and straight back to "men".
    await tester.enterText(find.byType(TextField), 'mens');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'men');
    // One frame, no debounce: a remembered answer is painted with the
    // keystroke rather than a quarter of a second after it.
    await tester.pump();

    expect(find.text("Men's Fashion"), findsOneWidget);
    expect(
      _callsTo('/search/suggestions'),
      2,
      reason: 'men, mens, and no more',
    );

    // Let the slow half finish, so the test does not end on top of it.
    await tester.pump(_slow);
    await tester.pumpAndSettle();
  });

  testWidgets('an empty answer is remembered too', (tester) async {
    // The endpoint is sparse -- most ordinary words come back with nothing --
    // so "nothing" is the common result and re-asking for it is the common
    // waste.
    _tall(tester);
    _stubWithLatency(suggestions: const []);

    await tester.pumpWidget(_wrap());
    await tester.pump();

    for (var i = 0; i < 2; i++) {
      await tester.enterText(find.byType(TextField), 'tshirt');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'x');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    expect(_callsTo('/search/suggestions'), 1);

    await tester.pump(_slow);
    await tester.pumpAndSettle();
  });

  testWidgets('one empty answer settles every longer word containing it', (
    tester,
  ) async {
    // The largest saving available here, and it rests on a measured fact: the
    // endpoint matches substrings, case-insensitively. `ashion`, `shi` and
    // `FASHION` all return the Fashion categories, and `shi` only matches
    // because "fa*shi*on" contains it. Substring matching is monotone, so a
    // word that matched nothing settles every word containing it.
    //
    // On production, typing "kettle" asks five times and is answered once.
    // This is what makes it ask twice.
    _tall(tester);
    _stubWithLatency(suggestions: const []);

    await tester.pumpWidget(_wrap());
    await tester.pump();

    for (final typed in ['ke', 'ket', 'kett', 'kettl', 'kettle']) {
      await tester.enterText(find.byType(TextField), typed);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    expect(
      _callsTo('/search/suggestions'),
      1,
      reason: 'the first miss ended the asking',
    );

    await tester.pump(_slow);
    await tester.pumpAndSettle();
  });

  testWidgets('and it proves nothing about a word it is not inside', (
    tester,
  ) async {
    // The other half of the inference, and the one that keeps it honest: a miss
    // on "ke" says nothing about "bag", which does not contain it.
    _tall(tester);
    _stubWithLatency(suggestions: const []);

    await tester.pumpWidget(_wrap());
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ke');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'bag');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(_callsTo('/search/suggestions'), 2);

    await tester.pump(_slow);
    await tester.pumpAndSettle();
  });

  testWidgets('a query already fetched costs no second product call', (
    tester,
  ) async {
    // The expensive half. Measured on production the keyword search takes 1.6
    // to 1.8 seconds for about forty kilobytes, so overshooting a word and
    // coming back to it used to pay that twice.
    _tall(tester);
    _stubWithLatency();

    await tester.pumpWidget(_wrap());
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'shoes');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(_slow);
    await tester.pumpAndSettle();
    final first = _callsTo('/api/1688/search') + _callsTo('/search/products');
    expect(first, 1);

    // Away and back again.
    await tester.enterText(find.byType(TextField), 'shoesx');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'shoes');
    // One frame, no debounce: the rows are painted with the keystroke.
    await tester.pump();

    expect(
      _callsTo('/api/1688/search') + _callsTo('/search/products'),
      2,
      reason: '"shoes" and "shoesx" -- the return to "shoes" asked for nothing',
    );

    await tester.pump(_slow);
    await tester.pumpAndSettle();
  });

  testWidgets('a superseded request is cancelled, not just ignored', (
    tester,
  ) async {
    // Two seconds of a forty-kilobyte download still occupies the connection
    // the newest request needs. Dropping the answer on arrival was not enough.
    _tall(tester);
    _stubWithLatency();

    await tester.pumpWidget(_wrap());
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'sho');
    await tester.pump(const Duration(milliseconds: 300));
    // Mid-flight on the slow half.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'shoes');
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pump(_slow);
    await tester.pumpAndSettle();

    // The last query's products are the ones on screen, and nothing threw when
    // the abandoned one was cut off.
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Catalogue product'), findsWidgets);
  });

  testWidgets('leaving the screen mid-flight cancels rather than throws', (
    tester,
  ) async {
    _tall(tester);
    _stubWithLatency();

    await tester.pumpWidget(_wrap());
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'shoes');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));

    // Torn down with both halves outstanding.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(_slow);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
