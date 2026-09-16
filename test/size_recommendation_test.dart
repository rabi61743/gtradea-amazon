import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/product/widgets/size_guide_sheet.dart';
import 'package:gtradea_amazon/features/product/widgets/size_recommendation.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _openRecommendation(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412, 900) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: Center(child: SizeGuideButton())),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('size-guide-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('size-tab-1')));
  await tester.pumpAndSettle();
}

String _valueBox(WidgetTester tester, String name) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey('measure-$name-value')),
        matching: find.byType(Text),
      ),
    )
    .data!;

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('size-recommendation-submit')));
  await tester.pumpAndSettle();
}

/// Drags a ruler by [ticks] -- positive to raise the value.
Future<void> _swipe(WidgetTester tester, String name, int ticks) async {
  await tester.drag(
    find.byKey(ValueKey('ruler-$name')),
    // Plus the touch slop the gesture spends before the list starts moving.
    Offset(-(ticks * RulerPicker.tickGap + ticks.sign * 18), 0),
  );
  await tester.pumpAndSettle();
}

String _suggested(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('size-recommendation-size')))
    .textSpan!
    .toPlainText();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the suggestion', () {
    test('a measurement inside a size range is that size', () {
      expect(fitFor(96, (s) => s.chest).size.label, 'M');
      expect(fitFor(100, (s) => s.chest).size.label, 'L');
      expect(fitFor(105, (s) => s.chest).size.label, 'L');
    });

    test('between two sizes, the larger', () {
      // M is 94-99, L is 100-105: 99.5 is neither, and L will fit.
      expect(fitFor(99.5, (s) => s.chest).size.label, 'L');
    });

    test('off either end is the end, and says so', () {
      final small = fitFor(70, (s) => s.chest);
      expect(small.size.label, 'XS');
      expect(small.below, isTrue);
      final big = fitFor(140, (s) => s.chest);
      expect(big.size.label, '3XL');
      expect(big.above, isTrue);
    });

    test('when bust and waist disagree, the larger is suggested', () {
      final r = SizeRecommendation.forMeasurements(
        const BodyMeasurements(bust: 104, waist: 95),
      );
      expect(r.bust.size.label, 'L');
      expect(r.waist.size.label, 'XL');
      expect(r.size.label, 'XL');
    });
  });

  testWidgets('the tab matches the reference, and says where data is kept', (
    tester,
  ) async {
    await _openRecommendation(tester);

    expect(find.text('Swipe to add your body information'), findsOneWidget);
    expect(find.textContaining('on this device'), findsWidgets);
    expect(find.text('Bust size'), findsOneWidget);
    expect(find.text('Waist size'), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
    expect(_valueBox(tester, 'bust'), '96 cm');
    expect(_valueBox(tester, 'waist'), '82 cm');
    // No suggestion until something has been submitted.
    expect(
      find.byKey(const ValueKey('size-recommendation-result')),
      findsNothing,
    );
  });

  testWidgets('swiping a ruler changes the measurement', (tester) async {
    await _openRecommendation(tester);

    await _swipe(tester, 'bust', 8);
    expect(_valueBox(tester, 'bust'), '104 cm');

    await _swipe(tester, 'waist', -4);
    expect(_valueBox(tester, 'waist'), '78 cm');
  });

  testWidgets('submitting suggests a standard size, and explains it', (
    tester,
  ) async {
    await _openRecommendation(tester);
    await _swipe(tester, 'bust', 8); // 104: L
    await _swipe(tester, 'waist', 13); // 95: XL
    await _submit(tester);

    expect(_suggested(tester), 'Your standard size: XL');
    expect(find.textContaining('fits L'), findsOneWidget);
    expect(find.textContaining('fits XL'), findsOneWidget);
    expect(find.textContaining('The larger is suggested'), findsOneWidget);
    expect(find.textContaining("not this product's"), findsOneWidget);
  });

  testWidgets('Submit shows it worked, even when the size is the same', (
    tester,
  ) async {
    await _openRecommendation(tester);
    await _submit(tester);
    expect(_suggested(tester), 'Your standard size: M');
    expect(find.text('Saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
    expect(find.text('Submit'), findsOneWidget);

    // Moving a ruler: the old answer is marked out of date, not left as if
    // it were current.
    // Submit scrolled the answer up; bring the bust ruler back first.
    await tester.ensureVisible(
      find.byKey(const ValueKey('measure-bust-value')),
    );
    await tester.pumpAndSettle();
    await _swipe(tester, 'bust', 1);
    expect(_valueBox(tester, 'bust'), '97 cm');
    expect(
      find.byKey(const ValueKey('size-recommendation-stale')),
      findsOneWidget,
    );

    // The same size again (97 is still M) -- and it still says Saved.
    await _submit(tester);
    expect(_suggested(tester), 'Your standard size: M');
    expect(
      find.byKey(const ValueKey('size-recommendation-stale')),
      findsNothing,
    );
    expect(find.text('Saved'), findsOneWidget);
    expect((await BodyMeasurementsStore.instance.load())!.bust, 97);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('saves on the device, and shows it again next time', (
    tester,
  ) async {
    await _openRecommendation(tester);
    await _swipe(tester, 'bust', 8);
    await _submit(tester);

    final saved = await BodyMeasurementsStore.instance.load();
    expect(saved!.bust, 104);

    // Closed and opened again: the same measurements, and the suggestion.
    await tester.tap(find.byKey(const ValueKey('size-guide-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('size-guide-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('size-tab-1')));
    await tester.pumpAndSettle();

    expect(_valueBox(tester, 'bust'), '104 cm');
    expect(_suggested(tester), 'Your standard size: L');
  });

  testWidgets('inches show the same measurement in inches', (tester) async {
    await _openRecommendation(tester);

    await tester.tap(find.byKey(const ValueKey('rec-unit-inches')));
    await tester.pumpAndSettle();
    expect(_valueBox(tester, 'bust'), '37.8 in');

    await tester.tap(find.byKey(const ValueKey('rec-unit-cm')));
    await tester.pumpAndSettle();
    expect(_valueBox(tester, 'bust'), '96 cm');
  });

  testWidgets('"see it in the size guide" opens the guide on that size', (
    tester,
  ) async {
    await _openRecommendation(tester);
    await _swipe(tester, 'bust', 16); // 112: XXL
    await _swipe(tester, 'waist', 16); // 98: XXL
    await _submit(tester);
    expect(_suggested(tester), 'Your standard size: XXL');

    // Submit brings the answer into view, clear of the Submit bar.
    await tester.tap(find.byKey(const ValueKey('size-recommendation-view')));
    await tester.pumpAndSettle();

    // On the guide tab, with XXL's figures.
    expect(find.text('Switch to'), findsOneWidget);
    final chest = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('body-chest')),
        matching: find.byType(Text),
      ),
    );
    expect(chest.data, '112-117');
  });

  testWidgets('fits a phone and a tablet without overflowing', (tester) async {
    for (final size in const [Size(360, 740), Size(800, 1280)]) {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: Center(child: SizeGuideButton())),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('size-guide-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('size-tab-1')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      await tester.tap(find.byKey(const ValueKey('size-guide-close')));
      await tester.pumpAndSettle();
    }
    tester.view.reset();
  });
}
