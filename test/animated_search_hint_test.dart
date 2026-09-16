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
    testWidgets('a lone phrase is shown whole, and stays put', (tester) async {
      await tester.pumpWidget(
        _wrap(const AnimatedSearchHint(style: TextStyle(), phrases: ['Lamp'])),
      );

      expect(_hint(tester), 'Search for Lamp');
    });

    testWidgets('turns one phrase over for the next, without a blank', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AnimatedSearchHint(
            style: TextStyle(),
            phrases: ['Lamp', 'Shoes'],
          ),
        ),
      );

      // Whole from the first frame: a ticker shows a word, it does not build
      // one letter at a time.
      expect(_hint(tester), 'Search for Lamp');

      // Held long enough to read before anything moves.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_hint(tester), 'Search for Lamp', reason: 'still being read');

      // Mid-turn both are on screen -- one leaving, one arriving -- which is
      // what makes it a ticker rather than a swap.
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 120));
      final turning = _hint(tester);
      expect(turning, contains('Shoes'));
      expect(turning, contains('Lamp'), reason: 'the old one is still leaving');

      // And afterwards only the new one.
      await tester.pump(const Duration(milliseconds: 600));
      expect(_hint(tester), 'Search for Shoes');

      await tester.pumpWidget(_wrap(const SizedBox()));
    });

    testWidgets('the arriving word rises into place as it fades in', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AnimatedSearchHint(
            style: TextStyle(),
            phrases: ['Lamp', 'Shoes'],
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 2300));
      await tester.pump(const Duration(milliseconds: 100));

      final arriving = find.text('Shoes');
      expect(arriving, findsOneWidget);
      final slide = tester.widget<SlideTransition>(
        find
            .ancestor(of: arriving, matching: find.byType(SlideTransition))
            .first,
      );
      // Still below its resting place, on its way up.
      expect(slide.position.value.dy, greaterThan(0));

      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(of: arriving, matching: find.byType(FadeTransition))
            .first,
      );
      expect(fade.opacity.value, lessThan(1), reason: 'and still fading in');

      await tester.pumpWidget(_wrap(const SizedBox()));
    });

    testWidgets('pausing holds the phrase it is on, and does not rewind', (
      tester,
    ) async {
      Widget hint({required bool paused}) => _wrap(
        AnimatedSearchHint(
          style: const TextStyle(),
          paused: paused,
          phrases: const ['Lamp', 'Shoes', 'Toys'],
        ),
      );

      await tester.pumpWidget(hint(paused: false));
      await tester.pump(const Duration(milliseconds: 2300));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_hint(tester), 'Search for Shoes');

      // Paused: the clock stops where it is.
      await tester.pumpWidget(hint(paused: true));
      await tester.pump(const Duration(seconds: 6));
      expect(_hint(tester), 'Search for Shoes', reason: 'nothing moved on');

      // Resumed: it carries on from there rather than starting the list again.
      await tester.pumpWidget(hint(paused: false));
      await tester.pump(const Duration(milliseconds: 2300));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_hint(tester), 'Search for Toys');

      await tester.pumpWidget(_wrap(const SizedBox()));
    });

    testWidgets('holds still when the reader asked for less motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AnimatedSearchHint(
            style: TextStyle(),
            phrases: ['Lamp', 'Shoes'],
          ),
          reducedMotion: true,
        ),
      );

      final first = _hint(tester);
      await tester.pump(const Duration(seconds: 3));

      expect(first, 'Search for Lamp');
      expect(_hint(tester), first, reason: 'nothing moved');
    });

    testWidgets('the cursor is drawn, and keeps its own time', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AnimatedSearchHint(
            style: TextStyle(fontSize: 15),
            phrases: ['Lamp', 'Shoes'],
          ),
        ),
      );

      // A bar after the word, not a typed "|" inside the text.
      expect(_hint(tester), isNot(contains('|')));
      final caret = find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == 1.5,
      );
      expect(caret, findsOneWidget);

      double opacity() => tester
          .widget<AnimatedOpacity>(find.byKey(const ValueKey('search-caret')))
          .opacity;

      final first = opacity();
      await tester.pump(const Duration(milliseconds: 650));
      expect(opacity(), isNot(closeTo(first, 0.05)), reason: 'it blinks');

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
