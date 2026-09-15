import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The tokens the gateway issued, and when they stop working.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    this.expiresAt,
    this.user,
  });

  final String accessToken;
  final String refreshToken;

  /// Unix epoch seconds. Absolute, so it survives the app being killed --
  /// GoTrue's own `expires_in` is relative and would silently mean "an hour
  /// from whenever this was read".
  final int? expiresAt;

  /// The GoTrue user object, verbatim. The JWT is never decoded on the client:
  /// an unverified claim is not evidence of anything, so identity comes from
  /// this object and permission decisions come from the server.
  final Map<String, dynamic>? user;

  /// Refreshed 30s early, so a request that starts just before the boundary
  /// does not arrive just after it.
  bool get isExpired {
    if (expiresAt == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= (expiresAt! - 30);
  }

  String? get userId {
    final u = user;
    if (u == null) return null;
    final id = u['id'] ?? u['sub'];
    return id is String && id.isNotEmpty ? id : null;
  }

  String? get email {
    final value = user?['email'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// The same session carrying a newer copy of the user object.
  ///
  /// Tokens are untouched: changing a name or an address on GoTrue does not
  /// issue new ones, and replacing a working access token with anything else
  /// here would sign the shopper out mid-edit.
  AuthSession withUser(Map<String, dynamic> user) => AuthSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: expiresAt,
    user: user,
  );

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt,
    'user': user,
  };

  /// Lenient on purpose. The password grant returns `expires_in`, the refresh
  /// grant returns both, and the OAuth fragment returns everything as strings
  /// because a URL has no other type. A cast that assumed one of those shapes
  /// would throw on the others and lose a session that is perfectly good.
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    int? expiresAt = _epoch(json['expires_at']);
    final expiresIn = _epoch(json['expires_in']);
    if (expiresAt == null && expiresIn != null) {
      expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + expiresIn;
    }
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    if (access is! String || access.isEmpty) {
      throw const FormatException('session has no access token');
    }
    return AuthSession(
      accessToken: access,
      refreshToken: refresh is String ? refresh : '',
      expiresAt: expiresAt,
      user: (json['user'] as Map?)?.cast<String, dynamic>(),
    );
  }

  static int? _epoch(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// Where the tokens live.
///
/// Secure storage, not SharedPreferences: an access token is a bearer
/// credential, and prefs are a plain XML file on Android and an unprotected
/// plist on iOS. The wishlist can live there; this cannot.
///
/// A single instance, because the in-memory cache in front of the keystore is
/// only correct if there is exactly one of it -- two would drift apart the
/// moment either wrote.
class SessionStore {
  SessionStore._(this._storage);

  static final SessionStore instance = SessionStore._(
    const FlutterSecureStorage(),
  );

  /// For tests: an isolated store over a fake backing.
  @visibleForTesting
  SessionStore.forTest(this._storage);

  static const _key = 'gtradea-go-auth-session';

  final FlutterSecureStorage _storage;

  AuthSession? _cached;
  bool _loaded = false;

  /// Fires when a refresh fails, meaning the refresh token is dead and the app
  /// is signed out whether it likes it or not.
  ///
  /// This exists because the alternative is worse than it sounds: without it
  /// the app clears the tokens but still believes it is signed in, so every
  /// screen 401s forever and the only way out the shopper can find is
  /// reinstalling.
  final _invalidated = StreamController<void>.broadcast();

  Stream<void> get onInvalidated => _invalidated.stream;

  /// The active account's session: the one every request is sent with.
  Future<AuthSession?> read() async {
    if (_loaded) return _cached;
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null) {
        _cached = AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // A keystore that will not open, or a half-written blob. Signed out is
      // the honest reading of both, and it is recoverable by signing in.
      _cached = null;
    }
    _loaded = true;

    // A session stored before accounts were kept side by side: the one
    // account this device had joins the saved list rather than being lost to
    // the first switch.
    final id = _cached?.userId;
    if (id != null) {
      await _loadVault();
      if (!_vault.containsKey(id)) {
        _vault[id] = _cached!;
        await _saveVault();
      }
    }
    return _cached;
  }

  /// Makes [session] the active one, and keeps it among the saved accounts.
  ///
  /// Every token refresh comes through here too, so the saved copy of an
  /// account is always its newest tokens -- a stale refresh token kept for a
  /// switch later would be one GoTrue has already rotated away.
  Future<void> write(AuthSession session) async {
    _cached = session;
    _loaded = true;
    try {
      await _storage.write(key: _key, value: jsonEncode(session.toJson()));
    } catch (_) {
      // The session still works for this run; it just will not survive a
      // restart. Failing the sign-in over that would be worse.
    }
    final id = session.userId;
    if (id != null) {
      await _loadVault();
      // Re-inserted, so the list runs least to most recently used.
      _vault.remove(id);
      _vault[id] = session;
      await _saveVault();
    }
  }

  /// Signs the active account out of this device: its session goes, and so
  /// does its place among the saved accounts. The others are untouched.
  Future<void> clear({bool notify = false}) async {
    final id = _cached?.userId;
    _cached = null;
    _loaded = true;
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing useful to do -- the cache is already cleared.
    }
    if (id != null) {
      await _loadVault();
      if (_vault.remove(id) != null) await _saveVault();
    }
    if (notify) _invalidated.add(null);
  }

  /// The cached session without touching the keystore. Null both when signed
  /// out and when [read] has not run yet, so it is for hot paths that have
  /// already awaited a read, not for deciding whether someone is signed in.
  AuthSession? get current => _cached;

  // ── Accounts kept on this device ─────────────────────────────────────────
  //
  // Each account signed in here keeps its own session, in the same keystore
  // as the active one and never anywhere else. Switching makes a saved one
  // active; nothing about the others changes, so switching back costs no
  // password. Passwords are never stored: a session is a token pair.

  static const _vaultKey = 'gtradea-go-auth-accounts';

  final Map<String, AuthSession> _vault = {};
  bool _vaultLoaded = false;
  Future<void>? _vaultLoading;

  /// Every account signed in on this device, least recently used first.
  Future<List<AuthSession>> savedSessions() async {
    await read();
    await _loadVault();
    return List.unmodifiable(_vault.values);
  }

  /// Forgets a saved account that is not the active one. The active one is
  /// signed out through [clear], which also forgets it.
  Future<void> forget(String userId) async {
    await _loadVault();
    if (_vault.remove(userId) == null) return;
    await _saveVault();
  }

  Future<void> _loadVault() {
    if (_vaultLoaded) return Future<void>.value();
    return _vaultLoading ??= _readVault();
  }

  Future<void> _readVault() async {
    try {
      final raw = await _storage.read(key: _vaultKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded.whereType<Map>()) {
            try {
              final session = AuthSession.fromJson(
                entry.cast<String, dynamic>(),
              );
              final id = session.userId;
              if (id != null) _vault.putIfAbsent(id, () => session);
            } catch (_) {
              // One unreadable entry costs that account, not the others.
            }
          }
        }
      }
    } catch (_) {
      // An unreadable list is an empty one; each account signs in again.
    }
    _vaultLoaded = true;
    _vaultLoading = null;
  }

  Future<void> _saveVault() async {
    try {
      await _storage.write(
        key: _vaultKey,
        value: jsonEncode([
          for (final session in _vault.values) session.toJson(),
        ]),
      );
    } catch (_) {
      // The list still stands for this run.
    }
  }

  @visibleForTesting
  void resetForTest() {
    _cached = null;
    _loaded = false;
    _vault.clear();
    _vaultLoaded = false;
    _vaultLoading = null;
  }
}
