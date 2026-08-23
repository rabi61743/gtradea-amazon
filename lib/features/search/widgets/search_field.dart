import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

/// The search field as it appears inside the teal header, with a back arrow
/// and a camera affordance.
///
/// The pill is white in both brightnesses because it sits on the brand band,
/// so every child pins its own colour instead of inheriting one that would
/// vanish against it.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    this.autofocus = false,
    this.readOnly = false,
    this.onSubmitted,
    this.onTap,
    this.onImageSearch,
    this.trailing,
  });

  final TextEditingController controller;
  final bool autofocus;
  final bool readOnly;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final VoidCallback? onImageSearch;

  /// Extra action to the right of the field, e.g. the cart.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final onPill = Colors.black.withValues(alpha: 0.55);

    return Container(
      color: AppColors.primaryLight,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 10),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.onPrimary),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(Icons.search, size: 20, color: onPill),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          autofocus: autofocus,
                          readOnly: readOnly,
                          onTap: onTap,
                          onSubmitted: onSubmitted,
                          textInputAction: TextInputAction.search,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.black.withValues(alpha: 0.87),
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: 'Search products',
                            hintStyle: TextStyle(fontSize: 15, color: onPill),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.photo_camera_outlined,
                            size: 20, color: onPill),
                        tooltip: 'Search by image',
                        onPressed: onImageSearch,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
