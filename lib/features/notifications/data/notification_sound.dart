import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../core/audio/sound_settings.dart';

/// The chime that plays when something new arrives.
///
/// Played through `video_player`, which this app already carries for product
/// videos and which plays an audio-only asset perfectly well. Flutter's own
/// [SystemSound] was the obvious candidate and is not one: its `alert` is
/// documented as ignored on Android and iOS, so it would have made no sound at
/// all on the devices this ships to. Reusing a dependency that is already here
/// beats adding one for a quarter of a second of audio.
///
/// Everything here fails silently. A notification that arrives is the point; a
/// device that will not play a sound -- silent mode, an audio focus refusal, a
/// codec that will not open -- must not cost the shopper the notification.
class NotificationSound {
  NotificationSound._();

  static final NotificationSound instance = NotificationSound._();

  static const _asset = 'assets/sounds/notification.wav';

  /// Off in tests: a widget test has no audio device, and initialising a
  /// player would leave a pending platform call that fails the test for a
  /// reason unrelated to what it was checking.
  @visibleForTesting
  static bool enabled = true;

  /// Counts plays, so a test can assert the sound happened without listening
  /// for one.
  @visibleForTesting
  static int plays = 0;

  VideoPlayerController? _player;
  Future<void>? _loading;

  /// True while a chime is already sounding.
  ///
  /// Ten notifications arriving together should be one chime and not ten, and
  /// the caller already batches them -- this is the second guard, for the case
  /// where two batches land within a few hundred milliseconds of each other.
  bool _sounding = false;

  /// The earliest the next chime may sound.
  DateTime _nextAllowed = DateTime.fromMillisecondsSinceEpoch(0);

  /// A quiet window after each chime. Long enough that a burst of arrivals is
  /// one sound, short enough that a genuinely separate event still gets its
  /// own.
  static const _gap = Duration(seconds: 3);

  Future<void> _ensureLoaded() {
    final existing = _player;
    if (existing != null) return Future<void>.value();
    return _loading ??= () async {
      try {
        final player = VideoPlayerController.asset(_asset);
        await player.initialize();
        await player.setVolume(1);
        _player = player;
      } catch (_) {
        // No audio on this device, or the asset would not open. The app goes
        // on being silent, which is the correct failure.
      } finally {
        _loading = null;
      }
    }();
  }

  /// Plays the chime, unless one has just played.
  ///
  /// Never awaited by callers, and never throws.
  Future<void> play() async {
    // The shopper's one sound switch governs this too. "Sound off" that still
    // chimes is not sound off.
    if (!enabled || !SoundSettings.instance.enabled) return;

    final now = DateTime.now();
    if (_sounding || now.isBefore(_nextAllowed)) return;
    _sounding = true;
    _nextAllowed = now.add(_gap);
    plays += 1;

    try {
      await _ensureLoaded();
      final player = _player;
      if (player == null) return;
      // Rewound first: a controller left at the end plays nothing.
      await player.seekTo(Duration.zero);
      await player.play();
    } catch (_) {
      // See the class doc: silence is an acceptable outcome, a crash is not.
    } finally {
      _sounding = false;
    }
  }

  @visibleForTesting
  Future<void> resetForTest() async {
    plays = 0;
    _sounding = false;
    _nextAllowed = DateTime.fromMillisecondsSinceEpoch(0);
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}
