import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the app makes any sound at all.
///
/// One switch for the lot rather than one per sound: a shopper who wants
/// quiet wants quiet, and a settings page that makes them turn off four
/// things to get it has misunderstood the request. Every sound played through
/// [AppSound] reads this, so a new sound is covered the day it is added
/// without anybody having to remember to wire it up.
///
/// A [ChangeNotifier] singleton, which is how the rest of this app shares
/// state -- see `WishlistStore` and `LanguageStore` for the same shape.
class SoundSettings extends ChangeNotifier {
  SoundSettings._();

  static final SoundSettings instance = SoundSettings._();

  static const _key = 'gtradea_sound_enabled';

  /// **On until told otherwise.** A shopper who has never opened this setting
  /// gets the sounds, and the stored value only ever turns them off. That is
  /// also what happens while the preference is still being read from disk, so
  /// the first frame of a cold start never has to guess wrong in the direction
  /// of silence.
  bool _enabled = true;
  bool _loaded = false;

  bool get enabled => _enabled;
  bool get isLoaded => _loaded;

  /// Reads the stored preference. Called at startup, and cheap to call again.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Absent means never set, which is on -- not off.
      _enabled = prefs.getBool(_key) ?? true;
    } catch (_) {
      // Unreadable store: sound stays on, which is the documented default.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Turns sound on or off, and remembers it.
  ///
  /// The switch answers immediately and the write follows: a preference that
  /// waited on the disk before moving would feel broken, and a failed write
  /// costs the setting across a restart, never the setting now.
  Future<void> setEnabled(bool value) async {
    if (_enabled == value && _loaded) return;
    _enabled = value;
    _loaded = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {
      // Best effort, as everywhere else this app persists a preference.
    }
  }

  /// Test seam: drops in-memory state so each test starts at the default.
  @visibleForTesting
  void resetForTest() {
    _enabled = true;
    _loaded = false;
  }
}
