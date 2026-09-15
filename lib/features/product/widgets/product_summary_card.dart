import 'package:flutter/material.dart';

import '../../home/widgets/product_rail.dart' show formatRupees;
import 'product_type_scale.dart';

/// What is about to be bought, in one line.
///
/// The picture, the name, the price and the count -- all four read from the
/// page's own state rather than from a copy of it, so it cannot show a variant
/// the shopper is not looking at or a quantity they did not set. It makes no
/// decisions: the page works out which variant is selected and what it costs,
/// and this draws the answer.
///
/// Frameless on purpose. It sits inside the product card, under the rule below
/// the quantity stepper -- a card of its own there would be a card inside a
/// card, which is a box nobody asked for.
class ProductSummaryCard extends StatelessWidget {
  const ProductSummaryCard({
    super.key,
    required this.title,
    required this.unitPrice,
    required this.quantity,
    this.imageUrl,
    this.variantLabel,
    this.unitLabel = 'pcs',
    this.priceKnown = true,
  });

  /// The chosen colourway's own photograph where it has one, so two variants
  /// of a product are told apart at a glance rather than by a text label.
  final String? imageUrl;

  final String title;

  /// The option this price and picture belong to, when the listing has any.
  final String? variantLabel;

  /// What one piece costs at the quantity currently chosen -- tiered pricing
  /// included, since the page has already worked that out.
  final num unitPrice;

  final int quantity;
  final String unitLabel;

  /// False for a listing the catalogue has no price for, and for a grid with
  /// nothing typed into it yet. Rs. 0 would read as free rather than as
  /// unknown, which is what it actually is.
  final bool priceKnown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 58,
            height: 58,
            child: imageUrl == null
                ? Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ProductType.attributeValue(theme),
              ),
              if (variantLabel case final variant? when variant.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(variant, style: ProductType.attributeLabel(theme)),
              ],
              const SizedBox(height: 5),
              // The count, and what one of them costs. Wrapped rather than
              // rowed: a six-figure wholesale price beside a four-digit
              // quantity is wider than half a phone.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(
                    'Qty: $quantity $unitLabel',
                    style: ProductType.minOrder(theme),
                  ),
                  if (priceKnown)
                    Text(
                      '${formatRupees(unitPrice)} each',
                      style: ProductType.minOrder(theme),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // What the line comes to, which is the figure the buy bar is about to
        // charge.
        Text(
          priceKnown ? formatRupees(unitPrice * quantity) : '—',
          style: ProductType.attributeValue(theme)
              .copyWith(color: theme.colorScheme.primary),
        ),
      ],
    );
  }
}
