import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/search/widgets/search_field.dart';
import 'package:gtradea_amazon/shared/widgets/animated_search_hint.dart';

Widget _wrap(Widget child, {bool reducedMotion = false}) => MaterialApp(
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Scaffold(body: child),
  ),
);

/// The text of the one hint on screen.
String _hint(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(AnimatedSearchHint),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data ?? '')
    .join();

void main() {
  group('the phrases', () {
    test('read as the end of "Search for", and none is too long to show', () {
      for (final phrase in kSearchHintPhrases) {
        expect(
          phrase.length,
          lessThanOrEqualTo(kSearchHintMaxLength),
          reason: '"$phrase" would end in an ellipsis in the home header',
        );
        expect(
          phrase,
          phrase.toLowerCase(),
          reason: 'mid-sentence, lower case',
        );
      }
      expect(kSearchHintPhrases.take(3), [
        'running shoes',
        'winter jackets',
        'gift ideas',
      ]);
    });
  });

  group('the animated placeholder', () {
    const two = AnimatedSearchHint(
      style: TextStyle(),
      phrases: ['lamp', 'shoes'],
    );

    /// The rendered vertical offset and opacity of [word], as drawn.
    ({double dy, double opacity}) drawn(WidgetTester tester, String word) {
      final text = find.text('Search for "$word"');
      final translate = tester.widget<Transform>(
        find.ancestor(of: text, matching: find.byType(Transform)).first,
      );
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: text, matching: find.byType(Opacity)).first,
      );
      return (
        dy: translate.transform.getTranslation().y,
        opacity: opacity.opacity,
      );
    }

    testWidgets('a lone phrase is shown whole, and stays put', (tester) async {
      await tester.pumpWidget(
        _wrap(const AnimatedSearchHint(style: TextStyle(), phrases: ['lamp'])),
      );

      expect(_hint(tester), 'Search for "lamp"');
    });

    testWidgets('the whole phrase moves as one, lead and quoted keyword', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AnimatedSearchHint(
            style: TextStyle(),
            phrases: ['running shoes', 'winter jackets', 'gift ideas'],
          ),
        ),
      );

      // Exactly the format asked for, quotes and all -- and no "Search for"
      // drawn on its own anywhere, which is what would stay still.
      expect(find.text('Search for "running shoes"'), findsOneWidget);
      expect(find.text('Search for '), findsNothing);
      expect(find.text('running shoes'), findsNothing);

      // Mid-turn, both whole phrases are moving: the lead goes up with its
      // keyword and comes in with the next one.
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pump(const Duration(milliseconds: 200));
      expect(drawn(tester, 'running shoes').dy, lessThan(0), reason: 'rising');
      expect(drawn(tester, 'winter jackets').dy, greaterThan(0));

      // And on through the list in order.
      await tester.pump(const Duration(milliseconds: 400));
      expect(_hint(tester), 'Search for "winter jackets"');
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_hint(tester), 'Search for "gift ideas"');

      await tester.pumpWidget(_wrap(const SizedBox()));
    });

    testWidgets('the cursor sits after the closing quote', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AnimatedSearchHint(
            style: TextStyle(fontSize: 15),
            phrases: ['gift ideas', 'toys'],
          ),
        ),
      );

      final phrase = tester.getRect(find.text('Search for "gift ideas"'));
      final caret = tester.getRect(find.byKey(const ValueKey('search-caret')));
      expect(caret.left, greaterThanOrEqualTo(phrase.right));
      expect(caret.left - phrase.right, lessThan(4), reason: 'right after it');

      await tester.pumpWidget(_wrap(const SizedBox()));
    });

    testWidgets('each phrase holds for 2.6 seconds before it turns', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(two));
      expect(_hint(tester), 'Search for "lamp"');

      await tester.pump(const Duration(milliseconds: 2550));
      expect(_hint(tester), 'Search for "lamp"', reason: 'still being read');
      expect(find.text('Search for "shoes"'), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Search for "shoes"'),
        findsOneWidget,
        reason: 'turning at 2.6 s',
      );

      await tester.pumpWidget(_wrap(const SizedBox()));
    });

    testWidgets('the outgoing phrase rises 16 and fades over 400 ms, ease-in', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(two));
      await tester.pump(const Duration(milliseconds: 2600));

      // Half-way through its 400 ms, on an ease-in: well under half-way.
      await tester.pump(const Duration(milliseconds: 200));
      final mid = drawn(tester, 'lamp');
      final eased = Curves.easeIn.transform(0.5);
      expect(mid.dy, closeTo(-16 * eased, 0.5));
      expect(mid.opacity, closeTo(1 - eased, 0.02));
      expect(-mid.dy, lessThan(8), reason: 'slow to start');

      // At 400 ms it has gone the whole way.
      await tester.pump(const Duration(milliseconds: 200));
      final end = drawn(tester, 'lamp');
      expect(end.dy, closeTo(-16, 0.5));
      expect(end.opacity, closeTo(0, 0.01));

      await tester.pumpWidget(_wrap(const SizedBox()));
    });

    testWidgets('the incoming one waits 50 ms, then rises 18 over 450 ms', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(two));
      await tester.pump(const Duration(milliseconds: 2600));

      // 40 ms in: the outgoing one has begun, the incoming one has not.
      await tester.pump(const Duration(milliseconds: 40));
      final waiting = drawn(tester, 'shoes');
      expect(waiting.dy, closeTo(18, 0.01), reason: 'still 18 below');
      expect(waiting.opacity, 0, reason: 'and not yet showing');
      expect(drawn(tester, 'lamp').opacity, lessThan(1), reason: 'overlap');

      // Half-way through its own 450 ms (50 + 225 = 275 ms in), on an
      // ease-out: well past half-way.
      await tester.pump(const Duration(milliseconds: 235));
      final mid = drawn(tester, 'shoes');
      final eased = Curves.easeOut.transform(0.5);
      expect(mid.dy, closeTo(18 * (1 - eased), 0.5));
      expect(mid.opacity, closeTo(eased, 0.02));
      expect(mid.dy, lessThan(9), reason: 'quick to start');

      // Settled at 500 ms.
      await tester.pump(const Duration(milliseconds: 230));
      expect(
        find.text('Search for "lamp"'),
        findsNothing,
        reason: 'the old one is gone',
      );
      final settled = drawn(tester, 'shoes');
      expect(settled.dy, 0);
      expect(settled.opacity, 1);

      await tester.pumpWidget(_wrap(const SizedBox()));
    });

    testWidgets('the width follows the phrase over 450 ms, eased both ways', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(two));
      final size = tester.widget<AnimatedSize>(find.byType(AnimatedSize));
      expect(size.duration, const Duration(milliseconds: 450));
      expect(size.curve, Curves.easeInOut);
    });

    testWidgets('pausing holds the phrase it is on, and does not rewind', (
      tester,
    ) async {
      Widget hint({required bool paused}) => _wrap(
        AnimatedSearchHint(
          style: const TextStyle(),
          paused: paused,
          phrases: const ['lamp', 'shoes', 'toys'],
        ),
      );

      await tester.pumpWidget(hint(paused: false));
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_hint(tester), 'Search for "shoes"');

      // Paused: the clock stops where it is.
      await tester.pumpWidget(hint(paused: true));
      await tester.pump(const Duration(seconds: 6));
      expect(_hint(tester), 'Search for "shoes"', reason: 'nothing moved on');

      // Resumed: it carries on from there rather than starting the list again.
      await tester.pumpWidget(hint(paused: false));
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_hint(tester), 'Search for "toys"');

      await tester.pumpWidget(_wrap(const SizedBox()));
    });

    testWidgets('holds still when the reader asked for less motion', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(two, reducedMotion: true));

      final first = _hint(tester);
      await tester.pump(const Duration(seconds: 4));

      expect(first, 'Search for "lamp"');
      expect(_hint(tester), first, reason: 'nothing moved');
    });

    testWidgets('the cursor fades full to nothing and back, 550 ms a half', (
      tester,
    ) async {
      // Off for the rest of the suite so pages can settle; on for this one.
      AnimatedSearchHint.blinkEnabled = true;
      addTearDown(() => AnimatedSearchHint.blinkEnabled = false);

      await tester.pumpWidget(
        _wrap(
          const AnimatedSearchHint(
            style: TextStyle(fontSize: 15),
            phrases: ['lamp', 'shoes'],
          ),
        ),
      );

      // A bar after the word, not a typed "|" inside the text.
      expect(_hint(tester), isNot(contains('|')));

      double opacity() => tester
          .widget<FadeTransition>(find.byKey(const ValueKey('search-caret')))
          .opacity
          .value;

      // One half down: from full to nothing over 550 ms, eased.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 275));
      expect(opacity(), closeTo(0.5, 0.05), reason: 'eased, symmetric');
      await tester.pump(const Duration(milliseconds: 275));
      expect(opacity(), closeTo(0, 0.02), reason: 'gone at 550 ms');

      // And back up over the next 550 ms.
      await tester.pump(const Duration(milliseconds: 550));
      expect(opacity(), closeTo(1, 0.02), reason: 'full again at 1.1 s');

      await tester.pumpWidget(_wrap(const SizedBox()));
    });
  });

  group('the search field', () {
    testWidgets('shows the animated placeholder while it is empty', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(SearchField(controller: controller), reducedMotion: true),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AnimatedSearchHint), findsOneWidget);
    });

    testWidgets('the placeholder goes the moment something is typed', (
      tester,
    ) async {
      // The whole point: no placeholder competing with what is being typed.
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(SearchField(controller: controller), reducedMotion: true),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'geyser');
      await tester.pumpAndSettle();

      expect(find.byType(AnimatedSearchHint), findsNothing);
      expect(find.text('geyser'), findsOneWidget);
    });

    testWidgets('and comes back when the box is emptied again', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(SearchField(controller: controller), reducedMotion: true),
      );
      await tester.enterText(find.byType(TextField), 'geyser');
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSearchHint), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      expect(find.byType(AnimatedSearchHint), findsOneWidget);
    });

    testWidgets('focusing the empty box fades the hint and stops it', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_wrap(SearchField(controller: controller)));
      await tester.pump();

      expect(
        tester
            .widget<AnimatedSearchHint>(find.byType(AnimatedSearchHint))
            .paused,
        isFalse,
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      final hint = tester.widget<AnimatedSearchHint>(
        find.byType(AnimatedSearchHint),
      );
      expect(hint.paused, isTrue, reason: 'the run holds');
      expect(
        tester
            .widget<AnimatedOpacity>(
              find
                  .ancestor(
                    of: find.byType(AnimatedSearchHint),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .opacity,
        0,
        reason: 'and it is faded out',
      );

      await tester.pumpWidget(_wrap(const SizedBox()));
    });

    testWidgets('the clear button appears with the text, and takes it back', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final typed = <String>[];

      await tester.pumpWidget(
        _wrap(
          SearchField(controller: controller, onChanged: typed.add),
          reducedMotion: true,
        ),
      );
      await tester.pumpAndSettle();

      final clear = find.byKey(const ValueKey('search-clear'));
      expect(clear, findsNothing, reason: 'nothing to clear yet');

      await tester.enterText(find.byType(TextField), 'geyser');
      await tester.pumpAndSettle();
      expect(clear, findsOneWidget);

      await tester.tap(clear);
      await tester.pumpAndSettle();

      expect(controller.text, isEmpty);
      expect(clear, findsNothing, reason: 'and it goes with the text');
      expect(typed.last, '', reason: 'suggestions hear about it too');
      // Emptied, the placeholder is back.
      expect(find.byType(AnimatedSearchHint), findsOneWidget);
    });

    testWidgets('typing still reaches the field own callbacks', (tester) async {
      // The placeholder sits behind the field and must not swallow anything.
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final typed = <String>[];
      final submitted = <String>[];

      await tester.pumpWidget(
        _wrap(
          SearchField(
            controller: controller,
            onChanged: typed.add,
            onSubmitted: submitted.add,
          ),
          reducedMotion: true,
        ),
      );

      await tester.enterText(find.byType(TextField), 'lamp');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(typed, ['lamp'], reason: 'typeahead still fires');
      expect(submitted, ['lamp'], reason: 'and so does the search itself');
    });
  });
}
