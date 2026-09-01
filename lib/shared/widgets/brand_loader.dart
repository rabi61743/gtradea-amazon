import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import 'brand_wordmark.dart';

/// The mark, with an arc travelling round it.
///
/// Built to the reference: a faint complete ring, one bright arc sweeping it,
/// and the logo held still in the middle. The logo does **not** rotate -- a
/// spinning brand mark is a novelty the fifth time somebody sees it, and it
/// makes the one element that has to stay legible the one element that never
/// is.
///
/// Everything is drawn: the ring is two arcs on a canvas rather than a
/// `CircularProgressIndicator` tinted orange, because the reference's arc is a
/// specific fraction of the circle with rounded ends and Material's spinner
/// animates its own sweep as well as its rotation.
class BrandLoader extends StatefulWidget {
  const BrandLoader({super.key, this.size = 56, this.label});

  /// The ring's diameter. The mark inside is sized from it, so one number
  /// scales the whole thing and the proportions cannot drift.
  final double size;

  /// Shown under the ring. Say what is being waited for -- "Loading products"
  /// beats a bare "Loading", which tells somebody only that they are waiting,
  /// which they already know.
  final String? label;

  /// How much of the circle the bright arc covers.
  static const _sweep = math.pi * 0.55;

  /// The mark's share of the ring's diameter. Comfortably inside the stroke,
  /// so the arc passes round the logo rather than across it.
  static const _markScale = 0.52;

  @override
  State<BrandLoader> createState() => _BrandLoaderState();
}

class _BrandLoaderState extends State<BrandLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion gets the ring and the mark, held still. The arc parked
    // off the top still reads as "in progress" rather than as a plain circle.
    if (MediaQuery.of(context).disableAnimations) {
      _spin.stop();
      _spin.value = 0.12;
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.label;

    return Semantics(
      // One announcement for the whole thing. The mark inside carries the
      // company name, which is not what somebody waiting needs to hear.
      label: label ?? 'Loading',
      liveRegion: true,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) => CustomPaint(
                      painter: _RingPainter(
                        turn: _spin.value,
                        track: theme.colorScheme.outlineVariant,
                        arc: AppColors.accent,
                        stroke: widget.size * 0.055,
                      ),
                    ),
                  ),
                ),
                // Outside the AnimatedBuilder on purpose: the mark is static,
                // so it is built once rather than sixty times a second.
                //
                // Centred explicitly. The wordmark aligns to the start by
                // default -- right for a header row -- and its Align expands to
                // fill this Stack, so the default left-pinned the mark against
                // the inside of the ring instead of sitting in the middle.
                BrandWordmark(
                  height: widget.size * BrandLoader._markScale,
                  alignment: Alignment.center,
                ),
              ],
            ),
          ),
          if (label != null) ...[
            SizedBox(height: widget.size * 0.28),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.turn,
    required this.track,
    required this.arc,
    required this.stroke,
  });

  /// Where the bright arc has got to, 0 to 1 of a full revolution.
  final double turn;
  final Color track;
  final Color arc;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = Rect.fromCircle(
      center: rect.center,
      radius: (size.shortestSide - stroke) / 2,
    );

    canvas.drawArc(
      circle,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    canvas.drawArc(
      circle,
      // From twelve o'clock, which is where a sweep is read as starting.
      -math.pi / 2 + turn * math.pi * 2,
      BrandLoader._sweep,
      false,
      Paint()
        ..color = arc
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.turn != turn ||
      old.track != track ||
      old.arc != arc ||
      old.stroke != stroke;
}

/// The whole screen, for the one case that earns it: the app opening with
/// nothing cached to paint.
///
/// Every later wait gets a skeleton instead. Replacing a page somebody is
/// already reading with a logo is a step backwards, however nice the logo.
class BrandLoaderScreen extends StatelessWidget {
  const BrandLoaderScreen({super.key, this.label = 'Loading your storefront'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(child: BrandLoader(size: 64, label: label)),
    );
  }
}
