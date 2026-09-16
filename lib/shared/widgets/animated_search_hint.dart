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

/// A placeholder whose phrase rises into place, holds long enough to be read,
/// and leaves upward as the next one arrives.
///
/// Each phrase is shown whole -- `Search for "running shoes"` -- and turns
/// over whole: the lead and the quoted keyword move together, with the cursor
/// after the closing quote.
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

  /// What comes before the quoted keyword. It turns over with the keyword.
  final String prefix;

  /// Holds the run where it is -- the field has the shopper's attention.
  final bool paused;

  /// Whether the cursor blinks.
  ///
  /// The blink is a fade that never ends, which is right on a phone and wrong
  /// in a widget test: a page with one on it never settles. Tests turn it off
  /// in `flutter_test_config.dart`, as they do the hero banner's autoplay, and
  /// the cursor is then drawn lit and still.
  static bool blinkEnabled = true;

  @override
  State<AnimatedSearchHint> createState() => _AnimatedSearchHintState();
}

class _AnimatedSearchHintState extends State<AnimatedSearchHint>
    with TickerProviderStateMixin {
  /// How long a phrase stays on screen before it turns over.
  static const _hold = Duration(milliseconds: 2600);

  /// The whole turn: the outgoing phrase takes 400 ms, and the incoming one
  /// takes 450 ms starting 50 ms in. Driven as one timeline so the overlap is
  /// exact rather than two animations that happen to line up.
  static const _turn = Duration(milliseconds: 500);
  static const _outMs = 400.0;
  static const _inDelayMs = 50.0;
  static const _inMs = 450.0;

  /// How far each travels, in logical pixels.
  static const _outRise = 16.0;
  static const _inDrop = 18.0;

  /// The container follows the arriving phrase's width over the same 450 ms.
  static const _resize = Duration(milliseconds: 450);

  /// Each half of the blink: full to nothing, or nothing to full.
  static const _blinkHalf = Duration(milliseconds: 550);

  Timer? _timer;
  int _phrase = 0;

  /// The phrase leaving, for the length of a turn. Null when none is.
  String? _leaving;

  bool _reducedMotion = false;

  late final AnimationController _turnClock =
      AnimationController(vsync: this, duration: _turn, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && _leaving != null) {
            setState(() => _leaving = null);
          }
        });

  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: _blinkHalf,
    value: 1,
  );

  /// Eased both ways, so the blink is a breath rather than a flicker.
  late final Animation<double> _blinkCurve = CurvedAnimation(
    parent: _blink,
    curve: Curves.easeInOut,
  );

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

  /// Starts or stops the run, and the blink, to match what they should be.
  void _sync() {
    _timer?.cancel();

    // The cursor keeps its own time, not the phrases': it blinks whenever the
    // hint is drawn and motion is allowed.
    if (AnimatedSearchHint.blinkEnabled && !_reducedMotion) {
      if (!_blink.isAnimating) _blink.repeat(reverse: true);
    } else {
      _blink.stop();
      _blink.value = 1;
    }

    if (_still) return;
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
    setState(() {
      _leaving = _current;
      _phrase = (_phrase + 1) % widget.phrases.length;
    });
    _turnClock.forward(from: 0);
    // The next hold starts once this turn is over, so every phrase gets its
    // full 2.6 seconds fully on screen.
    _timer = Timer(_hold + _turn, _next);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _turnClock.dispose();
    _blink.dispose();
    super.dispose();
  }

  /// 0 to 1 across [durationMs], starting [delayMs] into the turn.
  double _phase(double delayMs, double durationMs) {
    final elapsed = _turnClock.value * _turn.inMilliseconds;
    return ((elapsed - delayMs) / durationMs).clamp(0.0, 1.0);
  }

  /// The whole placeholder for [keyword], exactly as it is shown:
  /// `Search for "running shoes"`. The lead is part of the phrase, so the two
  /// turn over together rather than the keyword moving under a fixed lead.
  String _phraseFor(String keyword) => '${widget.prefix}"$keyword"';

  Widget _word(String keyword, TextStyle? style) => Text(
    _phraseFor(keyword),
    key: ValueKey(keyword),
    style: style,
    maxLines: 1,
    // Long phrases on a narrow phone shorten rather than push the icons off
    // the end of the pill.
    overflow: TextOverflow.ellipsis,
    softWrap: false,
  );

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final caretHeight = (style?.fontSize ?? 14) * 1.1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The whole phrase turns over -- "Search for" with its quoted keyword --
        // in one piece. The container is sized to the arriving phrase and
        // follows it over 450 ms, so the cursor after the closing quote moves
        // at the pace of the text change. Flexible, so at a large text size
        // the phrase shortens rather than pushing the buttons off the pill.
        Flexible(
          child: AnimatedSize(
            duration: _resize,
            curve: Curves.easeInOut,
            alignment: Alignment.centerLeft,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _turnClock,
                builder: (context, _) {
                  final leaving = _leaving;
                  // Out: up 16 while fading to nothing, over 400 ms,
                  // slow to start and quick to finish.
                  final out = Curves.easeIn.transform(_phase(0, _outMs));
                  // In: from 18 below while fading in, over 450 ms from
                  // 50 ms after the out began, quick to start and slow
                  // to settle.
                  final into = Curves.easeOut.transform(
                    _phase(_inDelayMs, _inMs),
                  );
                  // Reduced motion keeps the fades and drops the travel.
                  final travel = !_reducedMotion;

                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      if (leaving != null)
                        // Out of the layout, so the container is the
                        // arriving phrase's width alone.
                        Positioned(
                          left: 0,
                          child: Opacity(
                            opacity: 1 - out,
                            child: Transform.translate(
                              offset: Offset(0, travel ? -_outRise * out : 0),
                              child: _word(leaving, style),
                            ),
                          ),
                        ),
                      Opacity(
                        opacity: leaving == null ? 1 : into,
                        child: Transform.translate(
                          offset: Offset(
                            0,
                            travel && leaving != null
                                ? _inDrop * (1 - into)
                                : 0,
                          ),
                          child: _word(_current, style),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        // A caret, so the changing word reads as something being typed rather
        // than as text failing to render. It keeps its own time: the blink is
        // not tied to the turn, the way a real one is not. Behind its own
        // repaint boundary, so a fade that never stops repaints one thin line
        // and not the header around it.
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: RepaintBoundary(
            child: FadeTransition(
              key: const ValueKey('search-caret'),
              opacity: _blinkCurve,
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
        ),
      ],
    );
  }
}
