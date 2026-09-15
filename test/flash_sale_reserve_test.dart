import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/flash_sale/data/flash_sale.dart';
import 'package:gtradea_amazon/features/flash_sale/presentation/flash_sale_card.dart';
import 'package:gtradea_amazon/features/flash_sale/presentation/flash_sale_card_skeleton.dart';

/// The reserve exists to stop the page jumping when the sale lands late, and it
/// only works if the space it holds is the space the card then takes.

FlashSale _sale(DateTime endsAt) => FlashSale(
  id: 'sale',
  headline: 'Dashain Specials',
  subhead: 'Unbeatable deals. Limited stock. Hurry up!',
  endsAt: endsAt,
  items: [
    FlashSaleItem(
      product: const Product(numIid: 'a', title: 'A', displayPrice: 100),
      salePrice: 60,
      listPrice: 100,
      discountPercent: 40,
    ),
  ],
);

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Builder(
    builder: (context) => Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  final now = DateTime(2026, 9, 12, 12);

  Future<double> heightOf(WidgetTester tester, Widget child, double width) async {
    tester.view.physicalSize = Size(width * 3, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(child));
    await tester.pump();
    return tester.getSize(find.byWidget(child)).height;
  }

  testWidgets('the reserved slot is the size of the card it stands in for', (
    tester,
  ) async {
    // The whole point of the reserve. If these drift apart, the page still
    // jumps -- by the difference -- and the fix quietly stops working.
    for (final width in [360.0, 412.0]) {
      final card = await heightOf(
        tester,
        FlashSaleCard(
          sale: _sale(now.add(const Duration(hours: 2))),
          onTap: () {},
          now: () => now,
        ),
        width,
      );
      final reserved = await heightOf(
        tester,
        const FlashSaleCardSkeleton(),
        width,
      );

      expect(
        reserved,
        closeTo(card, 10),
        reason: 'the slot and the card are the same block at ${width}dp',
      );
    }
  });

  testWidgets('and it is quiet: no heading, no clock, no claim of a sale', (
    tester,
  ) async {
    // A skeleton that mimicked the card would advertise a sale before anything
    // knows there is one.
    await tester.pumpWidget(_wrap(const FlashSaleCardSkeleton()));
    await tester.pump();

    expect(find.text('Flash Sales'), findsNothing);
    expect(find.byIcon(Icons.bolt), findsNothing);
    expect(find.text('Shop now'), findsNothing);
    expect(find.textContaining('Days'), findsNothing);
  });
}
