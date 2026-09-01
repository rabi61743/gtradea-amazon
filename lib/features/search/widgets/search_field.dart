import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/animated_search_hint.dart';
import 'voice_search_sheet.dart';

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
    this.onChanged,
    this.onTap,
    this.onImageSearch,
    this.trailing,
  });

  final TextEditingController controller;
  final bool autofocus;
  final bool readOnly;
  final ValueChanged<String>? onSubmitted;

  /// Called on every keystroke, for typeahead. Null on the screens that have
  /// nothing to suggest, which is most of them.
  final ValueChanged<String>? onChanged;

  final VoidCallback? onTap;
  final VoidCallback? onImageSearch;

  /// Extra action to the right of the field, e.g. the cart.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final onPill = Colors.black.withValues(alpha: 0.55);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Same teal band as the home header, and the same reason: without this
      // the status bar icons are drawn dark on dark.
      value: AppTheme.brandBandOverlay,
      child: Container(
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
                          // The animated hint sits behind the field rather
                          // than in `hintText`, which takes a plain string and
                          // cannot move. It is built only while the box is
                          // empty, so the first keystroke removes it outright
                          // -- there is no placeholder left to compete with
                          // what is being typed, and nothing about the field,
                          // its suggestions or its submission changes.
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: controller,
                                builder: (context, value, _) =>
                                    value.text.isEmpty
                                    ? IgnorePointer(
                                        child: AnimatedSearchHint(
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: onPill,
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              TextField(
                                controller: controller,
                                autofocus: autofocus,
                                readOnly: readOnly,
                                onTap: onTap,
                                onSubmitted: onSubmitted,
                                onChanged: onChanged,
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
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Voice first, then image, matching the home header --
                        // a shopper sees both bands within a second of each
                        // other and the pair should not reorder between them.
                        VoiceSearchButton(
                          size: 20,
                          color: onPill,
                          onResult: (transcript) => _dictated(transcript),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.photo_camera_outlined,
                            size: 20,
                            color: onPill,
                          ),
                          tooltip: 'Search by image',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          onPressed: onImageSearch,
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 4), trailing!],
            ],
          ),
        ),
      ),
    );
  }

  /// What a dictated query does here.
  ///
  /// The text lands in the field first and the search runs from it, so the
  /// shopper both gets what they asked for and keeps the words in front of them
  /// to fix if the recogniser misheard one. Filling the field without searching
  /// would read as broken; searching without filling it would leave them
  /// nothing to correct.
  void _dictated(String transcript) {
    controller.value = TextEditingValue(
      text: transcript,
      selection: TextSelection.collapsed(offset: transcript.length),
    );
    onSubmitted?.call(transcript);
  }
}
