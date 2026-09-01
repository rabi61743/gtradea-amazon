import 'package:flutter/material.dart';

import '../../../core/images/app_images.dart';

import '../data/product_detail_content.dart';
import 'variant_tooltip.dart';

/// Colourway swatches with the selected one named above them.
///
/// The name is spelled out rather than left to the swatch alone: "Selected:
/// White / S" is checkable, a highlighted thumbnail is a guess. Sold-out
/// options stay in place, dimmed and struck, so a shopper can see the range
/// exists instead of hunting for a colour that was quietly removed.
class VariantPicker extends StatelessWidget {
  const VariantPicker({
    super.key,
    this.label = 'Option',
    required this.variants,
    required this.selectedIndex,
    required this.onSelected,
  });

  /// What these options are called: Colour, Size, or several axes at once.
  /// Named by the listing, so a size is never labelled a colour.
  final String label;

  final List<ProductVariant> variants;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Plenty of listings sell one thing in one form, and the page shows a
    // preview with no options at all while the full record loads. A picker
    // with nothing to pick renders nothing rather than indexing an empty list.
    if (variants.isEmpty) return const SizedBox.shrink();

    // Clamped rather than trusted: the selection is held by the page across a
    // reload, and the new record can have fewer options than the old one.
    final selected = variants[selectedIndex.clamp(0, variants.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              // The field's own name, which was missing -- the row read as a
              // bare ": Red" with nothing saying what was being chosen.
              '$label: ',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            // Flexible, because these labels are seller-written and some of
            // them are sentences. An unconstrained one overflowed the row by
            // 228px on a phone, striping the page yellow and black.
            Flexible(
              child: Text(
                selected.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: variants.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final variant = variants[i];
              final isSelected = i == selectedIndex;

              return Semantics(
                label: variant.inStock
                    ? variant.label
                    : '${variant.label}, out of stock',
                selected: isSelected,
                child: VariantTooltip(
                  // The seller's own name for this colourway, off the SKU's
                  // property values. Without it a swatch says what it looks
                  // like and nothing else: the name was only ever shown for
                  // the option already selected, so telling two similar
                  // colourways apart meant selecting each in turn to read the
                  // line above. Hovering, or holding on a phone, now names the
                  // one under the pointer.
                  //
                  message: variant.inStock
                      ? variant.label
                      : '${variant.label} - sold out',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: variant.inStock ? () => onSelected(i) : null,
                    child: Container(
                      width: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Opacity(
                              opacity: variant.inStock ? 1 : 0.35,
                              // A 64pt swatch. This had no size bound at all, so
                              // every colour chip downloaded and decoded a
                              // full-resolution product photograph -- a dozen of
                              // them on a page where none is bigger than a
                              // thumbnail.
                              child: Image(
                                image: AppImages.of(
                                  variant.imageUrl,
                                  width: 64,
                                  devicePixelRatio:
                                      MediaQuery.devicePixelRatioOf(context),
                                ),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stack) =>
                                    ColoredBox(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest,
                                    ),
                              ),
                            ),
                            if (!variant.inStock)
                              Center(
                                child: Container(
                                  color: theme.colorScheme.surface.withValues(
                                    alpha: 0.85,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    'Sold out',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
