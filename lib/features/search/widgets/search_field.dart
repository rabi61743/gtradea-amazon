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
class SearchField extends StatefulWidget {
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
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  /// Held here so the trailing controls can tell composing a query apart from
  /// merely reading one back: the results header keeps the query in the box
  /// long after the shopper has stopped typing.
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// True while the shopper is writing a query: the box is theirs, it has
  /// words in it, and the useful action is running the search.
  bool get _typing =>
      !widget.readOnly &&
      _focus.hasFocus &&
      widget.controller.text.trim().isNotEmpty;

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
                              AnimatedBuilder(
                                animation: Listenable.merge([
                                  widget.controller,
                                  _focus,
                                ]),
                                builder: (context, _) {
                                  if (widget.controller.text.isNotEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  // Focused but empty: the hint fades and the
                                  // run holds where it is, so the box belongs
                                  // to whoever is about to type in it. Coming
                                  // back to an untouched box resumes from the
                                  // phrase it stopped on rather than starting
                                  // the list again.
                                  final focused = _focus.hasFocus;
                                  return IgnorePointer(
                                    child: AnimatedOpacity(
                                      opacity: focused ? 0 : 1,
                                      duration: const Duration(
                                        milliseconds: 160,
                                      ),
                                      child: AnimatedSearchHint(
                                        paused: focused,
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: onPill,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              TextField(
                                controller: widget.controller,
                                focusNode: _focus,
                                autofocus: widget.autofocus,
                                readOnly: widget.readOnly,
                                onTap: widget.onTap,
                                onSubmitted: widget.onSubmitted,
                                onChanged: widget.onChanged,
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
                        // The other ways of asking, while the shopper is not
                        // mid-query. Once there are words being typed they are
                        // not what is wanted -- running the search is -- and
                        // two ways to start a different search would sit where
                        // the answer belongs.
                        //
                        // A query the shopper is only reading back, as the
                        // results header shows it, keeps the pair: they have
                        // finished asking, and asking again by voice or photo
                        // is exactly what that header is for.
                        //
                        // Voice first, then image, matching the home header:
                        // a shopper sees both bands within a second of each
                        // other and the pair should not reorder between them.
                        // Takes back what was typed, without leaving the box:
                        // shown only while there is something to take back.
                        AnimatedBuilder(
                          animation: widget.controller,
                          builder: (context, _) =>
                              widget.controller.text.isEmpty
                              ? const SizedBox.shrink()
                              : IconButton(
                                  key: const ValueKey('search-clear'),
                                  icon: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: onPill,
                                  ),
                                  tooltip: 'Clear',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 30,
                                    height: 30,
                                  ),
                                  onPressed: () {
                                    widget.controller.clear();
                                    // The same keystroke path the typing takes,
                                    // so a screen with suggestions clears them
                                    // rather than holding the last ones.
                                    widget.onChanged?.call('');
                                    // The box stays the shopper's: they cleared
                                    // it to type something else.
                                    if (!widget.readOnly) _focus.requestFocus();
                                  },
                                ),
                        ),
                        AnimatedBuilder(
                          animation: Listenable.merge([
                            widget.controller,
                            _focus,
                          ]),
                          builder: (context, _) => AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            // Cross-faded in place: the pair and the submit
                            // are the same width, so nothing in the pill
                            // shifts as they swap.
                            child: _typing
                                ? IconButton(
                                    key: const ValueKey('submit'),
                                    icon: Icon(
                                      Icons.arrow_forward,
                                      size: 20,
                                      color: onPill,
                                    ),
                                    tooltip: 'Search',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 34,
                                      height: 34,
                                    ),
                                    // The same submission the keyboard's own
                                    // search key runs, so both routes end in
                                    // one place.
                                    onPressed: () => widget.onSubmitted?.call(
                                      widget.controller.text,
                                    ),
                                  )
                                : Row(
                                    key: const ValueKey('ask'),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      VoiceSearchButton(
                                        size: 20,
                                        color: onPill,
                                        onResult: _dictated,
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.photo_camera_outlined,
                                          size: 20,
                                          color: onPill,
                                        ),
                                        tooltip: 'Search by image',
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 34,
                                              height: 34,
                                            ),
                                        onPressed: widget.onImageSearch,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 4),
                widget.trailing!,
              ],
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
    widget.controller.value = TextEditingValue(
      text: transcript,
      selection: TextSelection.collapsed(offset: transcript.length),
    );
    widget.onSubmitted?.call(transcript);
  }
}
