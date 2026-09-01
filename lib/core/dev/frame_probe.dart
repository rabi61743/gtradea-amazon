import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Reports how long frames actually take, from inside the engine.
///
/// This exists because the obvious Android tools cannot see a Flutter app.
/// Flutter renders into a `SurfaceView`, which bypasses HWUI entirely, so
/// `dumpsys gfxinfo` reports zero frames for it -- and on Android 16
/// `dumpsys SurfaceFlinger --latency` no longer returns per-frame rows either.
/// Any number read from those about a Flutter app is measuring the platform's
/// own decor, not the app.
///
/// `addTimingsCallback` is the engine's own accounting and splits the two
/// halves that matter:
///
///   * **build** -- the UI thread: widget builds, layout, and any Dart work
///     that ran in the frame. This is where an over-eager `setState`, a large
///     `jsonDecode` or twenty thousand widgets show up.
///   * **raster** -- the GPU thread: turning the layer tree into pixels. Heavy
///     images, shaders and overdraw show up here.
///
/// Knowing which of the two is over budget is the difference between fixing the
/// right thing and guessing.
///
/// Profile builds only, and no-op elsewhere: the callback itself is cheap, but
/// logging every frame in release would not be.
abstract final class FrameProbe {
  static bool _started = false;

  /// Frames seen since the last report.
  static final _build = <int>[];
  static final _raster = <int>[];

  /// How many frames to gather before printing a summary. About two seconds of
  /// scrolling at 120Hz, which is long enough to be representative and short
  /// enough to line up with what you just did on screen.
  static const _batch = 240;

  /// Starts reporting. Safe to call more than once.
  static void start() {
    // Not in a shipped build. Everywhere else it reports, so the same binary
    // can be checked in debug and profile and the two compared.
    if (_started || kReleaseMode) return;
    _started = true;

    // Called before runApp, so the binding does not exist yet. Reaching for
    // `WidgetsBinding.instance` first would throw.
    WidgetsFlutterBinding.ensureInitialized();

    // Says so on startup, so "no output" can be told apart from "no jank".
    debugPrint(
      '[frames] probe on -- profile=$kProfileMode debug=$kDebugMode, '
      'reporting every $_batch frames',
    );

    WidgetsBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        _build.add(timing.buildDuration.inMicroseconds);
        _raster.add(timing.rasterDuration.inMicroseconds);
      }
      if (_build.length >= _batch) _report();
    });
  }

  static void _report() {
    final build = [..._build]..sort();
    final raster = [..._raster]..sort();
    _build.clear();
    _raster.clear();

    // The budget is the display's, not a hardcoded 16ms. A 120Hz phone gives a
    // frame 8.3ms, and calling 12ms "fine" on one of those is how jank gets
    // measured as smooth.
    final hz = WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .display
        .refreshRate;
    final budgetUs = (1000000 / hz).round();

    final over = [
      for (var i = 0; i < build.length; i++)
        if (build[i] + raster[i] > budgetUs) i,
    ].length;

    // debugPrint, not developer.log: `dart:developer` writes to the VM service,
    // which nothing is attached to here, so it never reaches logcat in a
    // profile build. print does.
    debugPrint(
      '[frames] frames=${build.length} budget=${_ms(budgetUs)} '
      '(${hz.toStringAsFixed(0)}Hz) over=$over '
      '(${(over * 100 / build.length).toStringAsFixed(0)}%)  '
      'build p50=${_ms(_pct(build, 50))} p90=${_ms(_pct(build, 90))} '
      'p99=${_ms(_pct(build, 99))}  '
      'raster p50=${_ms(_pct(raster, 50))} p90=${_ms(_pct(raster, 90))} '
      'p99=${_ms(_pct(raster, 99))}',
    );
  }

  static int _pct(List<int> sorted, int percentile) {
    if (sorted.isEmpty) return 0;
    final index = ((percentile / 100) * (sorted.length - 1)).round();
    return sorted[index];
  }

  static String _ms(int micros) => '${(micros / 1000).toStringAsFixed(1)}ms';
}
