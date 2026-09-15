import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/home/home_screen.dart';
import 'package:gtradea_amazon/features/home/widgets/search_header.dart';
import 'package:gtradea_amazon/shared/widgets/brand_lockup.dart';
import 'package:gtradea_amazon/shared/widgets/brand_wordmark.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);

void _screen(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width * 2, 2000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    stubCatalog();
    CatalogStore.instance.resetForTest();
  });

  tearDown(clearApiStub);

  group('the brand block', () {
    testWidgets('is the mark, the name and the line under it', (tester) async {
      _screen(tester, 400);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      expect(find.byType(BrandLockup), findsOneWidget);
      // The supplied mark, unmodified, in its on-dark version.
      final mark = tester.widget<BrandWordmark>(find.byType(BrandWordmark));
      expect(
        AppBrand.logoFor(mark.background ?? Colors.white),
        AppBrand.logoOnDarkAsset,
      );
      // The name, split where the artwork splits it, and the tagline.
      expect(find.textContaining('gtradea'), findsOneWidget);
      expect(find.text('Beyond Borders.'), findsOneWidget);
      // The country banner, opposite it: artwork now, where the words used to
      // be set. Nothing is written in their place -- if the supplied file is
      // missing the slot is empty, and the sentence does not come back.
      expect(find.text('Proudly Nepal'), findsNothing);

      // The artwork itself, right-aligned on the brand row and sized against
      // the mark opposite it rather than against a number of its own.
      final banner = tester.widget<Image>(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName.contains('proudly_nepal'),
        ),
      );
      expect(banner.fit, BoxFit.contain, reason: 'no stretch, no crop');

      final art = tester.getRect(find.byWidget(banner));
      final lockup = tester.getRect(find.byType(BrandLockup));
      expect(art.left, greaterThan(lockup.right), reason: 'opposite the mark');
      expect(
        art.height,
        greaterThan(lockup.height),
        reason: 'the reference draws it taller than the mark',
      );
    });

    testWidgets('says the company name once, to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      _screen(tester, 400);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      expect(find.bySemanticsLabel(AppBrand.name), findsOneWidget);
      handle.dispose();
    });

    testWidgets('grows with the screen, and gives way on a small one', (
      tester,
    ) async {
      final sizes = <double, double>{};
      for (final width in [320.0, 400.0, 760.0]) {
        _screen(tester, width);
        await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
        await tester.pump();

        sizes[width] = tester
            .widget<BrandLockup>(find.byType(BrandLockup))
            .height;
        expect(tester.takeException(), isNull, reason: '$width');
      }

      expect(sizes[320.0]! < sizes[400.0]!, isTrue);
      expect(sizes[400.0]! < sizes[760.0]!, isTrue);
    });

    testWidgets('and the header is taller for it, without losing anything', (
      tester,
    ) async {
      _screen(tester, 400);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final header = tester.getSize(find.byType(SearchHeader));
      // Three rows now -- brand, chrome, search -- where the mark used to
      // share the chrome row.
      expect(header.height, greaterThan(150));

      // Everything the header carried is still on it.
      expect(find.byKey(SearchHeader.pillKey), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      // Messages has the cart's old slot in this group, by request; the cart
      // itself is still on the bottom bar.
      expect(find.text('Messages'), findsOneWidget);
    });

    testWidgets('and the room above the first row is the head room, only', (
      tester,
    ) async {
      // The header's top padding was 28, then 18, and is 8 now. The middle
      // step measured correctly and was invisible on a phone -- the status bar
      // above it is forty points, so ten points off is a seventh of the space
      // over the mark. Measured here
      // rather than read off a screenshot because the two contributors to the
      // space above the brand are easy to confuse: this padding, and the
      // status-bar inset the header absorbs so the teal runs behind the clock.
      //
      // A test view has no status-bar inset, so what is left between the top of
      // the header and the top of its first row is the padding and nothing
      // else -- which is the number this pins.
      _screen(tester, 400);
      await tester.pumpWidget(_wrap(SearchHeader(onTap: () {})));
      await tester.pump();

      final header = tester.getRect(find.byType(SearchHeader));
      final lockup = tester.getRect(find.byType(BrandLockup));
      final art = tester.getRect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName.contains('proudly_nepal'),
        ),
      );

      // The country artwork is drawn taller than the mark, so whichever way the
      // row aligns its children, the artwork's top *is* the row's top. Asserted
      // rather than assumed, because the measurement below rests on it.
      expect(art.height, greaterThanOrEqualTo(lockup.height));
      expect(
        art.top - header.top,
        closeTo(8, 0.5),
        reason: 'the head room, with no status-bar inset in a test',
      );

      // And the mark cannot have been pushed above it: a negative gap would
      // mean the row had escaped its own padding.
      expect(lockup.top - header.top, greaterThanOrEqualTo(8 - 0.5));
    });
  });

  group('the glass', () {
    Future<void> pumpShell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is the mountains themselves, not a sheet of blue', (
      tester,
    ) async {
      await pumpShell(tester);

      // No blur at all any more: a blurred mountain is an unrecognisable
      // one, and the artwork is meant to be seen.
      expect(find.byType(BackdropFilter), findsNothing);

      // The colour is the band's own ramp -- a second sheet of blue over it
      // was the heavy treatment the design rules out.
      //
      // Two stops now, by specification, where it was three. It also runs the
      // other way: the old foot was a shade *above* Trust Blue so the band
      // lifted into the page, and this one sinks into it. Nothing is lost on
      // legibility -- white measures 14.66:1 on the new foot against the 4.57
      // the old one was tuned to reach.
      final band = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.gradient == AppColors.brandBand);
      expect((band.gradient! as LinearGradient).colors, [
        AppColors.brandBandHead,
        AppColors.brandBandDeep,
      ]);

      // And the Himalayan artwork is drawn at the strength the design asks
      // for -- 45-60% -- in the band's own blues rather than in grey.
      expect(band.image!.opacity, lessThanOrEqualTo(0.60));
      expect(band.image!.opacity, greaterThanOrEqualTo(0.45));
      expect(band.image!.colorFilter, isNotNull);
    });

    testWidgets('and the band is straight across its foot', (tester) async {
      // Three shapes in three revisions: two 16pt cut corners, then a downward
      // bulge, then an arch. It is a plain straight edge now, by request --
      // nothing is cut out of the band at all.
      await pumpShell(tester);

      expect(
        find.ancestor(
          of: find.byType(SearchHeader),
          matching: find.byType(ClipPath),
        ),
        findsNothing,
        reason: 'nothing shapes the foot of the band any more',
      );

      // Nor rounding: the corners went with the curve rather than coming back,
      // so a ClipRRect reappearing over the band would be a change of design
      // and not a detail. Only the bottom pair matters -- the top of the band
      // runs under the status bar and has never been cut.
      final rounded = tester
          .widgetList<ClipRRect>(
            find.ancestor(
              of: find.byType(SearchHeader),
              matching: find.byType(ClipRRect),
            ),
          )
          .map((c) => c.borderRadius)
          .whereType<BorderRadius>()
          .where((r) => r.bottomLeft.x > 0 || r.bottomRight.x > 0);
      expect(rounded, isEmpty);

      // The 36pt strip that gave the arch something to cut went with it, so the
      // band is shorter than it was -- but it still holds all three rows.
      //
      // 170 rather than 190 since the three actions were compacted: their
      // blurred field went from 52 to 44, and the band came down with it. The
      // bound is a floor under "all three rows are still in here", not a
      // measurement of the design -- the assertions above are what actually
      // keep the foot straight, and a floor set to whatever the header last
      // happened to measure turns every deliberate tightening into a failure.
      final header = tester.getRect(find.byType(SearchHeader));
      expect(header.height, greaterThan(170));
    });
  });
}
