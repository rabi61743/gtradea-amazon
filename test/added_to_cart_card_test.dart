import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/theme/colors.dart';
import 'package:gtradea_amazon/core/ui/action_status.dart';

void main() {
  /// A page with one button that raises the card, as a real screen does.
  Future<int> pump(
    WidgetTester tester, {
    required String title,
    String? variant,
    int inCart = 2,
    Size size = const Size(1220, 2712),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => ActionStatus.addedToCart(
                  context,
                  title: title,
                  variant: variant,
                  inCart: inCart,
                  onViewCart: () => opened++,
                ),
                child: const Text('add'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
    return opened;
  }

  group('what the card says', () {
    testWidgets('the event, the product and how many are in the cart', (
      tester,
    ) async {
      await pump(tester, title: 'Egg storage box', inCart: 2);

      expect(find.textContaining('Added to Cart'), findsOneWidget);
      expect(find.text('Egg storage box'), findsOneWidget);
      expect(find.text('2 in cart'), findsOneWidget);
    });

    testWidgets('and names the variant when there is one', (tester) async {
      // A listing sold in twenty-one colourways needs its variant named, or
      // the confirmation does not say what went in.
      await pump(tester, title: 'Egg storage box', variant: 'brown / 30 eggs');

      expect(find.textContaining('brown / 30 eggs'), findsOneWidget);
    });

    testWidgets('the count is the one it was given, not a guess', (
      tester,
    ) async {
      await pump(tester, title: 'Egg storage box', inCart: 7);

      expect(find.text('7 in cart'), findsOneWidget);
    });

    testWidgets('it carries the tick and the cart mark', (tester) async {
      await pump(tester, title: 'Egg storage box');

      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.shopping_cart_outlined), findsNWidgets(2));
    });
  });

  group('the actions work', () {
    testWidgets('View cart opens the cart', (tester) async {
      var opened = 0;
      tester.view.physicalSize = const Size(1220, 2712);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => ActionStatus.addedToCart(
                    context,
                    title: 'Egg storage box',
                    inCart: 1,
                    onViewCart: () => opened++,
                  ),
                  child: const Text('add'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('add'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View cart'));
      await tester.pumpAndSettle();

      expect(opened, 1);
    });

    testWidgets('and closing it dismisses without opening anything', (
      tester,
    ) async {
      final opened = await pump(tester, title: 'Egg storage box');

      await tester.tap(find.byType(IconButton).last);
      await tester.pumpAndSettle();

      expect(find.text('View cart'), findsNothing);
      expect(opened, 0);
    });
  });

  group('it fits', () {
    testWidgets('a long variant name does not overflow', (tester) async {
      // It did: a Row of two Texts overflowed by 166px, because the label
      // could not shrink to make room for the variant.
      await pump(
        tester,
        title: 'Egg storage box',
        variant: 'brown [can hold 30 eggs / with timer / food grade] extra',
        size: const Size(1080, 2400),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('and neither does a long product title', (tester) async {
      await pump(
        tester,
        title:
            'Source Factory Wholesale Customized Christmas Gift Bag Display '
            'Rack Christmas Tree Decoration Pendant Small Gift Paper Shelf',
        size: const Size(1080, 2400),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('the colours are the brand own', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
    }

    testWidgets('Trust Blue card, Commerce Orange accents, white ink', (
      tester,
    ) async {
      await pump(tester, title: 'Egg storage box');

      // The card itself: the brand blue, not the page and not a grey bar.
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.backgroundColor, AppColors.trustBlue);

      // The tick and the button in the accent.
      final tick = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.check),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (tick.decoration as BoxDecoration).color,
        AppColors.commerceOrange,
      );
      final button = tester.widget<Material>(
        find
            .ancestor(
              of: find.text('View cart'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(button.color, AppColors.commerceOrange);

      // And the words read on the blue.
      final title = tester.widget<Text>(find.text('Egg storage box'));
      expect(title.style!.color, Colors.white);
      expect(
        contrast(Colors.white, AppColors.trustBlue),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('it is compact', () {
    testWidgets('three short lines, not a panel', (tester) async {
      await pump(
        tester,
        title:
            'Power Saver Household Black Technology Power Saver Smart '
            'Energy Saving Box',
        size: const Size(1080, 2400),
      );
      final height = tester.getSize(find.byType(SnackBar)).height;
      // Measured in this harness, whose test font sets every glyph a full em
      // wide: 185 before the card was tightened, 144 after. The ceiling sits
      // between them, so the padding cannot creep back unnoticed.
      expect(height, lessThan(160), reason: 'the card is $height tall');
      expect(tester.takeException(), isNull);
    });

    testWidgets('and still fits a narrow phone', (tester) async {
      await pump(
        tester,
        title: 'Egg storage box',
        variant: 'brown, 30 eggs',
        // 320dp: the narrowest phone in common use.
        size: const Size(960, 2000),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
