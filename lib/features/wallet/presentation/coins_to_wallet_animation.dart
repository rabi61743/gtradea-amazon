import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/motion/motion_curves.dart';
import '../../home/widgets/product_rail.dart' show formatGrouped;

/// Coins materialise, fly into a wallet, and the wallet reveals a total.
///
/// A self-contained visual. It is handed the number to reveal and knows
/// nothing about where that number came from: today the only caller is a
/// labelled preview, and once the points API exists the same widget is handed
/// the real balance. It reads no store, calls nothing and changes nothing.
///
/// The whole sequence is exactly [duration] -- one second -- on one timeline:
///
///   * 0.0 s  the spark: one coin fades in, spinning, over a gold glow;
///   * 0.2 s  the cascade: four more pop in on a stagger, each with sparkles;
///   * 0.5 s  the flight: all five arc into the wallet one after another,
///            trailing, shrinking and dissolving into light at its edge;
///   * 0.8 s  the reveal: the total rises out of the wallet as it lights up;
///   * 1.0 s  the settle: a last ring of sparkles, and a calm final frame.
///
/// Coins, trails and particles are painted rather than built, so there is
/// nothing to clean up when a phase ends: the painter simply stops drawing
/// them. Only the number is a widget, so it is set as real text.
class CoinsToWalletAnimation extends StatefulWidget {
  const CoinsToWalletAnimation({
    super.key,
    required this.value,
    this.preview = false,
    this.onFinished,
  });

  /// The total the wallet reveals. A demonstration value for now.
  final int value;

  /// Marks the scene as a demonstration, on screen and to screen readers.
  final bool preview;

  /// Called once the one-second sequence has played.
  final VoidCallback? onFinished;

  /// The total the preview reveals. A demonstration value, never a balance.
  static const demoValue = 1000;

  /// The whole sequence.
  static const duration = Duration(milliseconds: 1000);

  /// Whether the wallet's gentle idle shimmer runs after the sequence. It
  /// never ends, so widget tests turn it off to let a page settle.
  static bool idleShimmerEnabled = true;

  /// How long the finished scene stays up before it closes by itself.
  static const linger = Duration(milliseconds: 1400);

  /// Plays the scene over the current page, then closes it.
  ///
  /// A tap anywhere closes it early. Resolves once it has gone.
  static Future<void> show(
    BuildContext context, {
    required int value,
    bool preview = false,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 140),
      transitionBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (dialogContext, _, _) =>
          _Presented(value: value, preview: preview),
    );
  }

  @override
  State<CoinsToWalletAnimation> createState() => _CoinsToWalletAnimationState();
}

/// The scene as [CoinsToWalletAnimation.show] presents it: centred, sized to
/// the screen, closing itself a little after the sequence ends.
class _Presented extends StatefulWidget {
  const _Presented({required this.value, required this.preview});

  final int value;
  final bool preview;

  @override
  State<_Presented> createState() => _PresentedState();
}

class _PresentedState extends State<_Presented> {
  Timer? _close;

  void _finished() {
    _close = Timer(CoinsToWalletAnimation.linger, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _close?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // A phone gets most of its width; a tablet or desktop a card of the same
    // proportions rather than a scene stretched across the whole screen.
    final width = math.min(size.width * 0.86, 380.0);

    // A Material under the scene, or its text is drawn with Flutter's
    // missing-style underline -- the dialog route has none of its own.
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: SizedBox(
            width: width,
            height: width * 1.12,
            child: CoinsToWalletAnimation(
              value: widget.value,
              preview: widget.preview,
              onFinished: _finished,
            ),
          ),
        ),
      ),
    );
  }
}

class _CoinsToWalletAnimationState extends State<CoinsToWalletAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: CoinsToWalletAnimation.duration,
  );

  /// The wallet's idle shimmer, after the sequence.
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  bool _reduced = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.of(context).disableAnimations;
    if (_started) return;
    _started = true;
    _t.forward().whenComplete(() {
      if (!mounted) return;
      if (CoinsToWalletAnimation.idleShimmerEnabled && !_reduced) {
        _shimmer.repeat();
      }
      widget.onFinished?.call();
    });
  }

  @override
  void dispose() {
    _t.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.preview
          ? 'Animation preview: coins going into a wallet showing '
                '${formatGrouped(widget.value)}. No points were added.'
          : 'Wallet total ${formatGrouped(widget.value)}',
      excludeSemantics: true,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return AnimatedBuilder(
                animation: Listenable.merge([_t, _shimmer]),
                builder: (context, _) {
                  final ms = _t.value * 1000;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ScenePainter(
                            ms: ms,
                            shimmer: _shimmer.value,
                            reduced: _reduced,
                          ),
                        ),
                      ),
                      _Total(
                        key: const ValueKey('wallet-total'),
                        size: size,
                        ms: ms,
                        reduced: _reduced,
                        text: formatGrouped(widget.value),
                      ),
                      if (widget.preview)
                        const Positioned(
                          top: 14,
                          left: 16,
                          child: _PreviewTag(),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 0 to 1 across [from]..[to] milliseconds of the timeline.
double _seg(double ms, double from, double to) =>
    ((ms - from) / (to - from)).clamp(0.0, 1.0);

/// Where the scene's pieces sit, as fractions of its size, so it lays out the
/// same on a phone, a tablet and a desktop.
class _Layout {
  _Layout(this.size);

  final Size size;

  double get w => size.width;
  double get h => size.height;

  Offset get spark => Offset(w * 0.5, h * 0.33);

  /// The loose arc the cascade coins sit on, above the wallet.
  List<Offset> get arc => [
    spark + Offset(-w * 0.27, h * 0.04),
    spark + Offset(-w * 0.14, -h * 0.1),
    spark + Offset(w * 0.14, -h * 0.1),
    spark + Offset(w * 0.27, h * 0.04),
  ];

  Rect get wallet => Rect.fromCenter(
    center: Offset(w * 0.5, h * 0.74),
    width: w * 0.66,
    height: h * 0.3,
  );

  /// Where a coin enters the wallet: along its top edge, spread a little so
  /// five coins do not all hit one point.
  Offset entry(int i) =>
      Offset(wallet.center.dx + (i - 2) * w * 0.05, wallet.top + h * 0.02);

  double get coin => w * 0.085;
}

/// Everything but the number.
class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.ms,
    required this.shimmer,
    required this.reduced,
  });

  final double ms;
  final double shimmer;
  final bool reduced;

  static const _gold = Color(0xFFFFD700);
  static const _amber = Color(0xFFFFB300);
  static const _deepGold = Color(0xFFB8860B);

  /// The four cascade coins' pop-in times, a little apart.
  static const _popAt = [200.0, 255.0, 310.0, 365.0];
  static const _popFor = 150.0;

  /// Their slight differences in size and starting spin.
  static const _sizes = [0.78, 0.92, 0.86, 0.74];
  static const _spins = [0.6, 1.9, 3.1, 4.4];

  /// Flight: coin i leaves at 500 + 35i ms and takes 160 ms, so five coins
  /// land one after another and the last is in the wallet at exactly 0.8 s.
  static double _leave(int i) => 500 + 35.0 * i;
  static const _flight = 160.0;

  @override
  void paint(Canvas canvas, Size size) {
    final l = _Layout(size);
    _background(canvas, size);

    if (reduced) {
      _wallet(canvas, l, glow: _seg(ms, 0, 1000));
      return;
    }

    _spark(canvas, l);
    _wallet(canvas, l, glow: _revealGlow);

    // Every coin, in the order it will land: the spark first, then the arc.
    final homes = [l.spark, ...l.arc];
    for (var i = 0; i < homes.length; i++) {
      _coinLife(canvas, l, i, homes[i]);
    }

    _finalRing(canvas, l);
  }

  /// Deep navy into charcoal, top to bottom.
  void _background(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1B3A), Color(0xFF1C1F26)],
        ).createShader(rect),
    );
  }

  /// The gold bloom behind the first coin: in with it, down to an ambient
  /// level by the settle.
  void _spark(Canvas canvas, _Layout l) {
    final rise = Curves.easeOut.transform(_seg(ms, 0, 200));
    final calm = _seg(ms, 500, 1000);
    final strength = rise * (1 - 0.7 * calm);
    if (strength <= 0) return;
    final radius = l.coin * (3.2 + 0.6 * rise);
    canvas.drawCircle(
      l.spark,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _gold.withValues(alpha: 0.45 * strength),
            _gold.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: l.spark, radius: radius)),
    );
  }

  /// How lit the wallet's border is: rising as the total appears.
  double get _revealGlow => Curves.easeOut.transform(_seg(ms, 780, 950));

  void _wallet(Canvas canvas, _Layout l, {required double glow}) {
    final body = RRect.fromRectAndRadius(l.wallet, const Radius.circular(22));

    // Soft elevation beneath it.
    canvas.drawRRect(
      body.shift(const Offset(0, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // Frosted glass: a pale fill that is lighter at the top.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0.05),
          ],
        ).createShader(l.wallet),
    );

    // The flap line across the top third, so it reads as a wallet.
    final flapY = l.wallet.top + l.wallet.height * 0.3;
    canvas.drawLine(
      Offset(l.wallet.left + 18, flapY),
      Offset(l.wallet.right - 18, flapY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = 1,
    );

    // The border: a faint edge at rest, warm gold once the total is in.
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 + 1.3 * glow
        ..color = Color.lerp(
          Colors.white.withValues(alpha: 0.22),
          _amber.withValues(alpha: 0.95),
          glow,
        )!,
    );
    if (glow > 0) {
      canvas.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = _gold.withValues(alpha: 0.28 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    // The idle shimmer: a thin light that sweeps across the glass after the
    // settle, faint enough to be felt rather than watched.
    if (ms >= 1000 && shimmer > 0) {
      final x =
          l.wallet.left -
          l.wallet.width * 0.3 +
          (l.wallet.width * 1.6) * shimmer;
      final band = Rect.fromLTWH(
        x,
        l.wallet.top,
        l.wallet.width * 0.22,
        l.wallet.height,
      );
      canvas.save();
      canvas.clipRRect(body);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(band),
      );
      canvas.restore();
    }
  }

  /// One coin from appearing to being absorbed.
  void _coinLife(Canvas canvas, _Layout l, int i, Offset home) {
    final isSpark = i == 0;
    final scaleBase = isSpark ? 1.0 : _sizes[i - 1];
    final radius = l.coin * scaleBase;
    // A steady spin on the vertical axis, each coin at its own phase.
    final spin = (isSpark ? 0.0 : _spins[i - 1]) + ms / 1000 * math.pi * 2.4;

    // Appearing.
    double appear;
    if (isSpark) {
      appear = Curves.easeOut.transform(_seg(ms, 0, 180));
    } else {
      final at = _popAt[i - 1];
      if (ms < at) return;
      // Pops past full size on back.out, then settles.
      final p = _seg(ms, at, at + _popFor);
      appear = p < 1 ? backOut3.transform(p) : 1;
      _sparkleBurst(canvas, home, radius, _seg(ms, at, at + 240));
    }

    // Flying.
    final leave = _leave(i);
    final f = _seg(ms, leave, leave + _flight);
    if (f >= 1) {
      _absorb(
        canvas,
        l.entry(i),
        radius,
        _seg(ms, leave + _flight, leave + _flight + 140),
      );
      return;
    }

    final entry = l.entry(i);
    Offset at(double p) => _arc(home, entry, p);
    final pos = f == 0 ? home : at(Curves.easeIn.transform(f));

    // A short trail behind a coin in flight.
    if (f > 0) {
      for (var k = 1; k <= 3; k++) {
        final back = (f - 0.07 * k).clamp(0.0, 1.0);
        final ghost = at(Curves.easeIn.transform(back));
        canvas.drawCircle(
          ghost,
          radius * (0.75 - 0.15 * k),
          Paint()..color = _gold.withValues(alpha: 0.22 / k),
        );
      }
    }

    // At the wallet's edge it shrinks fast into the light.
    final shrink = f < 0.72
        ? 1.0
        : 1 - Curves.easeIn.transform((f - 0.72) / 0.28);
    final opacity = isSpark ? appear : (appear.clamp(0.0, 1.0));
    _coin(canvas, pos, radius * appear * shrink, spin, opacity);
  }

  /// A parabola from [from] to [to], rising a little first so the coins arc
  /// into the wallet rather than dropping straight in.
  Offset _arc(Offset from, Offset to, double p) {
    final x = from.dx + (to.dx - from.dx) * p;
    final lift = (to.dy - from.dy).abs() * 0.35 + 18;
    final y = from.dy + (to.dy - from.dy) * p - 4 * lift * p * (1 - p);
    return Offset(x, y);
  }

  /// A gold coin with an embossed star, turning on its vertical axis.
  void _coin(Canvas canvas, Offset c, double r, double spin, double opacity) {
    if (r <= 0.3 || opacity <= 0) return;
    // Turning on the vertical axis: the face narrows edge-on and widens again.
    final face = 0.2 + 0.8 * math.cos(spin).abs();
    final rect = Rect.fromCenter(center: c, width: r * 2 * face, height: r * 2);
    final a = opacity.clamp(0.0, 1.0);

    canvas.drawOval(
      rect.inflate(1.5),
      Paint()..color = _deepGold.withValues(alpha: a),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [
            const Color(0xFFFFF4B0).withValues(alpha: a),
            _gold.withValues(alpha: a),
            _amber.withValues(alpha: a),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(rect),
    );

    // The embossed star: a darker shape with a lighter edge above it.
    final star = _starPath(c, r * 0.46, face);
    canvas.drawPath(
      star.shift(const Offset(0, 0.8)),
      Paint()..color = _deepGold.withValues(alpha: 0.55 * a),
    );
    canvas.drawPath(
      star,
      Paint()..color = const Color(0xFFFFE680).withValues(alpha: 0.9 * a),
    );

    // The catch of the light as it turns.
    final shine = math.sin(spin).abs();
    canvas.drawOval(
      Rect.fromCenter(
        center: c + Offset(-r * 0.25 * face, -r * 0.35),
        width: r * 0.5 * face,
        height: r * 0.28,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.35 * shine * a),
    );
  }

  Path _starPath(Offset c, double r, double squeeze) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.45;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(
        c.dx + math.cos(angle) * radius * squeeze,
        c.dy + math.sin(angle) * radius,
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  /// Tiny gold sparks thrown out as a coin appears.
  void _sparkleBurst(Canvas canvas, Offset c, double r, double p) {
    if (p <= 0 || p >= 1) return;
    final eased = Curves.easeOut.transform(p);
    final paint = Paint()..color = _gold.withValues(alpha: 1 - p);
    for (var k = 0; k < 6; k++) {
      final angle = k * math.pi / 3 + 0.4;
      final at =
          c + Offset(math.cos(angle), math.sin(angle)) * (r + r * 1.4 * eased);
      canvas.drawCircle(at, 1.8 * (1 - p) + 0.4, paint);
    }
  }

  /// A coin that has reached the wallet, dissolving into light that is drawn
  /// down into the glass.
  void _absorb(Canvas canvas, Offset at, double r, double p) {
    if (p <= 0 || p >= 1) return;
    final paint = Paint()
      ..color = const Color(0xFFFFE680).withValues(alpha: 1 - p);
    for (var k = 0; k < 5; k++) {
      final angle = math.pi * (0.15 + 0.7 * k / 4);
      final spread = r * 0.9 * (1 - p);
      final down = r * 1.2 * Curves.easeIn.transform(p);
      final pos = at + Offset(math.cos(angle) * spread, down);
      canvas.drawCircle(pos, 1.6 * (1 - p) + 0.5, paint);
    }
  }

  /// The last ring of sparkles around the total, expanding and fading.
  void _finalRing(Canvas canvas, _Layout l) {
    final p = _seg(ms, 880, 1000);
    if (p <= 0 || p >= 1) return;
    final c = l.wallet.center + Offset(0, l.wallet.height * 0.08);
    final eased = Curves.easeOut.transform(p);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9 * (1 - p));
    for (var k = 0; k < 12; k++) {
      final angle = k * math.pi / 6;
      final reach = l.w * (0.12 + 0.16 * eased);
      final pos =
          c + Offset(math.cos(angle) * reach, math.sin(angle) * reach * 0.55);
      canvas.drawCircle(pos, 1.7 * (1 - p) + 0.3, paint);
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.ms != ms || old.shimmer != shimmer || old.reduced != reduced;
}

/// "1,000", rising out of the wallet.
class _Total extends StatelessWidget {
  const _Total({
    super.key,
    required this.size,
    required this.ms,
    required this.reduced,
    required this.text,
  });

  final Size size;
  final double ms;
  final bool reduced;
  final String text;

  @override
  Widget build(BuildContext context) {
    final l = _Layout(size);

    // From 80% and 60% opacity to full, starting as the last coin lands.
    final p = reduced
        ? Curves.easeOut.transform(_seg(ms, 0, 1000))
        : _seg(ms, 800, 950);
    if (p <= 0) return const SizedBox.shrink();
    final eased = Curves.easeOutCubic.transform(p);
    final scale = 0.8 + 0.2 * eased;
    final opacity = 0.6 + 0.4 * eased;
    // A single breath as it locks into place.
    final breath = reduced
        ? 0.0
        : math.sin(math.pi * _seg(ms, 880, 1000)) * 0.045;

    return Positioned.fromRect(
      rect: Rect.fromCenter(
        center: l.wallet.center + Offset(0, l.wallet.height * 0.08),
        width: l.wallet.width,
        height: l.wallet.height * 0.7,
      ),
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          key: const ValueKey('wallet-total-scale'),
          scale: scale + breath,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              style: TextStyle(
                fontSize: l.w * 0.13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: const Color(0xFFFFE9A8),
                height: 1,
                shadows: const [
                  Shadow(color: Color(0x99FFB300), blurRadius: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewTag extends StatelessWidget {
  const _PreviewTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Preview',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.8),
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}
