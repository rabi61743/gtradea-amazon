import 'package:shared_preferences/shared_preferences.dart';

/// The email address the sign-in screen fills in for you.
///
/// What "Remember me" on that screen actually does. Deliberately *only* the
/// address: the password is never written anywhere, and the session already
/// persists on its own -- signing in keeps you signed in whether the box was
/// ticked or not, and a tickbox that pretended to decide that would be
/// describing something it does not control.
///
/// Unticking forgets it, which is the other half of the promise: a shared
/// handset must be able to take the address back off the screen.
abstract final class RememberedEmail {
  static const _key = 'gtradea_remembered_email';

  /// The address to prefill, or null when there is none to offer.
  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  static Future<void> write(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, trimmed);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
