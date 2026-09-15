import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/images/app_images.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/home/home_screen.dart';
import 'package:gtradea_amazon/features/promo/data/popup_banner.dart';
import 'package:gtradea_amazon/features/promo/data/popup_banner_store.dart';
import 'package:gtradea_amazon/features/promo/presentation/startup_popup_banner.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
import 'package:gtradea_amazon/features/tour/data/tour_store.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

/// A real, decodable picture, so the popup's "decoded first" rule is exercised
/// rather than skipped.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Map<String, dynamic> _banner({
  String id = 'maha-sale',
  String? link = '/search?q=sale',
  Object? active = true,
  String? end,
}) => {
  'id': id,
  'image_url': 'https://cdn.example.invalid/popup.png',
  'button_link': link,
  'alt_text': 'Maha Savings Sale',
  'is_active': active,
  'end_date': end,
};

void main() {
  late FakeApi api;
  ImageProvider Function(String)? previousImages;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    WishlistStore.instance.resetForTest();
    TourStore.instance.resetForTest();
    PopupBannerStore.instance.resetForTest();
    api = stubCatalog();
    previousImages = AppImages.providerOverride;
    AppImages.providerOverride = (_) => MemoryImage(_png);
    // Decoding cannot finish inside the test clock; the artwork is stated as
    // loaded, and one test below states that it failed.
    StartupPopupBanner.decodeOverride = (_) async => true;
  });

  tearDown(() {
    AppImages.providerOverride = previousImages;
    StartupPopupBanner.decodeOverride = null;
    TourStore.enabled = false;
    PopupBannerStore.instance.resetForTest();
    clearApiStub();
  });

  void serve(Object? value) => api.on(
    'GET',
    '/site-settings/app_popup_banner',
    body: {'setting_key': 'app_popup_banner', 'setting_value': value},
  );

  // Tall, like the other home screen suites: the hero's copy column overflows
  // on a short test viewport for reasons unrelated to the popup.
  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 4400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );
    // Real time for the disk and the fake network.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    // The check runs after a frame, and the popup opens on the frames after.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final popup = find.byType(StartupPopupBanner);

  group('the setting', () {
    test('decodes the admin value and rejects half-filled ones', () {
      final b = PopupBanner.fromJson(_banner())!;
      expect(b.id, 'maha-sale');
      expect(b.buttonLink, '/search?q=sale');
      expect(PopupBanner.fromJson(null), isNull);
      expect(PopupBanner.fromJson({'id': 'x'}), isNull, reason: 'no picture');
      expect(PopupBanner.fromJson({'image_url': 'u'}), isNull, reason: 'no id');
    });

    test('is live inside its dates, through the whole last day', () {
      final b = PopupBanner.fromJson({
        ..._banner(),
        'start_date': '2026-09-19',
        'end_date': '2026-09-20',
      })!;
      expect(b.isLive(DateTime(2026, 9, 18, 23)), isFalse);
      expect(b.isLive(DateTime(2026, 9, 19, 8)), isTrue);
      expect(b.isLive(DateTime(2026, 9, 20, 23, 59)), isTrue);
      expect(b.isLive(DateTime(2026, 9, 21)), isFalse);
      expect(
        PopupBanner.fromJson(_banner(active: false))!.isLive(DateTime.now()),
        isFalse,
      );
    });

    test('the card stays portrait and phone-sized on any screen', () {
      for (final screen in const [
        Size(360, 740),
        Size(800, 1280),
        Size(1400, 900),
      ]) {
        final card = StartupPopupBanner.cardSize(screen);
        expect(card.width, lessThanOrEqualTo(StartupPopupBanner.maxWidth));
        expect(card.height, lessThanOrEqualTo(screen.height * 0.78 + 0.001));
        expect(card.width / card.height, closeTo(9 / 16, 0.001));
      }
    });
  });

  testWidgets('nothing is set: no popup', (tester) async {
    serve(null);
    await launch(tester);
    expect(popup, findsNothing);
  });

  testWidgets('a live banner opens once the storefront is ready', (
    tester,
  ) async {
    serve(_banner());
    await launch(tester);
    expect(popup, findsOneWidget);
    expect(find.byKey(const ValueKey('popup-close')), findsOneWidget);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> close(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('popup-close')));
    await tester.pumpAndSettle();
    expect(popup, findsNothing);
  }

  testWidgets('every fresh launch shows it again, even after closing it', (
    tester,
  ) async {
    serve(_banner());
    await launch(tester);
    expect(popup, findsOneWidget);
    await close(tester);

    // The app fully closed and opened again: a new process, so the in-memory
    // launch state starts over.
    await tester.pumpWidget(const SizedBox());
    PopupBannerStore.instance.resetForTest();
    await launch(tester);
    expect(popup, findsOneWidget);
  });

  testWidgets('returning from the background does not show it again', (
    tester,
  ) async {
    serve(_banner());
    await launch(tester);
    await close(tester);

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(popup, findsNothing);
  });

  testWidgets('moving between pages does not show it again', (tester) async {
    serve(_banner());
    await launch(tester);
    await close(tester);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('p')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(popup, findsNothing);
  });

  testWidgets('a rebuilt home screen in the same run does not show it again', (
    tester,
  ) async {
    serve(_banner());
    await launch(tester);
    await close(tester);

    // Same process, home screen torn down and built again.
    await tester.pumpWidget(const SizedBox());
    await launch(tester);
    expect(popup, findsNothing);
  });

  testWidgets('switched off or expired: no popup', (tester) async {
    serve(_banner(active: false));
    await launch(tester);
    expect(popup, findsNothing);

    await tester.pumpWidget(const SizedBox());
    PopupBannerStore.instance.resetForTest();
    serve(_banner(end: '2020-01-01'));
    await launch(tester);
    expect(popup, findsNothing);
  });

  testWidgets('a launch that opens the tour leaves the popup for next time', (
    tester,
  ) async {
    TourStore.enabled = true;
    serve(_banner());
    await launch(tester);
    expect(popup, findsNothing);
  });

  testWidgets('artwork that will not load means no popup, not an empty box', (
    tester,
  ) async {
    StartupPopupBanner.decodeOverride = (_) async => false;
    serve(_banner());
    await launch(tester);
    expect(popup, findsNothing);
  });

  testWidgets('a server failure is silent', (tester) async {
    api.on(
      'GET',
      '/site-settings/app_popup_banner',
      status: 500,
      body: const {},
    );
    await launch(tester);
    expect(popup, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the artwork follows its search link', (tester) async {
    serve(_banner());
    await launch(tester);
    await tester.tap(find.byKey(const ValueKey('popup-artwork')));
    await tester.pumpAndSettle();
    expect(popup, findsNothing);
    final results = tester.widget<SearchResultsScreen>(
      find.byType(SearchResultsScreen),
    );
    expect(results.query, 'sale');
  });

  for (final size in const [Size(360, 640), Size(800, 1280), Size(1400, 900)]) {
    testWidgets('fits at ${size.width.toInt()} dp without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final banner = PopupBanner.fromJson(_banner())!;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => StartupPopupBanner.show(
                context,
                banner: banner,
                image: MemoryImage(_png),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(popup, findsOneWidget);
      expect(tester.takeException(), isNull);
      final card = tester.getSize(find.byKey(const ValueKey('popup-artwork')));
      expect(card.width, lessThanOrEqualTo(StartupPopupBanner.maxWidth));
      final centre = tester.getCenter(
        find.byKey(const ValueKey('popup-artwork')),
      );
      expect(centre.dx, closeTo(size.width / 2, 0.5), reason: 'centred');
      expect(centre.dy, closeTo(size.height / 2, 0.5), reason: 'centred');
      final close = tester.getRect(find.byKey(const ValueKey('popup-close')));
      expect(close.width, greaterThanOrEqualTo(44), reason: 'tap target');
      final screen = Offset.zero & size;
      expect(screen.contains(close.topLeft), isTrue, reason: 'close on screen');
      expect(screen.contains(close.bottomRight), isTrue);
    });
  }
}
