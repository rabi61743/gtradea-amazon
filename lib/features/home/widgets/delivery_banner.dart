import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/section_header.dart';

/// The delivery promise, as a promotional band above the recommendations.
///
/// Built to a supplied design -- a pale panel, a headline and a sub-line on the
/// left, a filled pill, and a delivery scooter on the right -- in the app's own
/// palette rather than the reference's: a wash of Trust Blue over the page, the
/// brand blue on the headline and the button, and the section rhythm every
/// other block on this page uses.
///
/// **The words are not the reference's, and that is deliberate.** It read "Free
/// Delivery -- on orders above Rs. 1,999". Nothing in this app or its backend
/// does that:
///
///   * `freeDelivery` is never parsed from any response -- it defaults to false
///     and nothing sets it, so no line ever qualifies;
///   * the one remaining path is a promo carrying `free_shipping`, and
///     `/promo-codes/active` returns an empty list.
///
/// It then said "Rs. 100 flat delivery", which was true of the app but not of
/// the shop: that figure was a constant in this codebase, while the server
/// prices freight on the weight and volume of the order and its destination --
/// two shirts to Lalitpur by air quote at Rs. 551. Now that the cart asks the
/// server, a flat figure here would be contradicted one screen later.
///
/// So it names no number at all. What it promises is that the charge is quoted
/// before payment, which is what `POST /checkout/delivery-charge` makes true.
class DeliveryBanner extends StatelessWidget {
  const DeliveryBanner({super.key, this.onShop});

  /// Where the button goes. Null draws no button rather than a dead one.
  final VoidCallback? onShop;

  /// Past this the panel stops growing and centres, as the hero banner does. A
  /// promotional band three feet wide is not more persuasive, only emptier.
  static const maxWidth = 720.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SectionHeader.edge,
        SectionHeader.gapAbove,
        SectionHeader.edge,
        0,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: Material(
            // A wash of the brand blue over the page rather than a colour of
            // its own: the reference's pale blue, said in this app's palette.
            color: Color.alphaBlend(
              AppColors.trustBlue.withValues(alpha: 0.09),
              theme.colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusCard + 6),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onShop,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                child: Row(
                  children: [
                    Expanded(child: _Copy(onShop: onShop)),
                    const SizedBox(width: 8),
                    // Material's own delivery scooter -- the same subject as the
                    // reference's render, drawn from the icon font rather than
                    // an image this app does not have and would not own.
                    Icon(
                      Icons.delivery_dining,
                      size: 84,
                      color: AppColors.trustBlue.withValues(alpha: 0.85),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Copy extends StatelessWidget {
  const _Copy({this.onShop});

  final VoidCallback? onShop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          // No figure. This used to read "Rs. 100 flat delivery" against a
          // hardcoded constant; the server prices freight on the weight and
          // volume of the order and where it is going, so there is no one
          // number that is true of every basket -- and quoting one on the home
          // page that the cart then contradicts is worse than quoting none.
          'Delivery quoted before you pay',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: AppColors.trustBlue,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Priced on weight and where it is going, shown in your cart.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.3,
          ),
        ),
        if (onShop != null) ...[
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onShop,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.trustBlue,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const StadiumBorder(),
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Shop now'),
          ),
        ],
      ],
    );
  }
}
