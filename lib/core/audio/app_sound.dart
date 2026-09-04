import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'sound_settings.dart';

/// A short sound effect, played from a bundled asset.
///
/// Played through `video_player`, which this app already carries for product
/// videos and which plays an audio-only asset perfectly well. Flutter's own
/// [SystemSound] was the obvious candidate and is not one: its `alert` is
/// documented as ignored on Android and iOS, so it would have made no sound at
/// all on the devices this ships to. Reusing a dependency that is already here
/// beats adding one for a quarter of a second of audio.
///
/// **Everything here fails silently.** The action that triggered the sound is
/// the point; a device that will not play one -- silent mode, an audio focus
/// refusal, a codec that will not open -- must not cost the shopper that
/// action, and must not put an error in front of them either.
class AppSound {
  AppSound(this.asset, {this.gap = Duration.zero});

  /// The bundled asset to play, e.g. `assets/sounds/wishlist.wav`.
  final String asset;

  /// A quiet window after each play, for sounds that can be triggered in a
  /// burst. Zero means every call sounds, subject only to one not already
  /// being in flight.
  final Duration gap;

  /// Off in tests: a widget test has no audio device, and initialising a
  /// player would leave a pending platform call that fails the test for a
  /// reason unrelated to what it was checking.
  @visibleForTesting
  static bool enabled = true;

  /// Counts plays, so a test can assert the sound happened without listening
  /// for one.
  @visibleForTesting
  int plays = 0;

  VideoPlayerController? _player;
  Future<void>? _loading;

  /// True while this sound is already playing.
  bool _sounding = false;

  /// The earliest the next play may start.
  DateTime _nextAllowed = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _ensureLoaded() {
    final existing = _player;
    if (existing != null) return Future<void>.value();
    return _loading ??= () async {
      try {
        final player = VideoPlayerController.asset(asset);
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

  /// Plays it. Never awaited by callers, and never throws.
  ///
  /// Silent when the shopper has turned sound off. Checked here rather than at
  /// each call site so that a sound added later is covered without anybody
  /// having to remember to check.
  Future<void> play() async {
    if (!enabled || !SoundSettings.instance.enabled) return;

    final now = DateTime.now();
    if (_sounding || now.isBefore(_nextAllowed)) return;
    _sounding = true;
    _nextAllowed = now.add(gap);
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
