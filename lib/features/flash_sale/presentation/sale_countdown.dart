import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../data/flash_sale.dart';

/// How a countdown is drawn.
enum CountdownStyle {
  /// Four labelled cells, for a block that has the width for them.
  panel,

  /// One pill, for a heading row.
  strip,
}

/// A live countdown to a deadline.
///
/// Ticks once a second and recomputes from the wall clock every time, rather
/// than subtracting a second from a running total. The difference matters: a
/// decrementing counter drifts as timer callbacks slip, and it stops entirely
/// while the app is backgrounded -- so a shopper who returns after lunch is
/// shown a confident, wrong number. Reading the clock is right on the first
/// frame after a resume and needs no lifecycle handling at all.
///
/// Calls [onEnded] once, the moment it reaches zero, so the section around it
/// can swap to its ended state without polling.
class SaleCountdown extends StatefulWidget {
  const SaleCountdown({
    super.key,
    required this.endsAt,
    this.onEnded,
    this.compact = false,
    this.boxed = false,
    this.onLight = false,
    this.style = CountdownStyle.panel,
    this.now,
  });

  final DateTime endsAt;

  /// Fired once when the deadline passes while this widget is on screen.
  final VoidCallback? onEnded;

  /// Smaller cells, for the narrow layout.
  final bool compact;

  /// Each figure in its own box, for sitting on a band where plain digits would
  /// have to fight the background for contrast.
  final bool boxed;

  /// Boxed, but on a light card rather than a coloured band.
  ///
  /// Only the parts that were painted white move: the unit labels and the
  /// colons, which are invisible on a white surface, and the boxes themselves,
  /// which are white and would vanish into it. The digits are already the
  /// accent red and stay exactly as they are.
  final bool onLight;

  /// Which shape to draw.
  ///
  /// [CountdownStyle.strip] exists because the panel one does not survive being
  /// put in a header row: four labelled cells is eleven pieces of text, and
  /// squeezing that beside a title and a button shrank the digits until nobody
  /// could read them. The strip is the same clock in a shape that fits.
  final CountdownStyle style;

  /// The clock, injectable so a test can decide what time it is.
  final DateTime Function()? now;

  @override
  State<SaleCountdown> createState() => _SaleCountdownState();
}

class _SaleCountdownState extends State<SaleCountdown> {
  Timer? _timer;
  late Duration _remaining;
  bool _announced = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _remaining = _left();
    // Only run a timer if there is something to count. A sale that is already
    // over does not need a ticker waking the device every second.
    if (_remaining > Duration.zero) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _announceEnded();
    }
  }

  @override
  void didUpdateWidget(SaleCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new sale in the same slot: start again rather than counting down to
    // the previous one's deadline.
    if (oldWidget.endsAt != widget.endsAt) {
      _announced = false;
      _timer?.cancel();
      _remaining = _left();
      if (_remaining > Duration.zero) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration _left() {
    final left = widget.endsAt.difference(_now);
    return left.isNegative ? Duration.zero : left;
  }

  void _tick() {
    if (!mounted) return;
    final left = _left();

    // Whole seconds only. Rebuilding when nothing visible changed is a frame
    // spent for nothing, and this sits on the home page.
    if (left.inSeconds != _remaining.inSeconds) {
      setState(() => _remaining = left);
    }

    if (left <= Duration.zero) {
      _timer?.cancel();
      _announceEnded();
    }
  }

  void _announceEnded() {
    if (_announced) return;
    _announced = true;
    final ended = widget.onEnded;
    if (ended == null) return;
    // After the frame: this can fire from initState, and a parent calling
    // setState while it is still building is an assertion rather than a
    // warning.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ended();
    });
  }

  @override
  Widget build(BuildContext context) {
    final parts = CountdownParts.from(_remaining);

    // All four units, always, so the countdown reads the same whether the sale
    // is three days out or three minutes. It used to drop the days cell when it
    // was zero, which kept a short sale tighter but meant the row silently
    // changed shape as one ticked over into the other.
    final cells = <(String, String)>[
      (parts.two(parts.days), 'Days'),
      (parts.two(parts.hours), 'Hrs'),
      (parts.two(parts.minutes), 'Mins'),
      (parts.two(parts.seconds), 'Secs'),
    ];

    return Semantics(
      liveRegion: true,
      label: _spoken(parts),
      // The cells are decoration once the whole thing is announced as one
      // phrase -- a screen reader reading "02, Hrs, 35, Mins" every second is
      // unusable.
      excludeSemantics: true,
      child: switch (widget.style) {
        CountdownStyle.strip => _Strip(cells: cells),
        CountdownStyle.panel => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0)
                _Separator(
                  compact: widget.compact,
                  onColour: widget.boxed && !widget.onLight,
                ),
              _Cell(
                value: cells[i].$1,
                label: cells[i].$2,
                compact: widget.compact,
                boxed: widget.boxed,
                onLight: widget.onLight,
              ),
            ],
          ],
        ),
      },
    );
  }

  String _spoken(CountdownParts parts) {
    if (parts.isZero) return 'This sale has ended';
    final said = <String>[
      if (parts.days > 0) '${parts.days} days',
      if (parts.hours > 0) '${parts.hours} hours',
      if (parts.minutes > 0) '${parts.minutes} minutes',
      // Seconds only on the last stretch. Otherwise every announcement changes
      // and the reader never stops talking.
      if (parts.days == 0 && parts.hours == 0 && parts.minutes == 0)
        '${parts.seconds} seconds',
    ];
    return 'Sale ends in ${said.join(', ')}';
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.value,
    required this.label,
    required this.compact,
    this.boxed = false,
    this.onLight = false,
  });

  final String value;
  final String label;
  final bool compact;
  final bool boxed;
  final bool onLight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final digits = Text(
      value,
      style: (compact ? theme.textTheme.titleMedium : theme.textTheme.titleLarge)
          ?.copyWith(
            fontWeight: FontWeight.w800,
            color: boxed ? AppColors.accent : theme.colorScheme.error,
            height: 1.05,
            // Tabular figures, or the row jitters sideways every second as the
            // glyph widths change.
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (boxed)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              // A white box disappears into a white card, so on a light ground
              // the box is the tint and the card is the white.
              color: onLight
                  ? theme.colorScheme.surfaceContainerHighest
                  : Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              // Lifted off the panel behind it, matching the rest of the
              // card's furniture. Only where the box is drawn on a dark
              // ground: on a light card the box is already the tinted thing
              // and a shadow under it would be grubby rather than raised.
              boxShadow: onLight
                  ? null
                  : const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 6,
                        offset: Offset(1, 2),
                      ),
                    ],
            ),
            child: digits,
          )
        else
          digits,
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: boxed && !onLight
                ? Colors.white.withValues(alpha: 0.9)
                : theme.colorScheme.onSurfaceVariant,
            fontSize: compact ? 9 : 10,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.compact, this.onColour = false});

  final bool compact;
  final bool onColour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 9),
      child: Padding(
        // Nudged up so the colon sits against the digits rather than centred
        // against the digits-plus-label block.
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          ':',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: compact ? 15 : 18,
            color: onColour
                ? Colors.white.withValues(alpha: 0.8)
                : Theme.of(context).colorScheme.error.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

/// The countdown as a single pill, for a header bar.
///
/// Four labelled cells needed a block's worth of width, and four separate
/// chips were not much better: each one paid for its own padding, so the clock
/// came to 263 logical pixels and got scaled down to 81% on a 360-wide phone --
/// the same unreadable digits in a new shape. One pill pays that cost once.
///
/// The clock face is a single line of text rather than a row of widgets, so
/// there is nothing between the figures to space out, and the units are
/// single letters set small and dimmed: enough to say which number is which
/// without spending a word's width on each.
class _Strip extends StatelessWidget {
  const _Strip({required this.cells});

  /// Value and label, in order, as the parent already worked them out.
  final List<(String, String)> cells;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final digits = theme.textTheme.labelLarge?.copyWith(
      color: AppColors.onPrimary,
      fontWeight: FontWeight.w800,
      height: 1.0,
      // Tabular, or the pill jitters sideways every second as the glyph
      // widths change.
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final unit = digits?.copyWith(
      fontSize: 9,
      fontWeight: FontWeight.w600,
      color: AppColors.onPrimary.withValues(alpha: 0.72),
    );
    final divider = digits?.copyWith(
      color: AppColors.onPrimary.withValues(alpha: 0.45),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
      decoration: BoxDecoration(
        // Solid Trust Blue, because this now sits on the sale panel's warm
        // tint rather than on a coloured band. It used to be a translucent
        // wash of its own white, which only worked while the thing behind it
        // was dark -- on a light panel that is white text on very slightly
        // tinted white.
        color: AppColors.trustBlueDeep,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: 13,
            color: AppColors.onPrimary.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 5),
          Text.rich(
            TextSpan(
              children: [
                for (var i = 0; i < cells.length; i++) ...[
                  // No spaces around the colon. Padded separators cost a
                  // third of the pill's width for punctuation.
                  if (i > 0) TextSpan(text: ':', style: divider),
                  TextSpan(text: cells[i].$1, style: digits),
                  TextSpan(text: cells[i].$2[0].toLowerCase(), style: unit),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
