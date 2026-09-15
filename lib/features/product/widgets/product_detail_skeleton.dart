import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/shimmer.dart';

/// The product page while its record is in flight.
///
/// Drawn instead of the catalogue row the page was opened from. That row is
/// enough for a title and a price, but not for the gallery, the options, the
/// facts or the seller's photographs -- so a page built from it renders half
/// empty and then rearranges itself as the record lands. Bones the shape of
/// what is coming keep the page still, and mean nothing on screen is ever a
/// leftover from the product looked at before this one.
class ProductDetailSkeleton extends StatelessWidget {
  const ProductDetailSkeleton({super.key});

  /// The gallery's own aspect, so the picture lands where the bone was.
  static const _galleryRatio = 1.05;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const ShimmerPanel(aspectRatio: _galleryRatio, radius: 0),
          const SizedBox(height: 12),
          // The thumbnail strip under the gallery.
          SizedBox(
            height: 62,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, _) => const ShimmerBone(
                width: 62,
                height: 62,
                radius: AppTheme.radiusControl,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title: three lines, which is what the page caps it at.
                ShimmerBone(height: 15, radius: 4),
                SizedBox(height: 7),
                ShimmerBone(height: 15, radius: 4),
                SizedBox(height: 7),
                ShimmerBone(width: 220, height: 15, radius: 4),
                SizedBox(height: 12),
                // Sold and supplier.
                ShimmerBone(width: 180, height: 11, radius: 4),
                SizedBox(height: 14),
                // The price, with the minimum-order pill beside it.
                Row(
                  children: [
                    ShimmerBone(width: 140, height: 26, radius: 6),
                    Spacer(),
                    ShimmerBone(width: 118, height: 28, radius: 999),
                  ],
                ),
                SizedBox(height: 20),
                // The quantity stepper.
                Row(
                  children: [
                    ShimmerBone(width: 62, height: 14, radius: 4),
                    SizedBox(width: 12),
                    ShimmerBone(
                      width: 132,
                      height: 44,
                      radius: AppTheme.radiusControl,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // The logistics block, then the guarantees under it.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: ShimmerBone(height: 78, radius: 16),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: ShimmerBone(height: 52, radius: 16),
          ),
          const SizedBox(height: 16),
          // Highlights, then Description: the two cards that follow.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: ShimmerBone(height: 168, radius: 16),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: ShimmerBone(height: 110, radius: 16),
          ),
        ],
      ),
    );
  }
}
