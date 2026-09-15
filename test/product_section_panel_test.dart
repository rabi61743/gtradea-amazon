import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/product/data/product_repository.dart';
import 'package:gtradea_amazon/features/product/data/storefront_config.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';

import 'support/api.dart';
import 'support/catalog.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProductDetailScreen(product: sampleProduct, detail: sampleDetail),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// How many places name a spec value.
///
/// The Highlights card is built from the same specs, so one match means the
/// panel is shut and two mean it is open -- which is what makes this an
/// honest test of the panel rather than of the page.
int _mentions(String value) => find.text(value).evaluate().length;

IconData _icon(WidgetTester tester, String section) {
  final open = find.byIcon(Icons.keyboard_arrow_up);
  final shut = find.byIcon(Icons.keyboard_arrow_down);
  // Which one sits on this section's row.
  final row = tester.getRect(find.text(section));
  for (final finder in [open, shut]) {
    for (final element in finder.evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      if ((rect.center.dy - row.center.dy).abs() < 20) {
        return (element.widget as Icon).icon!;
      }
    }
  }
  fail('no open/close control on $section');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    stubCatalog();
    CartStore.instance.resetForTest();
    StorefrontConfigRepository.instance.resetForTest();
    ProductRepository.instance.clearDetailCache();
  });

  tearDown(clearApiStub);

  group('the panels that open and close', () {
    testWidgets('start closed, and say so', (tester) async {
      await _pump(tester);
      await tester.ensureVisible(find.text('Specifications'));
      await tester.pumpAndSettle();

      expect(_icon(tester, 'Specifications'), Icons.keyboard_arrow_down);
      // Closed: the table is not drawn, so the value appears once -- in the
      // Highlights card above.
      expect(_mentions('Phosphorus paper'), 1);
    });

    testWidgets('are cards, like every other section on the page', (
      tester,
    ) async {
      await _pump(tester);
      await tester.ensureVisible(find.text('Specifications'));
      await tester.pumpAndSettle();

      // The frame around the heading: white, hairline, 16pt corner -- the
      // same one Highlights and Description are drawn in.
      final card = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Specifications'),
              matching: find.byType(Container),
            )
            .last,
      );
      final box = card.decoration! as BoxDecoration;
      expect(box.color, AppTheme.light.colorScheme.surface);
      expect(box.border, isNotNull);
      expect(
        box.borderRadius,
        BorderRadius.circular(16),
        reason: 'the corner the page cuts every card to',
      );
    });

    testWidgets('open on a tap, and the control turns over', (tester) async {
      await _pump(tester);
      await tester.ensureVisible(find.text('Specifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Specifications'));
      await tester.pumpAndSettle();

      expect(_icon(tester, 'Specifications'), Icons.keyboard_arrow_up);
      expect(_mentions('Phosphorus paper'), 2, reason: 'the table is open');
    });

    testWidgets('and close again on a second tap', (tester) async {
      await _pump(tester);
      await tester.ensureVisible(find.text('Specifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Specifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Specifications'));
      await tester.pumpAndSettle();

      expect(_icon(tester, 'Specifications'), Icons.keyboard_arrow_down);
      expect(_mentions('Phosphorus paper'), 1, reason: 'shut again');
    });

    testWidgets('each panel opens on its own', (tester) async {
      // Two panels sharing a storage slot would open together, which is the
      // bug the per-panel key exists to stop.
      await _pump(tester);
      await tester.ensureVisible(find.text('Specifications'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Specifications'));
      await tester.pumpAndSettle();

      expect(_icon(tester, 'Specifications'), Icons.keyboard_arrow_up);
      // One panel open means one up-arrow on the page: any other panel that
      // opened with it would put a second one there.
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    });

    testWidgets('and the control is announced for a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);
      await tester.ensureVisible(find.text('Specifications'));
      await tester.pumpAndSettle();

      // Matched loosely: the tile merges its row into one node, so the
      // control's words arrive alongside the heading's.
      expect(
        find.bySemanticsLabel(RegExp('Open Specifications')),
        findsWidgets,
      );

      await tester.tap(find.text('Specifications'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp('Close Specifications')),
        findsWidgets,
      );
      semantics.dispose();
    });
  });

  testWidgets('every card down the page is 97% of it, centred', (tester) async {
    await _pump(tester);

    final page = tester.getSize(find.byType(ProductDetailScreen)).width;

    // Highlights, Description, Specifications and Detail images share it.
    final factors = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .map((box) => box.widthFactor)
        .toSet();
    expect(factors, {0.97});

    for (final title in const [
      'Highlights',
      'Description',
      'Specifications',
      'Detail images',
    ]) {
      // The list is lazy; measure the cards it has actually built.
      if (find.text(title).evaluate().isEmpty) continue;
      final card = tester.getRect(
        find
            .ancestor(
              of: find.text(title),
              matching: find.byType(FractionallySizedBox),
            )
            .first,
      );
      expect(card.width, closeTo(page * 0.97, 0.5), reason: title);
      expect(card.left, closeTo(page - card.right, 0.5), reason: title);
    }
  });
}
