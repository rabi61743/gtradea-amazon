import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The examples the search bar offers when nobody has typed anything.
///
/// Short, concrete and from different corners of the catalogue, so the three
/// together read as "this shop sells all sorts" rather than as one department.
// const List<String> kSearchHintPhrases = <String>[
//   'Lamp',
//   'Kid Fashion',
//   'Shoes',
// ];

const List<String> kSearchHintPhrases = <String>[
  'Lamp',
  'Kid Fashion',
  'Shoes',
  'Watches',
  'Backpacks',
  'Dresses',
  'T-Shirts',
  'Jeans',
  'Sunglasses',
  'Handbags',
  'Sneakers',
  'Home Decor',
  'Furniture',
  'Kitchen Essentials',
  'Beauty Products',
  'Skincare',
  'Jewelry',
  'Toys',
  'Sportswear',
  'Electronics',
  'Headphones',
  'Mobile Accessories',
  'Books',
  'Gifts',
  'Baby Products',
  'Men Fashion',
  'Women Fashion',
  'Pet Supplies',
  'Fitness Equipment',
  'Office Supplies',
];

/// A placeholder that types itself out, holds, erases, and moves on.
///
/// The lead word is fixed and only the example is animated: a whole line that
/// re-types itself every few seconds pulls the eye away from the page, where
/// one word changing under a steady "Search" reads as a suggestion rather than
/// as motion.
///
/// It stops for the two cases where an animated hint is wrong: when the reader
/// has asked the system for less movement, and when there is nothing to hint
/// at because the shopper is already typing -- that second one is the caller's
/// business, which simply stops building this.
class AnimatedSearchHint extends StatefulWidget {
  const AnimatedSearchHint({
    super.key,
    required this.style,
    this.phrases = kSearchHintPhrases,
    this.prefix = 'Search ',
  });

  final TextStyle? style;
  final List<String> phrases;

  /// The part that does not move.
  final String prefix;

  @override
  State<AnimatedSearchHint> createState() => _AnimatedSearchHintState();
}

class _AnimatedSearchHintState extends State<AnimatedSearchHint> {
  /// How fast a phrase appears, letter by letter. Quick enough to read as
  /// typing rather than as a countdown.
  static const _typeStep = Duration(milliseconds: 62);

  /// Erasing is faster than typing, the way a real correction is.
  static const _eraseStep = Duration(milliseconds: 28);

  /// Long enough to actually read the finished word.
  static const _hold = Duration(milliseconds: 1400);

  /// A beat before the next one starts, so the phrases do not run together.
  static const _between = Duration(milliseconds: 260);

  Timer? _timer;
  int _phrase = 0;
  int _shown = 0;
  bool _erasing = false;
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced != _reducedMotion) {
      _reducedMotion = reduced;
      _restart();
    }
  }

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(AnimatedSearchHint old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.phrases, widget.phrases)) {
      _phrase = 0;
      _shown = 0;
      _erasing = false;
      _restart();
    }
  }

  void _restart() {
    _timer?.cancel();
    if (_still) {
      // One complete phrase, held. The hint still says what it is for.
      _shown = _current.length;
      return;
    }
    _schedule(_typeStep);
  }

  /// True when the phrases must not cycle.
  bool get _still => _reducedMotion || widget.phrases.length < 2;

  String get _current => widget.phrases.isEmpty
      ? ''
      : widget.phrases[_phrase % widget.phrases.length];

  void _schedule(Duration after) {
    _timer = Timer(after, _tick);
  }

  void _tick() {
    if (!mounted) return;

    final phrase = _current;
    if (_erasing) {
      if (_shown == 0) {
        _erasing = false;
        _phrase = (_phrase + 1) % widget.phrases.length;
        setState(() {});
        _schedule(_between);
        return;
      }
      setState(() => _shown -= 1);
      _schedule(_eraseStep);
      return;
    }

    if (_shown >= phrase.length) {
      _erasing = true;
      _schedule(_hold);
      return;
    }
    setState(() => _shown += 1);
    _schedule(_typeStep);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typed = _current.substring(0, _shown.clamp(0, _current.length));

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: widget.prefix),
          TextSpan(text: typed),
          // A caret, so the changing word reads as something being typed
          // rather than as text failing to render. Drawn only while the
          // phrases are actually moving.
          if (!_still)
            TextSpan(
              text: '|',
              style: TextStyle(
                color: widget.style?.color?.withValues(alpha: 0.55),
              ),
            ),
        ],
      ),
      style: widget.style,
      maxLines: 1,
      // Long phrases on a narrow phone shorten rather than push the icons off
      // the end of the pill.
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
  }
}
