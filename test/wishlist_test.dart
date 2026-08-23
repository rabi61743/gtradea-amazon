import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/product/presentation/image_viewer_screen.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:gtradea_amazon/features/wishlist/presentation/wishlist_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _jacket = SavedProduct(
  id: 'jacket',
  title: 'Ice silk jacket',
  price: 1130,
  listPrice: 1568,
);

const _dress = SavedProduct(id: 'dress', title: 'Suspender dress', price: 1808);

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WishlistStore.instance.resetForTest();
  });

  group('WishlistStore', () {
    test('toggle adds, reports the new state, and toggles back off', () {
      final store = WishlistStore.instance;
      expect(store.contains('jacket'), isFalse);

      expect(store.toggle(_jacket), isTrue);
      expect(store.contains('jacket'), isTrue);
      expect(store.count, 1);

      expect(store.toggle(_jacket), isFalse);
      expect(store.contains('jacket'), isFalse);
    });

    test('newest saved comes first', () {
      final store = WishlistStore.instance
        ..toggle(_jacket)
        ..toggle(_dress);
      expect(store.items.map((e) => e.id), ['dress', 'jacket']);
    });

    test('saving the same product twice does not duplicate it', () {
      final store = WishlistStore.instance..toggle(_jacket);
      // Same id, different price -- identity is the id, not the payload.
      store.toggle(const SavedProduct(
        id: 'jacket',
        title: 'Ice silk jacket',
        price: 999,
      ));
      expect(store.count, 0, reason: 'second toggle removes it');
    });

    test('survives a reload from disk', () async {
      WishlistStore.instance.toggle(_jacket);
      // Let the fire-and-forget write land before reading it back.
      await Future<void>.delayed(Duration.zero);

      WishlistStore.instance.resetForTest();
      await WishlistStore.instance.load();

      expect(WishlistStore.instance.contains('jacket'), isTrue);
      expect(WishlistStore.instance.items.first.title, 'Ice silk jacket');
    });

    test('a corrupt store degrades to empty rather than throwing', () async {
      SharedPreferences.setMockInitialValues({'gtradea_wishlist': 'not json'});
      WishlistStore.instance.resetForTest();
      await WishlistStore.instance.load();
      expect(WishlistStore.instance.items, isEmpty);
    });

    test('entries missing an id are skipped, not fatal', () async {
      SharedPreferences.setMockInitialValues({
        'gtradea_wishlist':
            '[{"title":"no id","price":1},{"id":"ok","title":"Fine","price":2}]',
      });
      WishlistStore.instance.resetForTest();
      await WishlistStore.instance.load();
      expect(WishlistStore.instance.items.map((e) => e.id), ['ok']);
    });
  });

  testWidgets('the empty list explains how to fill it', (tester) async {
    await tester.pumpWidget(_wrap(const WishlistScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Nothing saved yet'), findsOneWidget);
    expect(find.text('Clear all'), findsNothing);
  });

  testWidgets('saved products are listed with their price', (tester) async {
    WishlistStore.instance.toggle(_jacket);
    await tester.pumpWidget(_wrap(const WishlistScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Ice silk jacket'), findsOneWidget);
    expect(find.text('Rs. 1,130'), findsOneWidget);
    expect(find.text('Rs. 1,568'), findsOneWidget);
  });

  testWidgets('removing one offers an undo that really restores it',
      (tester) async {
    WishlistStore.instance.toggle(_jacket);
    await tester.pumpWidget(_wrap(const WishlistScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove'));
    await tester.pump();
    expect(WishlistStore.instance.count, 0);

    // Let the snack bar finish animating in; tapping mid-slide misses it.
    await tester.pump(const Duration(milliseconds: 750));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(WishlistStore.instance.contains('jacket'), isTrue);
  });

  testWidgets('clearing everything asks first', (tester) async {
    WishlistStore.instance
      ..toggle(_jacket)
      ..toggle(_dress);
    await tester.pumpWidget(_wrap(const WishlistScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('Clear your saved list?'), findsOneWidget);

    // Backing out must keep the list intact.
    await tester.tap(find.text('Keep them'));
    await tester.pumpAndSettle();
    expect(WishlistStore.instance.count, 2);
  });

  testWidgets('the image viewer shows a page counter and closes', (tester) async {
    await tester.pumpWidget(_wrap(
      const ImageViewerScreen(
        images: ['https://example.invalid/1.jpg', 'https://example.invalid/2.jpg'],
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('1/2'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsWidgets);
    expect(find.byTooltip('Close'), findsOneWidget);
  });
}
