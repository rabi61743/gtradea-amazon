import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/page_width.dart';

/// The space the Flash Sale card will take, held while the answer is in flight.
///
/// **Why this exists.** The sale is deliberately not cached to disk -- a
/// deadline painted from yesterday's copy would count down to a time that has
/// already passed -- so on a cold open the slot is empty until the request
/// lands. It sits between the hero and the promotional banners, and rendering
/// nothing while it waits meant the card dropped in later and shoved every
/// banner below it down the page. Measured on the device: the banners sat
/// directly under the hero with no network, and about 140pt lower once the sale
/// arrived. That is the "banners pushed below the screen" this was reported as.
///
/// **Why only while loading.** Most of the time there is no sale at all, and
/// reserving this space permanently would leave a hole on every ordinary open.
/// The reserve is held for the length of one request and released the moment
/// the server says there is nothing to show, so the page settles once, early,
/// rather than jumping seconds later.
///
/// Deliberately quiet: a wash the height of the card, not a mimicry of it. A
/// skeleton with a fake heading and a fake clock on it would be advertising a
/// sale that may not exist.
class FlashSaleCardSkeleton extends StatelessWidget {
  const FlashSaleCardSkeleton({super.key});

  /// The card's own height, which this stands in for.
  ///
  /// A constant rather than a measurement because there is nothing to measure
  /// yet -- the card's height comes from the type on it, and the type comes
  /// from a sale that has not arrived. Pinned against the real card by a test
  /// so the two cannot drift apart; the existing card tests already hold it
  /// under 150 at every phone width.
  /// Measured against the card rather than derived from its parts.
  ///
  /// This plus the shared `insets(top: 6)` is what the reserved block occupies,
  /// and that total is what has to equal the card's. It was 126 while the card
  /// carried more padding; tightening the card left it over-reserving, so the
  /// page settled *upward* when a sale landed instead of not moving at all.
  ///
  /// [flash_sale_reserve_test] is the pin: it measures the rendered skeleton
  /// against the rendered card, so neither can drift behind the other.
  static const height = 114.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      // The same measure the card uses, so the reserved block and the card
      // that replaces it occupy exactly the same box. Followed it from 14 to 6.
      padding: PageWidth.insets(context, top: 6),
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.45,
            ),
            // The card's own radius, which it follows: 22, then 16, now the
            // theme's plain 12. A skeleton that kept the old corners would snap
            // into different ones the moment the sale landed.
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
        ),
      ),
    );
  }
}
