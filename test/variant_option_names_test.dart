import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/widgets/variant_picker.dart';
import 'package:gtradea_amazon/features/product/widgets/variant_tooltip.dart';

/// Two colourways whose names are the seller's own, off the SKU properties.
List<ProductVariant> _variants() => const [
  ProductVariant(
    label: 'Pearl white',
    imageUrl: 'https://cdn.invalid/white.jpg',
    skuId: 'sku-white',
    axisValues: ['Pearl white'],
  ),
  ProductVariant(
    label: 'Wine red',
    imageUrl: 'https://cdn.invalid/red.jpg',
    skuId: 'sku-red',
    axisValues: ['Wine red'],
  ),
  ProductVariant(
    label: 'Crab shell red',
    imageUrl: 'https://cdn.invalid/crab.jpg',
    skuId: 'sku-crab',
    axisValues: ['Crab shell red'],
    inStock: false,
  ),
];

/// Rests a mouse pointer on [finder], which is the only thing that raises
/// these tooltips now.
Future<TestGesture> hover(WidgetTester tester, Finder finder) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await tester.pump();
  await mouse.moveTo(tester.getCenter(finder));
  await tester.pumpAndSettle();
  return mouse;
}

void main() {
  Future<int?> pump(
    WidgetTester tester, {
    int selected = 0,
    void Function(int)? onSelected,
  }) async {
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: VariantPicker(
            label: 'Colour',
            variants: _variants(),
            selectedIndex: selected,
            onSelected: (i) {
              picked = i;
              onSelected?.call(i);
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return picked;
  }

  group('naming the option under the pointer', () {
    testWidgets('every swatch carries the seller own name', (tester) async {
      await pump(tester);

      final tooltips = tester
          .widgetList<Tooltip>(
            find.descendant(
              of: find.byType(VariantPicker),
              matching: find.byType(Tooltip),
            ),
          )
          .map((t) => t.message)
          .toList();

      expect(tooltips, contains('Pearl white'));
      expect(tooltips, contains('Wine red'));
    });

    testWidgets('the name is on every swatch, not just the selected one', (
      tester,
    ) async {
      // The line above the row already names the selection. The point of this
      // is the options the shopper has *not* chosen.
      await pump(tester, selected: 0);

      final messages = tester
          .widgetList<Tooltip>(
            find.descendant(
              of: find.byType(VariantPicker),
              matching: find.byType(Tooltip),
            ),
          )
          .map((t) => t.message);

      expect(
        messages.where((m) => m == 'Wine red'),
        isNotEmpty,
        reason: 'an unselected colourway is named too',
      );
    });

    testWidgets('a sold-out option says so in its name', (tester) async {
      await pump(tester);

      final messages = tester
          .widgetList<Tooltip>(
            find.descendant(
              of: find.byType(VariantPicker),
              matching: find.byType(Tooltip),
            ),
          )
          .map((t) => t.message);

      expect(messages, contains('Crab shell red - sold out'));
    });

    testWidgets('hovering a swatch shows its name', (tester) async {
      await pump(tester);

      await hover(tester, find.byType(InkWell).at(1));

      // Once for the swatch it is on, and not for the others.
      expect(find.text('Wine red'), findsOneWidget);
    });
  });

  group('how it looks, against the reference', () {
    testWidgets('the bubble sits above the option, not under the thumb', (
      tester,
    ) async {
      await pump(tester);

      final tip = tester.widget<Tooltip>(
        find
            .descendant(
              of: find.byType(VariantTooltip),
              matching: find.byType(Tooltip),
            )
            .first,
      );

      expect(tip.preferBelow, isFalse);
      expect(tip.verticalOffset, greaterThan(0));
    });

    testWidgets('it is opaque, rounded and padded, not the bare default', (
      tester,
    ) async {
      // A name read over a product photograph has to be readable; Flutter's
      // default is a translucent grey with a 4pt radius.
      await pump(tester);

      final tip = tester.widget<Tooltip>(
        find
            .descendant(
              of: find.byType(VariantTooltip),
              matching: find.byType(Tooltip),
            )
            .first,
      );

      final decoration = tip.decoration! as BoxDecoration;
      expect(decoration.color!.a, 1.0, reason: 'opaque');
      expect(
        (decoration.borderRadius! as BorderRadius).topLeft.x,
        greaterThanOrEqualTo(12),
      );
      expect(decoration.boxShadow, isNotEmpty);
      expect(tip.textStyle?.color, Colors.white);
    });

    testWidgets('hover names it at once, and a tap does too', (tester) async {
      await pump(tester);

      final tip = tester.widget<Tooltip>(
        find
            .descendant(
              of: find.byType(VariantTooltip),
              matching: find.byType(Tooltip),
            )
            .first,
      );

      expect(
        tip.waitDuration,
        Duration.zero,
        reason: 'it names the option as the pointer arrives, not a beat later',
      );
      expect(
        tip.triggerMode,
        TooltipTriggerMode.tap,
        reason: 'a tap raises it on touch, where hover cannot happen',
      );
    });

    testWidgets('moving to another option names that one instead', (
      tester,
    ) async {
      // Selected on the third, so neither name below is the one the heading
      // above the row is already showing.
      await pump(tester, selected: 2);

      final mouse = await hover(tester, find.byType(InkWell).at(1));
      expect(find.text('Wine red'), findsOneWidget);
      expect(find.text('Pearl white'), findsNothing);

      await mouse.moveTo(tester.getCenter(find.byType(InkWell).at(0)));
      await tester.pumpAndSettle();
      expect(find.text('Pearl white'), findsOneWidget);
      expect(
        find.text('Wine red'),
        findsNothing,
        reason: 'the old name is gone, not stacked under the new one',
      );
    });

    testWidgets('a long press raises nothing', (tester) async {
      await pump(tester, selected: 2);

      await tester.longPress(find.byType(InkWell).at(1));
      await tester.pumpAndSettle();

      expect(find.text('Wine red'), findsNothing);
    });
  });

  group('what must not change', () {
    testWidgets('a tap still selects -- the tooltip does not eat it', (
      tester,
    ) async {
      final taps = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: VariantPicker(
              label: 'Colour',
              variants: _variants(),
              selectedIndex: 0,
              onSelected: taps.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(InkWell).at(1));
      await tester.pump();

      expect(taps, [1]);
    });

    testWidgets('a sold-out swatch is still unselectable', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: VariantPicker(
              label: 'Colour',
              variants: _variants(),
              selectedIndex: 0,
              onSelected: taps.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(InkWell).at(2), warnIfMissed: false);
      await tester.pump();

      expect(taps, isEmpty);
    });

    testWidgets('the selected name still reads above the row', (tester) async {
      await pump(tester, selected: 1);

      expect(find.text('Colour: '), findsOneWidget);
      expect(
        find.text('Wine red'),
        findsOneWidget,
        reason: 'the heading still names the selection',
      );
    });

    testWidgets('the swatches keep their size and count', (tester) async {
      await pump(tester);

      expect(find.byType(InkWell), findsNWidgets(3));
      // Measured, not read off the widget: a Tooltip that laid out wrong
      // would still carry the right constraints on the Container inside it.
      expect(tester.getSize(find.byType(InkWell).first).width, 64);
    });
  });
}
