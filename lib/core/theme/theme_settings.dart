import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the app looks: light, dark, or whatever the device is set to.
///
/// A [ChangeNotifier] singleton, in the same shape as `SoundSettings`. The
/// root [MaterialApp] listens to it, so a change repaints every screen that is
/// already open -- through the theme's own animation, which is what makes the
/// switch a fade rather than a flash.
class ThemeSettings extends ChangeNotifier {
  ThemeSettings._();

  static final ThemeSettings instance = ThemeSettings._();

  static const _key = 'gtradea_theme_mode';

  /// Light until told otherwise: the app has always shipped the white
  /// version, and a shopper who never opens this setting should not find it
  /// changed under them.
  ThemeMode _mode = ThemeMode.light;
  bool _loaded = false;

  ThemeMode get mode => _mode;
  bool get isLoaded => _loaded;

  /// Reads the stored choice. Awaited before the first frame in `main.dart`,
  /// so a saved Dark never opens on one white frame first.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = _parse(prefs.getString(_key)) ?? ThemeMode.light;
    } catch (_) {
      // Unreadable store: the default, which is what the app looked like
      // before there was a choice.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Applies the choice now and remembers it. The write follows the change,
  /// as with every preference here: the screen must not wait on the disk.
  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode && _loaded) return;
    _mode = mode;
    _loaded = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {
      // Best effort: a failed write costs the choice across a restart only.
    }
  }

  static ThemeMode? _parse(String? stored) => switch (stored) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => null,
  };

  @visibleForTesting
  void resetForTest() {
    _mode = ThemeMode.light;
    _loaded = false;
  }
}
