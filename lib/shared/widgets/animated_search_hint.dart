import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The examples the search bar offers when nobody has typed anything.
///
/// Written as the end of a sentence that starts "Search for", in the words a
/// shopper would type, so the hint reads as a suggestion rather than as a
/// department label. From different corners of the catalogue, so the run of
/// them says "this shop sells all sorts". Visual only: none of these is ever
/// put into the box or searched for.
///
/// Each one is kept to [kSearchHintMaxLength] characters. The home header's
/// pill is narrow on a phone, and measured on one, "kitchen essentials" ran
/// out of room and ended in an ellipsis with the cursor stranded after it --
/// a hint that cannot be read is not a hint.
const List<String> kSearchHintPhrases = <String>[
  'running shoes',
  'winter jackets',
  'gift ideas',
  'handbags',
  'home decor',
  'kids fashion',
  'headphones',
  'kitchenware',
  'watches',
  'sunglasses',
  'backpacks',
  'skincare',
  'jewelry',
  'toys',
  'sportswear',
  'phone cases',
  'baby products',
  'stationery',
  'pet supplies',
  'gym gear',
];

/// The longest example that still reads whole in the home header on a phone.
const int kSearchHintMaxLength = 14;

/// A placeholder whose example rises into place, holds long enough to be read,
/// and leaves upward as the next one arrives.
///
/// The lead word is fixed and only the example moves: a whole line changing
/// every few seconds pulls the eye off the page, where one word turning over
/// under a steady "Search" reads as a suggestion.
///
/// It stops for the three cases where an animated hint is wrong: when the
/// reader has asked the system for less movement, when the shopper is typing
/// -- the caller stops building it then -- and when they have put the cursor
/// in the box and are about to, which is [paused]. Pausing holds the phrase it
/// is on rather than starting the run again, so coming back to an untouched
/// box does not rewind it.
class AnimatedSearchHint extends StatefulWidget {
  const AnimatedSearchHint({
    super.key,
    required this.style,
    this.phrases = kSearchHintPhrases,
    this.prefix = 'Search for ',
    this.paused = false,
  });

  final TextStyle? style;
  final List<String> phrases;

  /// The part that does not move.
  final String prefix;

  /// Holds the run where it is -- the field has the shopper's attention.
  final bool paused;

  @override
  State<AnimatedSearchHint> createState() => _AnimatedSearchHintState();
}

class _AnimatedSearchHintState extends State<AnimatedSearchHint> {
  /// Long enough to actually read the word before it goes.
  static const _hold = Duration(milliseconds: 2200);

  /// The turn itself: one word up and out as the next comes up from below.
  static const _turn = Duration(milliseconds: 420);

  /// How long the cursor stays in each state -- a heartbeat, not a flicker.
  static const _blink = Duration(milliseconds: 600);

  /// How long it takes to fade between them. Shorter than [_blink], so there
  /// is a still moment in every beat: the cursor is a timer and a fade, not an
  /// animation running for as long as the page is open, which would repaint
  /// the header every frame just to move one line of pixels.
  static const _caretFade = Duration(milliseconds: 280);

  Timer? _timer;
  Timer? _caretTimer;
  bool _caretOn = true;
  int _phrase = 0;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced != _reducedMotion) {
      _reducedMotion = reduced;
      _sync();
    }
  }

  @override
  void didUpdateWidget(AnimatedSearchHint old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.phrases, widget.phrases)) _phrase = 0;
    // Pausing and resuming only start or stop the clock. The phrase on screen
    // is where it was.
    if (old.paused != widget.paused ||
        !listEquals(old.phrases, widget.phrases)) {
      _sync();
    }
  }

  /// Starts or stops the run to match the state it should be in.
  void _sync() {
    _timer?.cancel();
    _caretTimer?.cancel();
    if (_still) {
      // Held: the cursor stays lit rather than blinking at nothing. Set
      // directly -- this runs from the lifecycle hooks, and a build follows.
      _caretOn = true;
      return;
    }
    _caretTimer = Timer.periodic(_blink, (_) {
      if (mounted) setState(() => _caretOn = !_caretOn);
    });
    _timer = Timer(_hold, _next);
  }

  /// True when the phrases must not cycle.
  bool get _still =>
      _reducedMotion || widget.paused || widget.phrases.length < 2;

  String get _current => widget.phrases.isEmpty
      ? ''
      : widget.phrases[_phrase % widget.phrases.length];

  void _next() {
    if (!mounted || _still) return;
    setState(() => _phrase = (_phrase + 1) % widget.phrases.length);
    _timer = Timer(_hold, _next);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _caretTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final caretHeight = (style?.fontSize ?? 14) * 1.1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Allowed to shorten too. At a large accessibility text size the
              // lead alone can be wider than the pill, and a fixed-width lead
              // would push the voice and camera buttons off the end of it.
              Flexible(
                child: Text(
                  widget.prefix,
                  style: style,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // The example, and only the example, turns over. Sized to what
              // is in it so the cursor after it moves with the word rather
              // than sitting at a fixed distance -- and animated, so a longer
              // phrase widens the run instead of jumping to it.
              Flexible(
                child: AnimatedSize(
                  duration: _turn,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.centerLeft,
                  child: ClipRect(
                    child: AnimatedSwitcher(
                      duration: _turn,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      // Both words are on screen at once during the turn, and
                      // laid out on top of each other they would fight for the
                      // width. The outgoing one is taken out of the layout.
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          ...previous.map(
                            (child) => Positioned(left: 0, child: child),
                          ),
                          ?current,
                        ],
                      ),
                      transitionBuilder: (child, animation) {
                        // Reduced motion keeps the change without the travel:
                        // the word fades rather than riding up the pill.
                        if (_reducedMotion) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        }
                        final slide = Tween<Offset>(
                          begin: const Offset(0, 0.9),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(position: slide, child: child),
                        );
                      },
                      child: Text(
                        _current,
                        key: ValueKey(_current),
                        style: style,
                        maxLines: 1,
                        // Long phrases on a narrow phone shorten rather than
                        // push the icons off the end of the pill.
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // A caret, so the changing word reads as something being typed rather
        // than as text failing to render. It keeps its own time: the blink is
        // not tied to the turn, the way a real one is not.
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: AnimatedOpacity(
            key: const ValueKey('search-caret'),
            opacity: _caretOn ? 0.7 : 0.15,
            duration: _caretFade,
            curve: Curves.easeInOut,
            child: Container(
              width: 1.5,
              height: caretHeight,
              decoration: BoxDecoration(
                color: style?.color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
