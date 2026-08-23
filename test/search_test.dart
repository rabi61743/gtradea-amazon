import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/search/data/search_content.dart';
import 'package:gtradea_amazon/features/search/presentation/search_entry_screen.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: child,
    );

void main() {
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

  testWidgets('the entry screen leads with recent searches', (tester) async {
    await tester.pumpWidget(_wrap(const SearchEntryScreen()));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('Trending searches'), findsOneWidget);
    expect(find.text('Search by image'), findsOneWidget);
    expect(find.text('Water geysers'), findsOneWidget);
  });

  testWidgets('tapping a trending query opens results for it', (tester) async {
    await tester.pumpWidget(_wrap(const SearchEntryScreen()));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Running shoes'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(SearchResultsScreen), findsOneWidget);
    expect(find.textContaining('Running shoes'), findsWidgets);
  });

  testWidgets('results show the count and every row', (tester) async {
    await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'geyser')));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('4 results'), findsOneWidget);
    expect(find.textContaining('Atlantis Pro'), findsOneWidget);
    // The saving is derived, not stored.
    expect(find.text('-64%'), findsOneWidget);
    expect(find.text('Sponsored'), findsOneWidget);
  });

  testWidgets('a filter narrows the list and can be cleared', (tester) async {
    await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'geyser')));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();

    // Applying is explicit: the sheet edits a copy, so tapping an option
    // alone must not change the results behind it.
    await tester.tap(find.widgetWithText(FilterChip, '4★ and above'));
    await tester.pump();
    expect(find.textContaining('Show 3 results'), findsOneWidget);

    await tester.tap(find.textContaining('Show 3 results'));
    await tester.pumpAndSettle();

    expect(find.text('3 results'), findsOneWidget);
    expect(find.text('Filters (1)'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear filters'));
    await tester.pump();
    expect(find.text('4 results'), findsOneWidget);
  });

  testWidgets('dismissing the sheet keeps the previous selection',
      (tester) async {
    await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'geyser')));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '4★ and above'));
    await tester.pump();

    // Close without applying.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('4 results'), findsOneWidget);
    expect(find.text('Filters'), findsOneWidget);
  });

  testWidgets('sorting by price reorders the rows', (tester) async {
    await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'geyser')));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Relevance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Price: low to high'));
    await tester.pumpAndSettle();

    expect(find.text('Price: low to high'), findsOneWidget);
    // Cheapest row first: Rs. 2,450 before Rs. 3,559.
    final prices = tester
        .widgetList<Text>(find.textContaining('Rs. '))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(prices.first, 'Rs. 2,450');
  });

  testWidgets('an impossible filter set shows the empty state', (tester) async {
    await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'geyser')));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    // No placeholder row is unrated, so this group alone empties the list.
    await tester.tap(find.widgetWithText(FilterChip, 'Unrated'));
    await tester.pump();
    await tester.tap(find.text('No matches'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing matches these filters'), findsOneWidget);
  });
}
