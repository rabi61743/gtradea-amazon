import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/shimmer.dart';
import '../../search/widgets/product_result_card.dart';

/// The Corporate Gifts page while the collection is in flight.
///
/// Laid out as the loaded page is, element for element, so nothing moves when
/// the products land: the search box, the heading, then the grid. The heading
/// is drawn for real because its words are known before any request is made --
/// what is being fetched is the products, and those get bones the size of the
/// cards that replace them.
class CorporateGiftsSkeleton extends StatelessWidget {
  const CorporateGiftsSkeleton({super.key});

  /// The search field's height, measured on the real one.
  static const _fieldHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: const [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: ShimmerBone(
              height: _fieldHeight,
              radius: AppTheme.radiusControl,
            ),
          ),
          SectionHeader(
            title: 'Corporate gifts',
            subtitle:
                'Gift sets and desk pieces, curated for business gifting.',
          ),
          // The grid's own margin, from ProductGrid.
          Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: ResultGridSkeleton(),
          ),
        ],
      ),
    );
  }
}
