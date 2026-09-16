import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/widgets/size_guide_sheet.dart';
import 'package:gtradea_amazon/features/product/widgets/variant_picker.dart';

/// A page with the button on it, at a given screen size.
Future<void> _page(
  WidgetTester tester, {
  Size size = const Size(400, 860),
  String? initialSize,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(child: SizeGuideButton(initialSize: initialSize)),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('size-guide-button')));
  await tester.pumpAndSettle();
}

Finder _pill(String key) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text));

/// The sheet's own vertical scroll -- not the table's sideways one inside it.
Finder get _pageScroll => find
    .descendant(
      of: find.byType(SizeGuideSheet),
      matching: find.byType(Scrollable),
    )
    .first;

String _pillText(WidgetTester tester, String key) =>
    tester.widget<Text>(_pill(key)).data!;

void main() {
  testWidgets('opens as a sheet, and closes', (tester) async {
    await _page(tester);
    await _open(tester);

    expect(find.byType(SizeGuideSheet), findsOneWidget);
    expect(find.text('Size guide'), findsWidgets);
    expect(find.text('Switch to'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('size-guide-close')));
    await tester.pumpAndSettle();
    expect(find.byType(SizeGuideSheet), findsNothing);
  });

  testWidgets('says plainly that these are standard, not the product own', (
    tester,
  ) async {
    await _page(tester);
    await _open(tester);

    expect(find.textContaining('General guide'), findsOneWidget);
    expect(find.textContaining("seller's sizes may differ"), findsOneWidget);
    expect(find.textContaining('Standard size'), findsOneWidget);
  });

  testWidgets('opens on the size already chosen, from a seller label', (
    tester,
  ) async {
    // Seller labels carry notes; the first word is the size.
    expect(SizeGuideSheet.indexFor('L [50.00 kg-57.50 kg]]'), 3);
    expect(SizeGuideSheet.indexFor('XL recommendation 57-65kg'), 4);
    expect(SizeGuideSheet.indexFor('XXXL'), 6);
    expect(SizeGuideSheet.indexFor('Wine red'), 2, reason: 'M when unknown');
    expect(SizeGuideSheet.indexFor(null), 2);

    await _page(tester, initialSize: 'L [50.00 kg-57.50 kg]]');
    await _open(tester);
    // L's body chest range, on the figure.
    expect(_pillText(tester, 'body-chest'), '100-105');
  });

  testWidgets('choosing a size updates the figures', (tester) async {
    await _page(tester);
    await _open(tester);
    expect(_pillText(tester, 'garment-chest'), '104', reason: 'M');

    await tester.tap(find.byKey(const ValueKey('guide-size-XL')));
    await tester.pumpAndSettle();
    expect(_pillText(tester, 'garment-chest'), '116');
    expect(_pillText(tester, 'body-waist'), '92-97');
  });

  testWidgets('switches centimetres and inches', (tester) async {
    await _page(tester);
    await _open(tester);
    expect(_pillText(tester, 'garment-length'), '70');

    await tester.tap(find.byKey(const ValueKey('unit-inches')));
    await tester.pumpAndSettle();
    expect(_pillText(tester, 'garment-length'), '27.6');
    expect(_pillText(tester, 'body-chest'), '37.0-39.0', reason: 'ranges too');

    // And the table's headings say which unit they are in.
    await tester.scrollUntilVisible(
      find.text('Chest (in)'),
      300,
      scrollable: _pageScroll,
    );
    expect(find.text('Chest (in)'), findsOneWidget);

    // Back up to the switch, which the table scrolled away.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('unit-cm')),
      -300,
      scrollable: _pageScroll,
    );
    await tester.tap(find.byKey(const ValueKey('unit-cm')));
    await tester.pumpAndSettle();
    expect(_pillText(tester, 'garment-length'), '70');
  });

  testWidgets('the body and product charts each list every size', (
    tester,
  ) async {
    await _page(tester);
    await _open(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('size-table-product')),
      300,
      scrollable: _pageScroll,
    );
    expect(find.text('Sleeve (cm)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chart-body')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('size-table-body')), findsOneWidget);
    expect(find.text('Hips (cm)'), findsOneWidget);
    for (final s in kStandardSizes) {
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('size-table-body')),
          matching: find.text(s.label),
        ),
        findsOneWidget,
        reason: s.label,
      );
    }
  });

  testWidgets('the measurement pills never overlap or leave the sheet', (
    tester,
  ) async {
    // On the phone the height pill ran into the sleeve pill and the length
    // pill sat on the edge. Checked at every size, since XL figures are wider.
    const keys = [
      'body-chest',
      'body-waist',
      'body-height',
      'garment-shoulder',
      'garment-chest',
      'garment-length',
      'garment-sleeve',
    ];
    for (final screen in const [
      Size(360, 800),
      Size(412, 900),
      Size(800, 1280),
    ]) {
      await _page(tester, size: screen);
      await _open(tester);
      for (final label in ['XS', 'M', '3XL']) {
        await tester.tap(find.byKey(ValueKey('guide-size-$label')));
        await tester.pumpAndSettle();

        final sheet = tester.getRect(find.byType(SizeGuideSheet));
        final rects = [
          for (final k in keys) tester.getRect(find.byKey(ValueKey(k))),
        ];
        for (var i = 0; i < rects.length; i++) {
          expect(
            sheet.contains(rects[i].topLeft) &&
                sheet.contains(rects[i].bottomRight),
            isTrue,
            reason: '${keys[i]} inside the sheet at $screen, $label',
          );
          for (var j = i + 1; j < rects.length; j++) {
            expect(
              rects[i].overlaps(rects[j]),
              isFalse,
              reason: '${keys[i]} and ${keys[j]} at $screen, $label',
            );
          }
        }
      }
      await tester.tap(find.byKey(const ValueKey('size-guide-close')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('fits a phone, a tablet and a desktop without overflowing', (
    tester,
  ) async {
    for (final size in const [
      Size(360, 740),
      Size(800, 1280),
      Size(1400, 900),
    ]) {
      await _page(tester, size: size);
      await _open(tester);
      expect(tester.takeException(), isNull, reason: '$size');
      // Phone width on anything larger.
      expect(
        tester.getSize(find.byType(SizeGuideSheet)).width,
        lessThanOrEqualTo(640),
      );
      await tester.tap(find.byKey(const ValueKey('size-guide-close')));
      await tester.pumpAndSettle();
    }
  });

  group('on the product page picker', () {
    const sizes = [
      ProductVariant(label: 'S', imageUrl: ''),
      ProductVariant(label: 'M', imageUrl: ''),
      ProductVariant(label: 'L', imageUrl: ''),
    ];

    Future<void> picker(WidgetTester tester, String label) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: VariantPicker(
                label: label,
                variants: sizes,
                selectedIndex: 2,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a size axis offers the guide, on the chosen size', (
      tester,
    ) async {
      await picker(tester, 'Size');
      expect(find.byKey(const ValueKey('size-guide-button')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('size-guide-button')));
      await tester.pumpAndSettle();
      expect(_pillText(tester, 'body-chest'), '100-105', reason: 'L');
    });

    testWidgets('a colour axis does not', (tester) async {
      await picker(tester, 'Color');
      expect(find.byKey(const ValueKey('size-guide-button')), findsNothing);
    });

    testWidgets('opening it does not change the selection', (tester) async {
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: VariantPicker(
              label: 'Size',
              variants: sizes,
              selectedIndex: 1,
              onSelected: (_) => changes++,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('size-guide-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-size-XL')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('size-guide-close')));
      await tester.pumpAndSettle();

      expect(changes, 0, reason: 'the guide is information only');
    });
  });
}
