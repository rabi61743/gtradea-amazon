import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/features/home/widgets/hero_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Three banners, so the carousel has somewhere to advance to.
List<BannerItem> _items() => [
  for (final name in ['Toys', 'Fashion', 'Home'])
    BannerItem(
      headline: name,
      caption: 'Shop $name',
      cta: 'Shop now',
      tint: const Color(0xFF10424F),
    ),
];

const _interval = Duration(seconds: 4);

/// How much of the pill is filled, 0 to 1, off the widget that draws it.
///
/// The fill is animated, so a test reads it after letting that settle: what is
/// on screen a frame after a slide changes is the tween on its way, which is
/// the point of having one.
double _fill(WidgetTester tester) {
  final box = tester.widget<FractionallySizedBox>(
    find.descendant(
      of: find.byKey(HeroBanner.progressKey),
      matching: find.byType(FractionallySizedBox),
    ),
  );
  return box.widthFactor ?? 0;
}

Future<void> _pump(
  WidgetTester tester, {
  bool reduceMotion = false,
  int count = 3,
}) async {
  tester.view.physicalSize = const Size(1080, 2000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: HeroBanner(
            items: _items().take(count).toList(),
            interval: _interval,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  // Past the fill's own 240ms catch-up, so a reading is the pill's answer
  // rather than the tween's.
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Back on for this file: these tests are about the clock, and it is the
    // real one. The suite switches it off in flutter_test_config.dart because
    // an always-running clock is a tree that never settles.
    HeroBanner.autoplayEnabled = true;
  });

  tearDown(() => HeroBanner.autoplayEnabled = false);

  group('the hero card', () {
    testWidgets('takes 97% of the page and is centred in it', (tester) async {
      await _pump(tester);

      final page = tester.getRect(find.byType(HeroBanner));
      final card = tester.getRect(find.byType(InkWell).first);

      expect(card.width / page.width, closeTo(HeroBanner.widthFactor, 0.005));
      expect(card.left - page.left, closeTo(page.right - card.right, 0.5));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('and nothing sits below it any more', (tester) async {
      // A rail of dots used to, with a gap above it. Both are gone: the
      // indicator is inside the carousel now.
      await _pump(tester);

      // One child under the carousel's column, which is the carousel: no
      // rail, and no gap above one.
      final column = tester.widget<Column>(
        find
            .descendant(
              of: find.byType(HeroBanner),
              matching: find.byType(Column),
            )
            .first,
      );
      expect(column.children, hasLength(1));

      // And the card ends where the carousel does.
      final card = tester.getRect(find.byType(InkWell).first);
      final carousel = tester.getRect(find.byType(PageView));
      expect(card.bottom, closeTo(carousel.bottom, 1));

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the progress pill', () {
    testWidgets('is small, rounded and in Commerce Orange', (tester) async {
      await _pump(tester);

      final pill = tester.getSize(find.byKey(HeroBanner.progressKey));
      expect(pill.width, 52);
      expect(pill.height, 4);

      final clip = tester.widget<ClipRRect>(
        find.descendant(
          of: find.byKey(HeroBanner.progressKey),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(clip.borderRadius, BorderRadius.circular(4));

      // The fill is the brand's action colour; the track under it is a
      // neutral, faint enough to read on dark artwork and on bright.
      final boxes = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byKey(HeroBanner.progressKey),
              matching: find.byType(ColoredBox),
            ),
          )
          .map((box) => box.color)
          .toList();
      expect(boxes, contains(AppColors.commerceOrange));
      expect(boxes.any((c) => c.a > 0 && c.a < 0.6), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('sits inside the carousel, along the foot of the card', (
      tester,
    ) async {
      await _pump(tester);

      final card = tester.getRect(find.byType(InkWell).first);
      final pill = tester.getRect(find.byKey(HeroBanner.progressKey));

      expect(pill.bottom, lessThanOrEqualTo(card.bottom));
      expect(pill.top, greaterThan(card.top + card.height / 2));
      // Centred on the card rather than parked at one end.
      expect(pill.center.dx, closeTo(card.center.dx, 1));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('creeps along while a slide runs its turn', (tester) async {
      await _pump(tester);

      final early = _fill(tester);
      await tester.pump(_interval * 0.5);
      await tester.pump(const Duration(milliseconds: 300));
      final later = _fill(tester);

      // Three slides, half way through the first: a sixth of the way along.
      expect(later, greaterThan(early));
      expect(later, closeTo(1 / 6, 0.06));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('and steps on when the carousel turns the page', (
      tester,
    ) async {
      await _pump(tester);

      await tester.pump(_interval);
      // Frame by frame: one long pump advances the clock but gives the page's
      // own scroll a single tick, which is not how it moves.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(find.text('Fashion'), findsOneWidget);
      // The second of three slides, freshly started.
      expect(_fill(tester), closeTo(1 / 3, 0.08));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a swipe moves it, and it holds while the pause runs', (
      tester,
    ) async {
      await _pump(tester);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      // The start of the second slide of three: the swipe moved the pill on,
      // and the new slide begins its own turn rather than inheriting the last
      // one's progress.
      expect(_fill(tester), closeTo(1 / 3, 0.05));

      // A second in -- still inside the pause -- and it has not moved.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_fill(tester), closeTo(1 / 3, 0.05));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('and the carousel picks itself up again afterwards', (
      tester,
    ) async {
      // The behaviour this is all for: a swipe pauses the carousel, it does
      // not end it. Nothing should be able to leave the hero parked on a slide
      // for good.
      await _pump(tester);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(find.text('Fashion'), findsOneWidget);

      // Past the wait, and creeping again.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(_interval * 0.5);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_fill(tester), greaterThan(1 / 3 + 0.05));

      // And it turns the page on its own from there.
      await tester.pump(_interval);
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('Home'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('and the last slide loops back to the first', (tester) async {
      await _pump(tester);

      // Three slides: run the set out and it comes back round rather than
      // stopping at the end.
      for (var slide = 0; slide < 3; slide++) {
        await tester.pump(_interval);
        for (var i = 0; i < 14; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
      }

      expect(find.text('Toys'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a single banner is a full pill', (tester) async {
      // Nowhere to advance to, so the carousel is already at its end -- a full
      // pill rather than an empty one that will never fill.
      await _pump(tester, count: 1);

      final pill = tester.getSize(find.byKey(HeroBanner.progressKey));
      final fill = tester.getSize(
        find.descendant(
          of: find.byKey(HeroBanner.progressKey),
          matching: find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == AppColors.commerceOrange,
          ),
        ),
      );
      expect(fill.width, pill.width);
    });

    testWidgets('and reduced motion still says where you are', (tester) async {
      await _pump(tester, reduceMotion: true);

      // The first of three with nothing creeping, so the pill is at the start
      // of the set: it measures ground covered, and none has been.
      expect(_fill(tester), closeTo(0, 0.02));
      await tester.pump(_interval * 2);
      expect(find.text('Toys'), findsOneWidget);
    });

    testWidgets('the fill is the carousel\'s own interval, not a copy', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: HeroBanner(
              items: _items(),
              interval: const Duration(seconds: 10),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));

      // A fifth through the first slide of three, because there is one clock
      // rather than a pill with a duration of its own.
      expect(_fill(tester), closeTo(0.2 / 3, 0.05));

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
