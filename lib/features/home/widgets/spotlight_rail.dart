import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/artwork_panel.dart';
import '../../../shared/widgets/section_header.dart';

class SpotlightItem {
  const SpotlightItem({
    required this.offer,
    required this.caption,
    required this.icon,
    required this.tint,
  });

  /// The banner line, e.g. "Min. 65% off". A marketing band, not a price.
  final String offer;

  /// The line under the card, e.g. "Brand days".
  final String caption;

  final IconData icon;
  final Color tint;
}

/// Horizontal row of promoted cards, each with an offer ribbon across the
/// bottom of its artwork and a caption underneath.
///
/// No "AD" badge: the reference marks these as paid placements, and labelling
/// our own placeholder content as advertising would be a false disclosure.
/// Add the badge here if and when real paid slots exist.
class SpotlightRail extends StatelessWidget {
  const SpotlightRail({
    super.key,
    required this.title,
    required this.items,
    this.leadingIcon,
    this.onSeeAll,
  });

  final String title;
  final IconData? leadingIcon;
  final List<SpotlightItem> items;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          leadingIcon: leadingIcon,
          onSeeAll: onSeeAll,
        ),
        SizedBox(
          height: 172 *
              MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _SpotlightCard(item: items[i]),
          ),
        ),
      ],
    );
  }
}

class _SpotlightCard extends StatelessWidget {
  const _SpotlightCard({required this.item});

  final SpotlightItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ArtworkPanel(icon: item.icon, tint: item.tint),
                  // The ribbon sits inside the artwork so the offer travels
                  // with the image rather than competing with the caption.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: AppColors.accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: Text(
                        item.offer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.onAccent,
                          fontSize: 11,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
