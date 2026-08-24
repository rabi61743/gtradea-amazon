import 'package:flutter/material.dart';

import '../data/product_detail_content.dart';

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
              ': ',
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
