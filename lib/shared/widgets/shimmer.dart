import 'package:flutter/material.dart';

/// One ticker for every placeholder underneath it.
///
/// Wrap a skeleton in this and its [ShimmerBone]s all pulse together off a
/// single [AnimationController]. That matters at the sizes skeletons actually
/// reach: a grid of six product cards carries eighteen bones, and eighteen
/// controllers is eighteen tickers each dirtying its own subtree every frame.
/// Shared, it is one ticker and one rebuild.
///
/// Pulsing rather than a sweeping gradient band. A translated gradient means a
/// shader per bone per frame, and on the profile traces from this app the
/// placeholders are on screen exactly when the main thread is busiest -- during
/// the first fetch. An opacity pulse costs nothing and reads the same.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  /// The pulse, or null when there is no [Shimmer] above. A bone with no
  /// shimmer to read holds still rather than throwing, so a placeholder can be
  /// dropped anywhere.
  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.notifier;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A pulsing placeholder is precisely the kind of motion reduced-motion is
    // asking about. Held at mid-pulse rather than stopped at either end, so it
    // still reads as a placeholder and not as an empty box or a filled one.
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ShimmerScope(notifier: _controller, child: widget.child);
  }
}

class _ShimmerScope extends InheritedNotifier<Animation<double>> {
  const _ShimmerScope({required super.notifier, required super.child});
}

/// A stand-in for a line of text, a price, a button -- anything but a picture.
///
/// Takes the size of the thing it replaces rather than a size of its own, which
/// is the only way a skeleton avoids shifting the layout when the real content
/// lands.
class ShimmerBone extends StatelessWidget {
  const ShimmerBone({super.key, this.width, this.height = 11, this.radius = 4});

  /// Null fills whatever width the parent gives.
  final double? width;
  final double height;
  final double radius;

  /// A square-cornered block, for a picture's place.
  const ShimmerBone.block({
    super.key,
    this.width,
    required this.height,
    this.radius = 10,
  });

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final pulse = Shimmer.maybeOf(context);

    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: SizedBox(width: width, height: height),
    );

    if (pulse == null) return box;

    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) => Opacity(
        // Never to nothing and never to solid: a bone that vanishes reads as a
        // gap in the layout, and one at full strength reads as real content.
        opacity: 0.45 + pulse.value * 0.4,
        child: box,
      ),
    );
  }
}

/// A bone that fills the box it is given, for a square product picture.
class ShimmerPanel extends StatelessWidget {
  const ShimmerPanel({super.key, this.radius = 10, this.aspectRatio});

  final double radius;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final bone = LayoutBuilder(
      builder: (context, constraints) => ShimmerBone(
        width: constraints.maxWidth.isFinite ? constraints.maxWidth : null,
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
        radius: radius,
      ),
    );

    if (aspectRatio == null) return bone;
    return AspectRatio(aspectRatio: aspectRatio!, child: bone);
  }
}
