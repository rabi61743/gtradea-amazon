import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';

/// One of the labelled chrome actions in the home header's right-hand group.
///
/// Icon over a word, with the count the control can actually compute badged on
/// the icon. The word is the point: three unlabelled glyphs on a teal band were
/// a guessing game, and the truck in particular was read as delivery rather
/// than as orders.
///
/// Shared by the three that sit in that group -- orders, notifications and the
/// cart -- so the metrics cannot drift apart between them. Each keeps its own
/// destination, badge and signed-out answer; this only draws them.
class HeaderActionTile extends StatelessWidget {
  const HeaderActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.count = 0,
    this.tooltip,
    this.color = AppColors.onPrimary,
    this.iconSize = 23,
  });

  /// The width of one tile's content, before its own padding.
  ///
  /// Three of these plus the block's insets have to leave the delivery line
  /// enough of a 360pt phone to say where the parcel is going, which is what
  /// keeps this narrow.
  ///
  /// 42 rather than 46 since the group was compacted. The floor under it is the
  /// tap target, not the artwork: 42 plus this tile's own 2pt sides is 46, and
  /// 44 is the smallest thing a thumb should be asked to hit.
  static const double _slot = 42;

  final IconData icon;

  /// The word under the glyph.
  final String label;

  /// What the badge says. Nothing is drawn at zero -- a badge reading 0 is a
  /// notification about the absence of notifications.
  final int count;

  final String? tooltip;
  final Color color;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip ?? label,
      // Carries its own Material rather than relying on finding one above, for
      // the reason the delivery button does: a ripple that depends on where a
      // caller puts the widget throws the first time it moves.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: ConstrainedBox(
              // One width for all three, so the group is a set of equal
              // columns rather than three boxes sized by how long their words
              // happen to be -- and a floor under the height, because the
              // glyph shrank when the label arrived under it and the thing a
              // thumb has to hit should not have shrunk with it.
              constraints: const BoxConstraints(
                minWidth: _slot,
                maxWidth: _slot,
                minHeight: 36,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Badge.count(
                    count: count,
                    isLabelVisible: count > 0,
                    // The specified badge: Commerce Orange, bold, and a disc
                    // wide enough to read at arm's length. Material's default
                    // is the theme's error red at 8pt, which on this band was
                    // a red speck.
                    backgroundColor: AppColors.commerceOrange,
                    textColor: AppColors.onPrimary,
                    textStyle: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                    largeSize: 15,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(icon, size: iconSize, color: color),
                  ),
                  const SizedBox(height: 1),
                  // Scaled down rather than clipped: "Notifications" is longer
                  // than its slot on a narrow phone, and a shopper reading
                  // "Notificati..." learns nothing the icon did not already
                  // tell them. Shrinking keeps the whole word, which is the
                  // reason the label is there at all.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9.5,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        color: color.withValues(alpha: 0.92),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
