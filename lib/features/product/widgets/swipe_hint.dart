import 'package:flutter/material.dart';

/// "Swipe left to see more sizes", under something that has more to the right.
///
/// The hand and arrow is the gesture itself, which is quicker to read than the
/// sentence beside it; the sentence says which way and what for. Both are in
/// the page's own blue rather than a colour of their own.
///
/// Shared by the chip rows and the quantity grid, so a shopper meets one hint
/// worded one way wherever a row of options runs past the edge.
class SwipeHint extends StatelessWidget {
  const SwipeHint({super.key, required this.noun});

  /// What is past the edge: "sizes", "colours".
  final String noun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.primary;

    // Centred, and sized to its words rather than to the row: AnimatedSize
    // hands its child loose constraints, and a Row that took all of them
    // overflowed by 67px the first time this was drawn.
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swipe_left_alt, size: 20, color: ink),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Swipe left to see more $noun',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}
