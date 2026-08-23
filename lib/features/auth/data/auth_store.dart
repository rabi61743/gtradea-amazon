import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The signed-in customer.
@immutable
class Account {
  const Account({required this.email, this.name});

  final String email;
  final String? name;

  /// What to greet them with. Falls back to the part of the address before the
  /// @, which is a better guess than showing the whole email in a heading.
  String get displayName {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  Map<String, dynamic> toJson() => {'email': email, 'name': name};

  static Account? fromJson(Map<String, dynamic> json) {
    final email = json['email'];
    if (email is! String || email.isEmpty) return null;
    return Account(
      email: email,
      name: json['name'] is String ? json['name'] as String : null,
    );
  }
}

/// Who is signed in, shared across screens.
///
/// A [ChangeNotifier] singleton, matching [WishlistStore]: the bottom nav, the
/// account page and anything else gated on identity all listen to one source,
/// so the UI flips the moment the state changes rather than on the next
/// navigation.
///
/// **This is a local placeholder, not authentication.** Nothing is verified and
/// no password is checked or stored -- the sibling storefront signs in against
/// GoTrue at `/auth/v1/token`. Wiring that up replaces [signIn] and nothing
/// above it.
class AuthStore extends ChangeNotifier {
  AuthStore._();

  static final instance = AuthStore._();

  static const _key = 'gtradea_account';

  Account? _account;
  bool _loaded = false;

  Account? get account => _account;
  bool get isSignedIn => _account != null;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _account = Account.fromJson(decoded.cast<String, dynamic>());
        }
      }
    } catch (_) {
      // Unreadable: treat as signed out rather than blocking the app.
    }
    _loaded = true;
    notifyListeners();
  }

  void signIn({required String email, String? name}) {
    _account = Account(email: email.trim(), name: name?.trim());
    // Marking loaded closes the race where a sign-in beats the startup read
    // and the disk copy then overwrites it. An explicit change always wins
    // over a pending load.
    _loaded = true;
    notifyListeners();
    unawaited(_persist());
  }

  void signOut() {
    _account = null;
    _loaded = true;
    notifyListeners();
    unawaited(_persist());
  }

  @visibleForTesting
  void resetForTest() {
    _account = null;
    _loaded = false;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final account = _account;
      if (account == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, jsonEncode(account.toJson()));
      }
    } catch (_) {
      // Best effort, like the wishlist: a failed write costs persistence
      // across a restart, never the action just taken.
    }
  }
}
