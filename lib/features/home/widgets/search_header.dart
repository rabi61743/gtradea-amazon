import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// Sticky search bar over the brand colour.
///
/// The pill is deliberately white in both brightnesses because it sits on the
/// teal band rather than on the page background — but every child then has to
/// pin its own colour, or it inherits a light-on-white foreground.
class SearchHeader extends StatelessWidget {
  const SearchHeader({
    super.key,
    this.hintText = 'Search products',
    this.onTap,
    this.onImageSearch,
  });

  final String hintText;
  final VoidCallback? onTap;
  final VoidCallback? onImageSearch;

  @override
  Widget build(BuildContext context) {
    final onPill = Colors.black.withValues(alpha: 0.55);

    return Container(
      color: AppColors.primaryLight,
      padding: EdgeInsets.fromLTRB(
        12,
        MediaQuery.of(context).padding.top + 10,
        12,
        12,
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(Icons.search, size: 22, color: onPill),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hintText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: onPill),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.center_focus_weak, size: 22, color: onPill),
                  tooltip: 'Search by image',
                  onPressed: onImageSearch,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
