import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../home/widgets/product_rail.dart' show formatRupees;
import '../data/search_models.dart';

/// One search result: image on the left, the facts a shopper compares on to
/// the right.
///
/// Landscape rather than the home feed's grid tiles, because comparing needs
/// specs and savings side by side and a two-up grid has no room for them.
class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.result, this.onTap});

  final SearchResult result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final discount = result.discountPercent;
    final list = result.listPrice;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104,
                height: 104,
                child: ArtworkPanel(
                  icon: result.icon,
                  tint: result.tint,
                  imageUrl: result.imageUrl,
                  iconScale: 0.4,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Paid placement is disclosed, quietly but present.
                    if (result.sponsored)
                      Text(
                        'Sponsored',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      result.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(height: 1.25, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    _Rating(
                      rating: result.rating,
                      count: result.reviewCount,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          formatRupees(result.price),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        if (list != null && discount != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              formatRupees(list),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                decoration: TextDecoration.lineThrough,
                                decorationColor:
                                    theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '-$discount%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (result.freeDelivery) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Free delivery',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (result.specs.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final spec in result.specs)
                            _SpecChip(label: spec),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stars and the review count.
///
/// Absent entirely when nothing has been rated: five empty stars beside a zero
/// reads as a product everybody disliked, not as one nobody has rated yet.
class _Rating extends StatelessWidget {
  const _Rating({required this.rating, required this.count});

  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (count <= 0) return const SizedBox.shrink();

    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star
                : (rating >= i - 0.5 ? Icons.star_half : Icons.star_border),
            size: 14,
            color: AppColors.star,
          ),
        const SizedBox(width: 6),
        Text(
          '($count)',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// A factual attribute, styled flat so it does not compete with the price or
/// read as a tappable filter.
class _SpecChip extends StatelessWidget {
  const _SpecChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
