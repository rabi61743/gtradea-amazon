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
String _hint(WidgetTester tester) {
  final widget = tester.widget<Text>(
    find.descendant(
      of: find.byType(AnimatedSearchHint),
      matching: find.byType(Text),
    ),
  );
  return widget.textSpan!.toPlainText();
}

void main() {
  group('the animated placeholder', () {
    testWidgets('types a phrase out one letter at a time', (tester) async {
      await tester.pumpWidget(
        _wrap(const AnimatedSearchHint(style: TextStyle(), phrases: ['Lamp'])),
      );

      // A single phrase does not cycle, so it is shown whole and still.
      expect(_hint(tester), 'Search Lamp');
    });

    testWidgets('moves through the phrases, erasing between them', (
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

      // Nothing typed yet beyond the fixed lead.
      expect(_hint(tester), startsWith('Search '));

      // Part-way through the first phrase.
      await tester.pump(const Duration(milliseconds: 130));
      final partial = _hint(tester);
      expect(partial, startsWith('Search L'));
      expect(
        partial.contains('Lamp'),
        isFalse,
        reason: 'it is still being typed',
      );

      // Finished, and held long enough to read.
      await tester.pump(const Duration(milliseconds: 300));
      expect(_hint(tester), startsWith('Search Lamp'));

      // Erased, and on to the next one.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_hint(tester), startsWith('Search S'));

      // Left in a settled state, or the pending timer fails the test.
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

      expect(first, 'Search Lamp');
      expect(_hint(tester), first, reason: 'nothing moved');
    });

    testWidgets('the caret is only there while it is moving', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AnimatedSearchHint(
            style: TextStyle(),
            phrases: ['Lamp', 'Shoes'],
          ),
          reducedMotion: true,
        ),
      );
      expect(_hint(tester), isNot(contains('|')));
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
