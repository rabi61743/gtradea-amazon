import 'package:flutter/material.dart';

/// Section heading with an optional leading icon and a trailing "See All".
///
/// Deliberately the gtradea-flutter idiom -- a modest title with the action on
/// the same row -- rather than a heavy headline with a link underneath. It
/// keeps the two GtradeA apps recognisably siblings, and the action stays where
/// a reader is already looking instead of after the whole block.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.titleColor,
    this.onSeeAll,
    this.actionLabel = 'See All',
    this.margin,
    this.topGap,
    this.bottomGap,
  });

  /// The inset this heading sits on, when it is not the page's default.
  ///
  /// Null keeps [edge], which is what every caller outside the home feed's
  /// category sections uses and what the rest of this app lines up on.
  ///
  /// The home feed passes the shared 97% measure instead -- see [PageWidth] --
  /// because a heading inset sixteen points over cards inset five is a section
  /// that does not line up with itself. Passed rather than changed here: this
  /// widget draws the headings for the rails, the cart, the category screen and
  /// two skeletons as well, and none of those asked to move.
  final double? margin;

  /// The room above and below the heading, when it is not the page's default.
  ///
  /// Null keeps [gapAbove] and [gapBelow], which is what every caller outside
  /// the home feed's category sections uses.
  final double? topGap;
  final double? bottomGap;

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final Color? titleColor;
  final VoidCallback? onSeeAll;
  final String actionLabel;

  /// The page's vertical rhythm, named here because this is the widget that
  /// sets it.
  ///
  /// Blocks that draw their own heading -- the sale panel -- space themselves
  /// by these rather than by numbers of their own, which is how the gap between
  /// sections came to vary between 4 and 20 points down one page.
  static const gapAbove = 12.0;
  static const gapBelow = 8.0;

  /// The same rhythm, tightened, for a page of stacked category sections.
  ///
  /// Thirteen of them run down the home feed one after another, and at the
  /// full rhythm each boundary costs sixty-six points of which only thirty are
  /// spacing -- the other thirty-six are the action's minimum tap target,
  /// which is not something to trade away. These take eight of those thirty
  /// back, per boundary, without the headings closing up on the cards above
  /// them.
  static const denseGapAbove = 10.0;
  static const denseGapBelow = 6.0;

  /// The page margin. The heading sits on it like everything else.
  static const edge = 16.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = leadingIcon;

    return Padding(
      // The same margin on both sides. It used to be 8 on the right to absorb
      // the button's own padding, which put "See All" half a step past the
      // margin every other block lines up on.
      padding: EdgeInsets.fromLTRB(
        margin ?? edge,
        topGap ?? gapAbove,
        margin ?? edge,
        bottomGap ?? gapBelow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 18,
              color: titleColor ?? theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              // Zero padding and a shrink-wrapped target so moving the row onto
              // the page margin does not also move the label a step inside it.
              // The row is already 40pt tall, which is the tap target the
              // button would otherwise pad its way to.
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel),
                  const Icon(Icons.chevron_right, size: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
