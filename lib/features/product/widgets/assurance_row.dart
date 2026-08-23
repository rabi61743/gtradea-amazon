import 'package:flutter/material.dart';

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

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor),
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            for (final assurance in assurances)
              Expanded(
                child: InkWell(
                  onTap: () => _explain(context, assurance),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          assurance.icon,
                          size: 24,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          assurance.label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
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
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
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
