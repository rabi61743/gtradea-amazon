import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'size_guide_sheet.dart';

/// A shopper's body measurements, in centimetres.
@immutable
class BodyMeasurements {
  const BodyMeasurements({required this.bust, required this.waist});

  final double bust;
  final double waist;

  /// What the rulers start on before anything has been saved.
  static const initial = BodyMeasurements(bust: 96, waist: 82);
}

/// Where the measurements are kept: on this device, and nowhere else.
///
/// There is no endpoint for them, so nothing is sent. Signing out, another
/// account on the same phone, or reinstalling the app all see what this phone
/// last saved -- said on the page, so nobody expects them to follow an account.
class BodyMeasurementsStore {
  BodyMeasurementsStore._();

  static final instance = BodyMeasurementsStore._();

  static const _bustKey = 'gtradea_size_bust_cm';
  static const _waistKey = 'gtradea_size_waist_cm';

  /// What was last saved on this device, or null if nothing was.
  Future<BodyMeasurements?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final bust = prefs.getDouble(_bustKey);
    final waist = prefs.getDouble(_waistKey);
    if (bust == null || waist == null) return null;
    return BodyMeasurements(bust: bust, waist: waist);
  }

  Future<void> save(BodyMeasurements m) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_bustKey, m.bust);
    await prefs.setDouble(_waistKey, m.waist);
  }
}

/// Which standard size a measurement falls in, and whether it was off the
/// ends of the chart.
@immutable
class SizeFit {
  const SizeFit({required this.index, this.below = false, this.above = false});

  final int index;
  final bool below;
  final bool above;

  StandardSize get size => kStandardSizes[index];
}

/// The standard size for [cm] on one body measurement.
///
/// Inside a size's range, that size. Between two ranges -- the chart leaves a
/// centimetre between one size's top and the next one's bottom -- the larger,
/// because a garment a little loose can be worn and one a little tight
/// cannot. Off either end, the end, flagged.
SizeFit fitFor(double cm, (double, double) Function(StandardSize) range) {
  for (var i = 0; i < kStandardSizes.length; i++) {
    final (from, to) = range(kStandardSizes[i]);
    if (cm < from) {
      return i == 0 ? const SizeFit(index: 0, below: true) : SizeFit(index: i);
    }
    if (cm <= to) return SizeFit(index: i);
  }
  return SizeFit(index: kStandardSizes.length - 1, above: true);
}

/// The suggestion for a pair of measurements: each one's fit, and the size
/// to take -- the larger of the two, so neither measurement is squeezed.
@immutable
class SizeRecommendation {
  const SizeRecommendation({required this.bust, required this.waist});

  factory SizeRecommendation.forMeasurements(BodyMeasurements m) =>
      SizeRecommendation(
        bust: fitFor(m.bust, (s) => s.chest),
        waist: fitFor(m.waist, (s) => s.waist),
      );

  final SizeFit bust;
  final SizeFit waist;

  int get index => bust.index > waist.index ? bust.index : waist.index;
  StandardSize get size => kStandardSizes[index];
}

/// The Size recommendation tab.
class SizeRecommendationTab extends StatefulWidget {
  const SizeRecommendationTab({super.key, required this.onViewSize});

  /// Opens the Size guide tab on a standard size.
  final ValueChanged<int> onViewSize;

  @override
  State<SizeRecommendationTab> createState() => _SizeRecommendationTabState();
}

enum _RecUnit { inches, cm }

class _SizeRecommendationTabState extends State<SizeRecommendationTab> {
  static const _orange = SizeGuideSheet.accent;

  _RecUnit _unit = _RecUnit.cm;
  BodyMeasurements _m = BodyMeasurements.initial;
  SizeRecommendation? _result;
  bool _loaded = false;

  /// The measurements [_result] was worked out from.
  BodyMeasurements? _submitted;

  /// Shows "Saved" on the button for a moment after Submit.
  bool _justSaved = false;
  Timer? _savedTimer;

  /// Bumped on every Submit, so the card flashes even when the size is the
  /// same as before -- otherwise a second Submit looks like it did nothing.
  int _flash = 0;

  /// The rulers have moved since the suggestion was worked out.
  bool get _changed =>
      _submitted != null &&
      (_submitted!.bust != _m.bust || _submitted!.waist != _m.waist);
  final _resultKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    BodyMeasurementsStore.instance.load().then((saved) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        if (saved != null) {
          _m = saved;
          // Measured before: the suggestion is there again on opening.
          _result = SizeRecommendation.forMeasurements(saved);
          _submitted = saved;
        }
      });
    });
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    await BodyMeasurementsStore.instance.save(_m);
    if (!mounted) return;
    final submitted = _m;
    setState(() {
      _result = SizeRecommendation.forMeasurements(submitted);
      _submitted = submitted;
      _justSaved = true;
      _flash++;
    });
    _savedTimer?.cancel();
    _savedTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _justSaved = false);
    });
    // On a phone the answer lands below the fold: bring it up to the shopper.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _resultKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.5,
        );
      }
    });
  }

  String _show(double cm) => _unit == _RecUnit.cm
      ? '${cm.round()} cm'
      : '${(cm / 2.54).toStringAsFixed(1)} in';

  String _range((double, double) r) => _unit == _RecUnit.cm
      ? '${r.$1.round()}–${r.$2.round()} cm'
      : '${(r.$1 / 2.54).toStringAsFixed(1)}–'
            '${(r.$2 / 2.54).toStringAsFixed(1)} in';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('size-recommendation-scroll'),
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.swipe, color: _orange, size: 22),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Swipe to add your body information',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: _orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'We save it on this device to suggest a standard size '
                      'next time. It is not sent anywhere.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _RecUnitToggle(
                        unit: _unit,
                        onChanged: (u) => setState(() => _unit = u),
                      ),
                    ),
                  ],
                ),
              ),
              _Measure(
                label: 'Bust size',
                keyName: 'bust',
                cm: _m.bust,
                minCm: 60,
                maxCm: 150,
                inches: _unit == _RecUnit.inches,
                display: _show(_m.bust),
                onChanged: (v) => setState(
                  () => _m = BodyMeasurements(bust: v, waist: _m.waist),
                ),
              ),
              _Measure(
                label: 'Waist size',
                keyName: 'waist',
                cm: _m.waist,
                minCm: 50,
                maxCm: 140,
                inches: _unit == _RecUnit.inches,
                display: _show(_m.waist),
                onChanged: (v) => setState(
                  () => _m = BodyMeasurements(bust: _m.bust, waist: v),
                ),
              ),
              if (_result != null)
                _Result(
                  key: _resultKey,
                  result: _result!,
                  stale: _changed,
                  flash: _flash,
                  range: _range,
                  onView: () => widget.onViewSize(_result!.index),
                ),
              Container(
                height: 8,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              const _HowToMeasure(),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              Text(
                'By tapping Submit you save these measurements on this device '
                'to get a size suggestion from a general size chart.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  key: const ValueKey('size-recommendation-submit'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: _submit,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _justSaved && !_changed
                        ? Row(
                            key: const ValueKey('saved'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Saved',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'Submit',
                            key: const ValueKey('submit'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecUnitToggle extends StatelessWidget {
  const _RecUnitToggle({required this.unit, required this.onChanged});

  final _RecUnit unit;
  final ValueChanged<_RecUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget half(String text, _RecUnit value) {
      final on = unit == value;
      return InkWell(
        key: ValueKey('rec-unit-${value.name}'),
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: on ? SizeGuideSheet.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              color: on ? Colors.white : theme.colorScheme.onSurface,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [half('IN', _RecUnit.inches), half('CM', _RecUnit.cm)],
      ),
    );
  }
}

/// One measurement: its name, the value in a box, and a ruler to swipe.
class _Measure extends StatelessWidget {
  const _Measure({
    required this.label,
    required this.keyName,
    required this.cm,
    required this.minCm,
    required this.maxCm,
    required this.inches,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final String keyName;
  final double cm;
  final double minCm;
  final double maxCm;
  final bool inches;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: theme.textTheme.titleMedium),
                ),
                Container(
                  key: ValueKey('measure-$keyName-value'),
                  width: 120,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Text(display, style: theme.textTheme.titleMedium),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
          const SizedBox(height: 6),
          RulerPicker(
            key: ValueKey('ruler-$keyName'),
            cm: cm,
            minCm: minCm,
            maxCm: maxCm,
            inches: inches,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// A horizontal ruler that scrolls under a fixed orange pointer.
///
/// The value is always held in centimetres. In centimetres a tick is one
/// centimetre, labelled every two; in inches a tick is half an inch, labelled
/// every inch -- so the ruler reads in the unit the switch shows, and a
/// shopper measuring in inches is not converting in their head.
class RulerPicker extends StatefulWidget {
  const RulerPicker({
    super.key,
    required this.cm,
    required this.minCm,
    required this.maxCm,
    required this.inches,
    required this.onChanged,
  });

  final double cm;
  final double minCm;
  final double maxCm;
  final bool inches;
  final ValueChanged<double> onChanged;

  /// Spacing between ticks, in logical pixels.
  static const tickGap = 14.0;

  @override
  State<RulerPicker> createState() => _RulerPickerState();
}

class _RulerPickerState extends State<RulerPicker> {
  late ScrollController _scroll = ScrollController(
    initialScrollOffset: _offsetFor(widget.cm),
  );

  /// Whether the scroll in progress began with the shopper's finger.
  bool _dragging = false;

  /// One tick in centimetres.
  double get _step => widget.inches ? 1.27 : 1.0;

  double get _min => widget.inches
      ? (widget.minCm / 2.54).ceilToDouble() * 2.54
      : widget.minCm;

  int get _ticks => ((widget.maxCm - _min) / _step).floor() + 1;

  double _offsetFor(double cm) =>
      ((cm - _min) / _step).clamp(0, _ticks - 1) * RulerPicker.tickGap;

  @override
  void didUpdateWidget(RulerPicker old) {
    super.didUpdateWidget(old);
    if (old.inches != widget.inches) {
      // A different ruler: start again on the same value.
      final previous = _scroll;
      _scroll = ScrollController(initialScrollOffset: _offsetFor(widget.cm));
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll(ScrollMetrics metrics) {
    final tick = (metrics.pixels / RulerPicker.tickGap).round().clamp(
      0,
      _ticks - 1,
    );
    final cm = _min + tick * _step;
    if ((cm - widget.cm).abs() <= 0.01) return;

    // A ruler rebuilt for the other unit reports its position while it is
    // still being laid out, and a setState from inside a layout is a build
    // scheduled during the frame -- which froze the value on the old unit.
    // Mid-frame, the change waits for the frame to finish.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      widget.onChanged(cm);
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(cm);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final half = constraints.maxWidth / 2;
        return SizedBox(
          height: 78,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.axis != Axis.horizontal) return false;
                  // Only a finger changes the value. A ruler rebuilt for the
                  // other unit snaps to its nearest tick, and that must not
                  // quietly turn 96 cm into 96.5.
                  if (n is ScrollStartNotification && n.dragDetails != null) {
                    _dragging = true;
                  }
                  if (!_dragging) return false;
                  if (n is ScrollUpdateNotification) _onScroll(n.metrics);
                  if (n is ScrollEndNotification) {
                    _onScroll(n.metrics);
                    _dragging = false;
                  }
                  return false;
                },
                child: ListView.builder(
                  key: ValueKey('ruler-list-${widget.inches}'),
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  physics: const _SnapToTick(),
                  padding: EdgeInsets.symmetric(horizontal: half),
                  itemExtent: RulerPicker.tickGap,
                  itemCount: _ticks,
                  itemBuilder: (context, i) {
                    final major = i.isEven;
                    final cm = _min + i * _step;
                    final label = widget.inches
                        ? (cm / 2.54).round().toString()
                        : cm.round().toString();
                    return OverflowBox(
                      maxWidth: 40,
                      alignment: Alignment.topCenter,
                      child: Column(
                        children: [
                          const SizedBox(height: 22),
                          Container(
                            width: 1,
                            height: major ? 24 : 14,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 6),
                          if (major)
                            Text(
                              label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // The baseline across the ruler, and the pointer on the value.
              Positioned(
                top: 22,
                left: 0,
                right: 0,
                child: Container(
                  height: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
              IgnorePointer(
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surface,
                        border: Border.all(
                          color: SizeGuideSheet.accent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    Container(
                      width: 2.5,
                      height: 22,
                      color: SizeGuideSheet.accent,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Settles the ruler on a whole tick, so the pointer never rests between two.
class _SnapToTick extends ScrollPhysics {
  const _SnapToTick({super.parent});

  @override
  _SnapToTick applyTo(ScrollPhysics? ancestor) =>
      _SnapToTick(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final simulation = super.createBallisticSimulation(position, velocity);
    final end = simulation?.x(double.infinity) ?? position.pixels;
    final target = (end / RulerPicker.tickGap).round() * RulerPicker.tickGap;
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clamped - position.pixels).abs() < 0.5 && velocity.abs() < 1) {
      return null;
    }
    return ScrollSpringSimulation(
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 100, ratio: 1),
      position.pixels,
      clamped,
      velocity,
      tolerance: toleranceFor(position),
    );
  }
}

/// The suggestion, and how it was reached.
class _Result extends StatelessWidget {
  const _Result({
    super.key,
    required this.result,
    required this.range,
    required this.onView,
    this.stale = false,
    this.flash = 0,
  });

  final SizeRecommendation result;

  /// The rulers have moved since: the card fades and says to Submit again.
  final bool stale;

  /// Changes on every Submit, replaying the highlight.
  final int flash;
  final String Function((double, double)) range;
  final VoidCallback onView;

  String _note(String name, SizeFit fit, (double, double) r) {
    final where = fit.below
        ? 'below the smallest standard size'
        : fit.above
        ? 'above the largest standard size'
        : 'fits ${fit.size.label} (${range(r)})';
    return '$name $where';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disagree = result.bust.index != result.waist.index;

    final card = TweenAnimationBuilder<double>(
      key: ValueKey('size-recommendation-flash-$flash'),
      // Starts bright and settles, each time Submit is tapped.
      tween: Tween(begin: flash == 0 ? 0 : 1, end: 0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      builder: (context, t, child) => Container(
        key: const ValueKey('size-recommendation-result'),
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SizeGuideSheet.accent.withValues(alpha: 0.07 + 0.18 * t),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: SizeGuideSheet.accent.withValues(alpha: 0.35 + 0.65 * t),
            width: 1 + t,
          ),
        ),
        child: child,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Your standard size: '),
                TextSpan(
                  text: result.size.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: SizeGuideSheet.accent,
                  ),
                ),
              ],
            ),
            key: const ValueKey('size-recommendation-size'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            '${_note('Bust', result.bust, result.bust.size.chest)}; '
            '${_note('waist', result.waist, result.waist.size.waist)}.'
            '${disagree ? ' The larger is suggested, so neither feels tight.' : ''}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'From a general size chart, not this product\'s. The seller\'s '
            'sizes may differ -- check their size chart in the photos too.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const ValueKey('size-recommendation-view'),
            onPressed: onView,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: SizeGuideSheet.accent,
            ),
            child: Text('See ${result.size.label} in the size guide ›'),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stale)
          Padding(
            key: const ValueKey('size-recommendation-stale'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.refresh,
                  size: 18,
                  color: SizeGuideSheet.accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Measurements changed. Tap Submit to update your size.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: SizeGuideSheet.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        AnimatedOpacity(
          opacity: stale ? 0.45 : 1,
          duration: const Duration(milliseconds: 200),
          child: card,
        ),
      ],
    );
  }
}

class _HowToMeasure extends StatelessWidget {
  const _HowToMeasure();

  static const _steps = [
    ('Bust', 'Measure the circumference of the fullest part of your bust.'),
    ('Waist', 'Measure the thinnest part of your waist.'),
    ('Hips', 'Measure the fullest part of your hips.'),
    ('Height', 'Measure your height from the top of your head to the floor.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How to measure?', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 11,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _steps.length; i++) ...[
                      Text(
                        '${i + 1}. ${_steps[i].$1}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(_steps[i].$2, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(flex: 9, child: MeasureFigure()),
            ],
          ),
        ],
      ),
    );
  }
}
