import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/home/data/fallback_banners.dart';
import 'package:gtradea_amazon/features/home/home_feed.dart';
import 'package:gtradea_amazon/features/home/widgets/hero_banner.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

late FakeApi api;

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

List<Map<String, dynamic>> serverBanners(int count) => [
  for (var i = 0; i < count; i++)
    {
      'id': 'banner-$i',
      'title': 'Campaign $i',
      'subtitle': 'Subtitle $i',
      'button_text': 'Shop $i',
      'button_link': '/search?q=thing$i',
      'background_image_url': 'https://example.invalid/b$i.jpg',
      'show_text_overlay': true,
      'is_active': true,
      'sort_order': i,
    },
];

Future<void> pumpFeed(WidgetTester tester) async {
  _phone(tester);
  await tester.pumpWidget(_wrap(const Scaffold(body: HomeFeed())));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CatalogStore.instance.resetForTest();
  });

  group('what the server sent', () {
    testWidgets('is what gets shown', (tester) async {
      api.on('GET', '/hero-banners', body: serverBanners(3));
      await pumpFeed(tester);

      final carousel = tester.widget<HeroBanner>(find.byType(HeroBanner));
      expect(carousel.items, hasLength(3));
      expect(carousel.items.first.headline, 'Campaign 0');
      expect(carousel.items.first.cta, 'Shop 0');
      expect(carousel.items.first.imageUrl, contains('b0.jpg'));
      // The built-in set stays out of the way when there are real campaigns.
      expect(find.text('Everything, from one place'), findsNothing);
    });

    testWidgets('artwork that carries its own words gets no overlay', (
      tester,
    ) async {
      api.on(
        'GET',
        '/hero-banners',
        body: [
          {
            'id': 'b',
            'title': 'Baked into the picture',
            'background_image_url': 'https://example.invalid/b.jpg',
            'show_text_overlay': false,
          },
        ],
      );
      await pumpFeed(tester);

      final item = tester
          .widget<HeroBanner>(find.byType(HeroBanner))
          .items
          .single;
      expect(item.headline, isEmpty);
      expect(item.caption, isEmpty);
      // Which is what stops the card darkening a picture to improve the
      // contrast of text that is not there.
      expect(item.isArtworkOnly, isTrue);
    });

    testWidgets('a campaign pointing nowhere this app has is not a button', (
      tester,
    ) async {
      api.on(
        'GET',
        '/hero-banners',
        body: [
          {'id': 'b', 'title': 'Web only', 'button_link': '/gift-cards'},
        ],
      );
      await pumpFeed(tester);

      final item = tester
          .widget<HeroBanner>(find.byType(HeroBanner))
          .items
          .single;
      expect(item.onTap, isNull);
    });
  });

  group('when the server has nothing to say', () {
    testWidgets('an empty list falls back to the built-in banners', (
      tester,
    ) async {
      api.on('GET', '/hero-banners', body: const []);
      await pumpFeed(tester);

      final carousel = tester.widget<HeroBanner>(find.byType(HeroBanner));
      expect(carousel.items, hasLength(kFallbackBanners.length));
      expect(find.text('Everything, from one place'), findsOneWidget);
    });

    testWidgets('so does a failure, without an error panel', (tester) async {
      api.on(
        'GET',
        '/hero-banners',
        status: 500,
        body: {'error': 'banners down'},
      );
      await pumpFeed(tester);

      expect(find.byType(HeroBanner), findsOneWidget);
      expect(find.text('Everything, from one place'), findsOneWidget);
      // A red retry panel where the storefront's artwork belongs is worse than
      // a storefront, and the rails below already report the same outage.
      expect(find.text('banners down'), findsNothing);
    });

    testWidgets('the built-in banners still go somewhere real', (tester) async {
      api.on('GET', '/hero-banners', body: const []);
      await pumpFeed(tester);

      final item = tester.widget<HeroBanner>(find.byType(HeroBanner)).items[1];
      expect(item.onTap, isNotNull);
      item.onTap!();
      await tester.pumpAndSettle();

      expect(find.byType(SearchResultsScreen), findsOneWidget);
    });

    test('none of them advertises an offer', () {
      // These appear when the server is silent, which is exactly when nothing
      // can confirm a discount -- and a made-up one would still be on screen
      // for a shopper who then found no such thing.
      const forbidden = ['%', 'off', 'sale', 'free', 'discount', 'save', 'rs.'];
      for (final item in kFallbackBanners) {
        final words =
            '${item.eyebrow} ${item.headline} ${item.caption} ${item.cta}'
                .toLowerCase();
        for (final word in forbidden) {
          expect(
            words.contains(word),
            isFalse,
            reason: '"${item.headline}" claims "$word"',
          );
        }
      }
    });

    test('and none of them needs the network to render', () {
      // The case they exist for is an unreachable server, and a device that
      // cannot reach the API usually cannot reach a CDN either.
      for (final item in kFallbackBanners) {
        expect(item.colors, hasLength(2));
        expect(item.cta, isNotEmpty);
      }
    });
  });

  group('while it is still loading', () {
    testWidgets('a skeleton holds the space the banner will take', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const Scaffold(body: HomeFeed())));
      await tester.pump();

      expect(find.byType(HeroBannerSkeleton), findsOneWidget);

      final skeleton = tester.getSize(find.byType(HeroBannerSkeleton));
      await tester.pumpAndSettle();
      final settled = tester.getSize(find.byType(HeroBanner));

      // Same height either way, so nothing below shifts when the real banners
      // arrive -- which is the whole reason to draw a placeholder at all.
      expect(skeleton.height, closeTo(settled.height, 1));
    });
  });

  group('sizing', () {
    test('keeps its proportions and stays inside its bounds', () {
      // A ratio rather than a fixed height, clamped at both ends: under the
      // floor the headline and button stop fitting, over the ceiling the banner
      // pushes the catalogue off the first screen.
      expect(HeroBanner.heightFor(320), 158);
      expect(HeroBanner.heightFor(420), closeTo(193, 1));
      expect(HeroBanner.heightFor(1400), 260);
    });
  });

  group('the indicator', () {
    testWidgets('is dots, with no slide count beside them', (tester) async {
      // It used to read "1/12" next to the dots once there were more of them
      // than the rail could show. Removed by request: the dots carry the
      // position, and a running total on a promotional banner is a fact about
      // the carousel rather than about anything for sale.
      api.on('GET', '/hero-banners', body: serverBanners(12));
      await pumpFeed(tester);

      expect(find.textContaining(RegExp(r'\d+\s*/\s*\d+')), findsNothing);
    });

    testWidgets('still says the position to a screen reader', (tester) async {
      // Taking the caption off the screen must not take the position away from
      // someone who cannot see the dots. This is now the only place it is said
      // in words, so it is the one that has to be pinned.
      final handle = tester.ensureSemantics();
      api.on('GET', '/hero-banners', body: serverBanners(12));
      await pumpFeed(tester);

      expect(find.bySemanticsLabel('Banner 1 of 12'), findsOneWidget);

      await tester.fling(
        find.byType(PageView).first,
        const Offset(-400, 0),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Banner 2 of 12'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a dot is a button, not a read-out', (tester) async {
      // The static "2 / 12" this replaced told you where you were and let you
      // do nothing about it.
      api.on('GET', '/hero-banners', body: serverBanners(4));
      await pumpFeed(tester);

      await tester.tap(find.bySemanticsLabel('Go to banner 3'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<PageView>(find.byType(PageView).first).controller!.page,
        2,
      );
    });

    testWidgets('picking one stops the carousel sliding away from under you', (
      tester,
    ) async {
      api.on('GET', '/hero-banners', body: serverBanners(4));
      await pumpFeed(tester);

      await tester.tap(find.bySemanticsLabel('Go to banner 3'));
      await tester.pumpAndSettle();
      // Well past the auto-advance interval.
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();

      expect(
        tester.widget<PageView>(find.byType(PageView).first).controller!.page,
        2,
      );
    });
  });
}
