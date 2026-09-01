import 'package:flutter/material.dart';

import '../../flash_sale/data/flash_sale.dart';
import '../../flash_sale/presentation/flash_deal_card.dart';

/// Deal cards, in as many columns as the window can hold.
///
/// Shared by the home page's flash sale block and the deals screen. They show
/// the same cards, so they measure them the same way -- two grids with their
/// own column maths drift apart the first time either is touched.
class DealGrid extends StatelessWidget {
  const DealGrid({
    super.key,
    required this.items,
    this.onOpen,
    this.onAddToCart,
  });

  final List<FlashSaleItem> items;
  final void Function(FlashSaleItem item)? onOpen;
  final void Function(FlashSaleItem item)? onAddToCart;

  /// Roughly the width a deal card wants. Columns are derived from it rather
  /// than from named device breakpoints, so a split-screen tablet and a small
  /// desktop window both get the layout that actually fits.
  static const targetWidth = 200.0;
  static const gap = 12.0;

  /// How many columns a given width gets. Exposed so a caller sizing its own
  /// rows can ask the same question and get the same answer.
  static int columnsFor(double width) =>
      (width / targetWidth).floor().clamp(2, 5);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: FlashDealCard(
                  item: item,
                  onTap: onOpen == null ? null : () => onOpen!(item),
                  onAddToCart: onAddToCart == null
                      ? null
                      : () => onAddToCart!(item),
                ),
              ),
          ],
        );
      },
    );
  }
}
