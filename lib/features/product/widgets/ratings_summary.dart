import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../data/product_detail_content.dart';

/// Rating average, the distribution behind it, and a few reviews.
///
/// The distribution bars are the point. A 4.3 built from steady fours is a
/// different product from a 4.3 built of fives and ones, and the reference
/// shows only the average and a total -- which cannot tell those apart.
class RatingsSummary extends StatelessWidget {
  const RatingsSummary({
    super.key,
    required this.summary,
    required this.reviews,
  });

  final RatingSummary summary;
  final List<ProductReview> reviews;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxCount = summary.distribution.isEmpty
        ? 1
        : summary.distribution.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      summary.average.toStringAsFixed(1),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.star,
                      size: 20,
                      color: AppColors.successInk,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  summary.verdict,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.successInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${summary.total} ratings',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                children: [
                  for (var i = 0; i < summary.distribution.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _DistributionBar(
                        stars: 5 - i,
                        count: summary.distribution[i],
                        maxCount: maxCount,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 15,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${summary.verifiedCount} from confirmed purchases',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final review in reviews) _ReviewTile(review: review),
      ],
    );
  }
}

class _DistributionBar extends StatelessWidget {
  const _DistributionBar({
    required this.stars,
    required this.count,
    required this.maxCount,
  });

  final int stars;
  final int count;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        SizedBox(
          width: 12,
          child: Text(
            '$stars',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Icon(Icons.star, size: 11, color: AppColors.star),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: maxCount == 0 ? 0 : count / maxCount,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.successInk,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 28,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final ProductReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.successInk,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      review.rating.toStringAsFixed(0),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.star, size: 10, color: Colors.white),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Flexible: the name is the only part of this row that can
              // give, and a long one plus the unverified tag overflows a
              // narrow phone by ~60px.
              Flexible(
                child: Text(
                  review.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Unverified reviews are marked rather than dropped: hiding them
              // would flatter the average.
              if (!review.verified) ...[
                const SizedBox(width: 6),
                Text(
                  'unverified',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                review.when,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            review.body,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}
