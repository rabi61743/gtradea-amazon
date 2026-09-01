import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/catalog_store.dart';
import 'package:gtradea_amazon/features/home/widgets/department_tabs.dart';
import 'package:gtradea_amazon/features/search/presentation/search_results_screen.dart';
import 'package:gtradea_amazon/features/search/widgets/product_result_card.dart';
import 'package:gtradea_amazon/shared/widgets/brand_loader.dart';
import 'package:gtradea_amazon/shared/widgets/brand_wordmark.dart';
import 'package:gtradea_amazon/shared/widgets/loading_gate.dart';
import 'package:gtradea_amazon/shared/widgets/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

late FakeApi api;

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// A gate with a settled `loading: false`, so the loader is never scheduled.
Widget _gate({required bool loading, Duration? delay}) => _wrap(
  Scaffold(
    body: LoadingGate(
      loading: loading,
      delay: delay ?? const Duration(milliseconds: 180),
      loadingChild: const Text('placeholder'),
      child: const Text('content'),
    ),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = stubCatalog();
    CatalogStore.instance.resetForTest();
  });

  group('the gate', () {
    testWidgets('shows nothing at all for a wait too short to notice', (
      tester,
    ) async {
      // A cached tree answers in single-digit milliseconds. A placeholder for
      // one frame and then content is a flash, and a flash reads as a fault --
      // it is what people mean when a fast app feels janky.
      await tester.pumpWidget(_gate(loading: true));
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('placeholder'), findsNothing);

      // Answered inside the delay.
      await tester.pumpWidget(_gate(loading: false));
      await tester.pumpAndSettle();

      expect(find.text('content'), findsOneWidget);
      expect(find.text('placeholder'), findsNothing);
    });

    testWidgets('shows the placeholder once the wait is real', (tester) async {
      await tester.pumpWidget(_gate(loading: true));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('placeholder'), findsOneWidget);
    });

    testWidgets('keeps it up long enough to be read', (tester) async {
      // Otherwise an answer landing just after the delay expired makes the
      // placeholder appear and vanish, which is the glitch the delay was
      // trying to avoid in the first place.
      await tester.pumpWidget(_gate(loading: true));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('placeholder'), findsOneWidget);

      await tester.pumpWidget(_gate(loading: false));
      await tester.pump(const Duration(milliseconds: 60));

      expect(
        find.text('placeholder'),
        findsOneWidget,
        reason: 'still inside its minimum',
      );

      await tester.pumpAndSettle();
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('leaves no timer behind when disposed mid-wait', (
      tester,
    ) async {
      // A timer outliving the tree fails the test that pumped it and leaks in
      // the app.
      await tester.pumpWidget(_gate(loading: true));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpWidget(_wrap(const Scaffold(body: Text('gone'))));
      await tester.pumpAndSettle();

      expect(find.text('gone'), findsOneWidget);
    });
  });

  group('the brand loader', () {
    testWidgets('centres the supplied mark inside the ring', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(const Scaffold(body: Center(child: BrandLoader(size: 88)))),
      );
      await tester.pump();

      // The logo itself, not a redrawing of it for the loader.
      expect(find.byType(BrandWordmark), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('says what is being waited for', (tester) async {
      // "Loading" alone tells somebody only that they are waiting, which they
      // can already see.
      _phone(tester);
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: Center(child: BrandLoader(label: 'Loading products')),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Loading products'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading products'), findsWidgets);

      handle.dispose();
    });

    testWidgets('holds still when the platform asks for reduced motion', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: Center(child: BrandLoader())),
          ),
        ),
      );

      // Settles, which a perpetual spin never would -- and which is what makes
      // this safe to put on a screen a test pumps.
      await tester.pumpAndSettle();
      expect(find.byType(BrandLoader), findsOneWidget);
    });
  });

  group('the product skeleton', () {
    testWidgets('is the exact size the real cards will be', (tester) async {
      // The whole point. A placeholder that is merely a similar size shifts the
      // layout the moment the products land.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(12),
              child: ResultGridSkeleton(count: 2),
            ),
          ),
        ),
      );
      await tester.pump();

      final cards = tester.widgetList<SizedBox>(
        find.descendant(
          of: find.byType(ResultGridSkeleton),
          matching: find.byType(SizedBox),
        ),
      );
      final sized = cards.where((b) => b.width != null && b.height != null);
      expect(sized, isNotEmpty);

      final available = 1100 / 2 - 24;
      final width = ProductResultCard.widthFor(available);
      final context = tester.element(find.byType(ResultGridSkeleton));
      final height = ProductResultCard.heightFor(context, width);

      expect(
        sized.any((b) => b.width == width && b.height == height),
        isTrue,
        reason: 'skeleton cards must be ${width}x$height',
      );
    });

    testWidgets('has a bone for every part of the real card', (tester) async {
      // A skeleton missing the add-to-cart button is a skeleton that shifts
      // when the button appears.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(12),
              child: ResultGridSkeleton(count: 1),
            ),
          ),
        ),
      );
      await tester.pump();

      // Price, cart button, two title lines, sold line -- plus the one the
      // picture panel builds inside itself, which is six.
      expect(find.byType(ShimmerBone), findsNWidgets(6));
      expect(find.byType(ShimmerPanel), findsOneWidget);
    });

    testWidgets('drives every bone from one ticker', (tester) async {
      // Six cards is eighteen bones. Eighteen controllers would be eighteen
      // tickers dirtying their own subtrees, on the frames where the main
      // thread is already busiest.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(12),
              child: ResultGridSkeleton(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Shimmer), findsOneWidget);
      expect(find.byType(ShimmerBone), findsWidgets);
    });

    testWidgets('a bone with no shimmer above it still renders', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const Scaffold(body: Center(child: ShimmerBone(width: 40)))),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ShimmerBone), findsOneWidget);
    });
  });

  group('the category skeleton', () {
    testWidgets('reserves exactly the strip height, so nothing shifts', (
      tester,
    ) async {
      // Without it the strip appears out of nothing when the tree lands and
      // shoves the whole storefront down.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(const Scaffold(body: DepartmentTabsSkeleton())),
      );
      await tester.pump();

      final context = tester.element(find.byType(DepartmentTabsSkeleton));
      final expected = DepartmentTabs.heightFor(context);
      final actual = tester.getSize(find.byType(DepartmentTabsSkeleton)).height;

      // The strip's own two points of bottom padding.
      expect(actual, expected + 2);
    });

    testWidgets('matches the real strip within a point', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: DepartmentTabs(
              categories: const [],
              selectedCid: null,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      final real = tester.getSize(find.byType(DepartmentTabs)).height;

      await tester.pumpWidget(
        _wrap(const Scaffold(body: DepartmentTabsSkeleton())),
      );
      await tester.pump();
      final skeleton = tester
          .getSize(find.byType(DepartmentTabsSkeleton))
          .height;

      expect(skeleton, closeTo(real, 1));
    });
  });

  group('on the results screen', () {
    testWidgets('a fast answer never flashes a skeleton', (tester) async {
      // The stub answers immediately, which is the case the gate exists for.
      _phone(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'x')));
      await tester.pump();

      expect(find.byType(ResultGridSkeleton), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byType(ProductResultCard), findsWidgets);
      expect(find.byType(ResultGridSkeleton), findsNothing);
    });

    testWidgets('and no skeleton lingers once the products are up', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_wrap(const SearchResultsScreen(query: 'x')));
      await tester.pumpAndSettle();

      expect(find.byType(ProductResultCard), findsWidgets);
      expect(find.byType(ShimmerBone), findsNothing);
    });
  });

  group('the loader is sized and centred', () {
    testWidgets('the mark sits in the middle of the ring, not against it', (
      tester,
    ) async {
      // The wordmark aligns to the start by default -- correct for a header
      // row -- and its Align expands to fill whatever box it is given. In the
      // ring that pinned the mark to the left edge instead of the centre.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(const Scaffold(body: Center(child: BrandLoader(size: 100)))),
      );
      await tester.pump();

      final ring = tester.getRect(_ringOf(BrandLoader));
      // The drawn picture, not the BrandWordmark box -- that box fills the
      // Stack either way, so measuring it would pass even with the mark pinned
      // hard left, which is the bug this is here to catch.
      final mark = tester.getRect(find.byType(SvgPicture));

      expect(mark.center.dx, closeTo(ring.center.dx, 0.5));
      expect(mark.center.dy, closeTo(ring.center.dy, 0.5));
    });

    testWidgets('the mark stays clear of the ring stroke', (tester) async {
      // It is a logo inside a ring, not a logo with a ring drawn across it.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(const Scaffold(body: Center(child: BrandLoader(size: 100)))),
      );
      await tester.pump();

      final mark = tester.getRect(find.byType(SvgPicture));
      expect(mark.height, lessThan(100 * 0.6));
    });

    testWidgets('the full-screen loader is modest, not a splash', (
      tester,
    ) async {
      // It appears on a cold start over an empty page, where a large mark reads
      // as a brand interstitial rather than as something loading.
      _phone(tester);
      await tester.pumpWidget(_wrap(const BrandLoaderScreen()));
      await tester.pump();

      final ring = tester.getSize(_ringOf(BrandLoader));
      expect(ring.width, lessThanOrEqualTo(64));

      // And still centred on the screen.
      final loader = tester.getRect(find.byType(BrandLoader));
      final screen = tester.getRect(find.byType(BrandLoaderScreen));
      expect(loader.center.dx, closeTo(screen.center.dx, 0.5));
    });

    testWidgets('the header mark is still left-aligned', (tester) async {
      // The default must not have moved: the loader asked for centring, the
      // header did not.
      _phone(tester);
      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: SizedBox(width: 300, child: BrandWordmark(height: 34)),
          ),
        ),
      );
      await tester.pump();

      final mark = tester.getRect(find.byType(SvgPicture));
      // Hard left in its 300pt box, not floating in the middle of it.
      expect(mark.left, 0);
      expect(
        tester.widget<BrandWordmark>(find.byType(BrandWordmark)).alignment,
        AlignmentDirectional.centerStart,
      );
    });
  });
}

/// The loader's own ring, not whatever CustomPaint a Scaffold happens to build.
Finder _ringOf(Type loader) => find
    .descendant(of: find.byType(loader), matching: find.byType(CustomPaint))
    .first;
