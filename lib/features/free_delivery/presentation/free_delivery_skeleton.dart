import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/shimmer.dart';
import '../../search/widgets/product_result_card.dart';

/// The Free Delivery page while the collection is in flight.
///
/// Laid out as the loaded page is, element for element, so nothing moves when
/// the products land: the search box, the heading, then the grid.
///
/// **The heading is drawn for real, not as bones.** Its words are the page's
/// own -- "Delivered free" and what it means -- and they are known before any
/// request is made. Drawing them as grey bars would be pretending not to know
/// something. What is actually being fetched is the products, and those get
/// placeholders the size of the real cards.
///
/// The search box is a bone because it cannot search yet: the collection it
/// searches is what is still arriving.
class FreeDeliverySkeleton extends StatelessWidget {
  const FreeDeliverySkeleton({super.key});

  /// The search field's height, measured on the real one. A bone that is not
  /// this tall would move the whole page down when the field replaces it.
  static const _fieldHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        // It stands in for a page that scrolls, but there is nothing here to
        // scroll to yet.
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          // The search box's own padding, from the page it stands in for.
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: ShimmerBone(
              height: _fieldHeight,
              radius: AppTheme.radiusControl,
            ),
          ),
          const SectionHeader(
            title: 'Delivered free',
            subtitle: 'Every one of these ships at no delivery charge.',
          ),
          // The grid's own margin, from ProductGrid.
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: ResultGridSkeleton(),
          ),
        ],
      ),
    );
  }
}
