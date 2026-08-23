import 'package:flutter/material.dart';

import '../data/product_detail_content.dart';

/// Colourway swatches with the selected one named above them.
///
/// The name is spelled out rather than left to the swatch alone: "Selected:
/// Blush pink" is checkable, a highlighted thumbnail is a guess. Sold-out
/// options stay in place, dimmed and struck, so a shopper can see the range
/// exists instead of hunting for a colour that was quietly removed.
class VariantPicker extends StatelessWidget {
  const VariantPicker({
    super.key,
    required this.variants,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<ProductVariant> variants;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = variants[selectedIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Colour: ',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Text(
              selected.label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
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
                            child: Image.network(
                              variant.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) =>
                                  ColoredBox(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          if (!variant.inStock)
                            Center(
                              child: Container(
                                color: theme.colorScheme.surface
                                    .withValues(alpha: 0.85),
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
              );
            },
          ),
        ),
      ],
    );
  }
}
