import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/product_detail_content.dart';

/// Returns, payment and quality guarantees, side by side under the buy area.
///
/// Each opens a sheet spelling the promise out. The reference renders these as
/// icon + label + chevron; a guarantee a shopper cannot actually read is
/// decoration, and the terms are exactly what they want before paying.
class AssuranceRow extends StatelessWidget {
  const AssuranceRow({super.key, required this.assurances});

  final List<Assurance> assurances;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (assurances.isEmpty) return const SizedBox.shrink();

    // A card with the three ruled apart, as the design has it: the icon at
    // the left of each, the promise under its name. Still one tap each to the
    // terms -- the sheet is where the guarantee is actually written down.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final assurance in assurances) ...[
                if (assurance != assurances.first)
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                Expanded(
                  child: InkWell(
                    onTap: () => _explain(context, assurance),
                    child: Padding(
                      // Even on all four sides, so the three cells are the
                      // same shape whatever their words do.
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 14,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            assurance.icon,
                            size: 24,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 8),
                          // Centred under its own mark and centred in its own
                          // third of the row. "Cash on delivery" needs two
                          // lines on a narrow phone; the cells stretch to the
                          // tallest, so all three still end level.
                          Text(
                            assurance.label,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _explain(BuildContext context, Assurance assurance) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(assurance.icon, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      assurance.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  assurance.detail,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
