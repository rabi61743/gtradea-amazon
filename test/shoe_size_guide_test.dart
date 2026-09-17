import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/widgets/shoe_size_guide_sheet.dart';
import 'package:gtradea_amazon/features/product/widgets/size_guide_sheet.dart';
import 'package:gtradea_amazon/features/product/widgets/variant_picker.dart';

// The labels live 1688 shoe listings publish (Men's sports shoes).
const _realSizes = [
  '36',
  '37.5',
  '38',
  '39',
  '40',
  '41',
  '42',
  '43',
  '44',
  '45',
  '46',
  '47',
];

Future<void> _button(
  WidgetTester tester, {
  String? category,
  List<String> sizes = _realSizes,
  String? initialSize,
  Size screen = const Size(412, 900),
}) async {
  tester.view.physicalSize = screen * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizeGuideButton(
            category: category,
            sizes: sizes,
            initialSize: initialSize,
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('size-guide-button')));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

void main() {
  group('sizing rules', () {
    test('footwear is decided by the category', () {
      expect(ShoeSizing.isFootwear("Men's sports shoes"), isTrue);
      expect(ShoeSizing.isFootwear('Sneakers'), isTrue);
      expect(ShoeSizing.isFootwear("Women's boots"), isTrue);
      expect(ShoeSizing.isFootwear('Sandals and slippers'), isTrue);
      expect(ShoeSizing.isFootwear('运动鞋'), isTrue);
      // Trousers are sized in numbers too, and are not shoes.
      expect(ShoeSizing.isFootwear("Men's casual trousers"), isFalse);
      expect(ShoeSizing.isFootwear('T-shirt'), isFalse);
      expect(ShoeSizing.isFootwear(null), isFalse);
    });

    test('reads the EU size from a seller label', () {
      expect(ShoeSizing.euOf('36'), 36);
      expect(ShoeSizing.euOf('37.5'), 37.5);
      expect(ShoeSizing.euOf('36 (sneaker size)'), 36);
      expect(ShoeSizing.euOf('XL'), isNull);
      expect(ShoeSizing.euOf('28'), isNull, reason: 'outside the chart');
    });

    test('foot length follows the size = cm x 2 - 10 rule', () {
      expect(ShoeSizing.rowFor(36)!.footCm, 23);
      expect(ShoeSizing.rowFor(42)!.footCm, 26);
      expect(ShoeSizing.rowFor(37.5)!.footCm, 23.75);
    });

    test('a half size sits between its neighbours', () {
      final half = ShoeSizing.rowFor(37.5)!;
      expect(half.uk, 4.5);
      expect(half.usMen, 5.5);
    });
  });

  testWidgets('a shoe opens the shoe guide on its own sizes', (tester) async {
    await _button(tester, category: "Men's sports shoes", initialSize: '42');

    expect(find.byType(ShoeSizeGuideSheet), findsOneWidget);
    expect(find.byType(SizeGuideSheet), findsNothing);
    // Every size the product has, and nothing it does not.
    for (final s in _realSizes) {
      expect(find.byKey(ValueKey('shoe-size-$s')), findsOneWidget, reason: s);
    }
    expect(find.byKey(const ValueKey('shoe-size-35')), findsNothing);

    // Opened on the size already picked.
    expect(_text(tester, const ValueKey('shoe-guide-foot')), '26 cm');
    expect(find.byKey(const ValueKey('shoe-guide-notice')), findsOneWidget);
  });

  testWidgets('choosing a size and a unit updates the figures', (tester) async {
    await _button(tester, category: "Men's sports shoes");
    expect(_text(tester, const ValueKey('shoe-guide-foot')), '23 cm');

    await tester.tap(find.byKey(const ValueKey('shoe-size-40')));
    await tester.pumpAndSettle();
    expect(_text(tester, const ValueKey('shoe-guide-foot')), '25 cm');

    await tester.tap(find.byKey(const ValueKey('shoe-unit-in')));
    await tester.pumpAndSettle();
    expect(_text(tester, const ValueKey('shoe-guide-foot')), '9.8 in');
    expect(find.text('Foot length (in)'), findsOneWidget);
  });

  testWidgets('a colour on the label does not repeat sizes', (tester) async {
    await _button(
      tester,
      category: 'Sneakers',
      sizes: const ['Black / 36', 'White / 36', 'Black / 37', 'White / 37'],
      initialSize: 'White / 37',
    );
    expect(find.byKey(const ValueKey('shoe-size-36')), findsOneWidget);
    expect(find.byKey(const ValueKey('shoe-size-37')), findsOneWidget);
    expect(_text(tester, const ValueKey('shoe-guide-foot')), '23.5 cm');
  });

  testWidgets('sizes outside shoe numbering say so, instead of a chart', (
    tester,
  ) async {
    await _button(tester, category: 'Slippers', sizes: const ['S', 'M']);
    expect(find.byKey(const ValueKey('shoe-guide-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('shoe-size-table')), findsNothing);
  });

  testWidgets('clothing still opens the clothing guide', (tester) async {
    await _button(tester, category: 'T-shirt', sizes: const ['S', 'M', 'L']);
    expect(find.byType(SizeGuideSheet), findsOneWidget);
    expect(find.byType(ShoeSizeGuideSheet), findsNothing);
  });

  testWidgets('fits a phone and a tablet, and closes', (tester) async {
    for (final screen in const [Size(360, 740), Size(800, 1280)]) {
      await _button(tester, category: "Men's sports shoes", screen: screen);
      expect(tester.takeException(), isNull, reason: '$screen');
      await tester.tap(find.byKey(const ValueKey('size-guide-close')));
      await tester.pumpAndSettle();
      expect(find.byType(ShoeSizeGuideSheet), findsNothing);
    }
  });

  testWidgets('the product page picker passes the shoe category through', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: VariantPicker(
              label: 'Size',
              category: "Men's sports shoes",
              variants: const [
                ProductVariant(label: '40', imageUrl: ''),
                ProductVariant(label: '41', imageUrl: ''),
              ],
              selectedIndex: 1,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('size-guide-button')));
    await tester.pumpAndSettle();
    expect(find.byType(ShoeSizeGuideSheet), findsOneWidget);
    expect(_text(tester, const ValueKey('shoe-guide-foot')), '25.5 cm');
  });
}
