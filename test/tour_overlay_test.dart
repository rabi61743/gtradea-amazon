import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/tour/data/tour_step.dart';
import 'package:gtradea_amazon/features/tour/data/tour_store.dart';
import 'package:gtradea_amazon/features/tour/presentation/tour_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Walking the tour.
///
/// The overlay is given its steps and a way to say how it ended; what it must
/// get right is the walking -- which step is shown, what the buttons say at
/// each end, what the counter reads, and what happens to a step whose widget
/// is not on the screen at all.

/// A page with two of the anchors really on it and one deliberately absent,
/// so the "skip what is not there" rule has something to skip.
class _Host extends StatelessWidget {
  const _Host({required this.steps, required this.onFinished, this.showSecond = true});

  final List<TourStep> steps;
  final ValueChanged<TourOutcome> onFinished;

  /// False leaves [TourAnchor.categories] unbuilt.
  final bool showSecond;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                Container(
                  key: TourAnchors.instance.keyOf(TourAnchor.search),
                  height: 60,
                  color: Colors.blue,
                ),
                if (showSecond)
                  Container(
                    key: TourAnchors.instance.keyOf(TourAnchor.categories),
                    height: 60,
                    color: Colors.green,
                  ),
                const Spacer(),
              ],
            ),
            TourOverlay(steps: steps, onFinished: onFinished),
          ],
        ),
      ),
    );
  }
}

const _steps = [
  TourStep(title: 'Welcome', body: 'Hello', anchor: TourAnchor.none),
  TourStep(title: 'Search', body: 'Find things', anchor: TourAnchor.search),
  TourStep(title: 'Categories', body: 'Browse', anchor: TourAnchor.categories),
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TourStore.instance.resetForTest();
    TourAnchors.instance.clear();
    TourStore.enabled = true;
  });

  tearDown(() {
    TourStore.instance.resetForTest();
    TourAnchors.instance.clear();
    TourStore.enabled = false;
  });

  Future<TourOutcome?> pump(
    WidgetTester tester, {
    List<TourStep> steps = _steps,
    bool showSecond = true,
  }) async {
    TourOutcome? outcome;
    await tester.pumpWidget(
      _Host(
        steps: steps,
        showSecond: showSecond,
        onFinished: (o) => outcome = o,
      ),
    );
    await tester.pumpAndSettle();
    return outcome;
  }

  group('walking it', () {
    testWidgets('opens on the first step, counting from one', (tester) async {
      await pump(tester);

      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
      // Nothing to go back to on the first step.
      expect(find.text('Back'), findsNothing);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('Next walks forward and the counter follows', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Search'), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('Back returns to the step before', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
    });

    testWidgets('the last step offers Get Started rather than Next', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('3 of 3'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });
  });

  group('how it ends', () {
    testWidgets('Get Started finishes it as completed', (tester) async {
      TourOutcome? outcome;
      await tester.pumpWidget(
        _Host(steps: _steps, onFinished: (o) => outcome = o),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      expect(outcome, TourOutcome.completed);
    });

    testWidgets('Skip finishes it as skipped, from any step', (tester) async {
      TourOutcome? outcome;
      await tester.pumpWidget(
        _Host(steps: _steps, onFinished: (o) => outcome = o),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(outcome, TourOutcome.skipped, reason: 'skipped, not completed');
    });
  });

  group('a step with nothing to point at', () {
    testWidgets('is stepped over rather than shown against nothing', (
      tester,
    ) async {
      // The categories anchor is not built on this page at all -- the case of
      // an element that is missing on a particular screen or width.
      await pump(tester, showSecond: false);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Search'), findsOneWidget);
      // Two steps are showable, so the counter says so rather than promising
      // a third that cannot be drawn.
      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('and the tour still ends properly', (tester) async {
      TourOutcome? outcome;
      await tester.pumpWidget(
        _Host(
          steps: _steps,
          showSecond: false,
          onFinished: (o) => outcome = o,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      expect(outcome, TourOutcome.completed);
    });
  });

  group('the dim itself', () {
    testWidgets('covers the whole screen, not nothing', (tester) async {
      // The overlay's own scrim, which was absent for a long time without any
      // test noticing: every assertion here was about text, and the words are
      // drawn *on* the dim rather than by it. A CustomPaint with no child and
      // no explicit size collapses to zero under the loose constraints
      // AnimatedSwitcher's Stack hands out, so the storefront stayed at full
      // brightness with white type floating over it.
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await pump(tester);

      final painted = find.descendant(
        of: find.byType(TourOverlay),
        matching: find.byType(CustomPaint),
      );
      expect(painted, findsWidgets);

      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final covers = tester
          .widgetList<CustomPaint>(painted)
          .indexed
          .map((e) => tester.getSize(painted.at(e.$1)))
          .any((s) => s.width >= screen.width && s.height >= screen.height);
      expect(covers, isTrue, reason: 'something actually paints the scrim');
    });
  });

  group('what it lets through', () {
    testWidgets('the highlighted widget still answers a tap', (tester) async {
      // The spec's rule, and the bug that broke ten suites when the overlay
      // swallowed every pointer: the hole is the real control, and it has to
      // keep working.
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Stack(
              children: [
                Column(
                  children: [
                    GestureDetector(
                      key: TourAnchors.instance.keyOf(TourAnchor.search),
                      onTap: () => tapped++,
                      child: Container(height: 60, color: Colors.blue),
                    ),
                    const Spacer(),
                  ],
                ),
                TourOverlay(
                  steps: const [
                    TourStep(
                      title: 'Search',
                      body: 'Find things',
                      anchor: TourAnchor.search,
                    ),
                  ],
                  onFinished: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(200, 30));
      await tester.pumpAndSettle();

      expect(tapped, 1, reason: 'the spotlight is not a lid');
    });
  });
}
