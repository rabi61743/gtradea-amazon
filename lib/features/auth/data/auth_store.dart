import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/session_store.dart';
import 'auth_repository.dart';

/// The signed-in customer, as the app needs them.
///
/// A view of the GoTrue user object rather than a second copy of it: the server
/// owns identity, this is what the UI reads.
@immutable
class Account {
  const Account({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.avatarUrl,
  });

  /// The GoTrue user id. Every user-scoped row on the server keys on it.
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;

  /// Whatever the identity provider supplied -- Google puts a photograph here
  /// on sign-in. The gateway's profile row is the one the shopper edits, and
  /// it wins when it has one; this is what an account has before that.
  final String? avatarUrl;

  /// What to greet them with. Falls back to the part of the address before the
  /// @, which reads better in a heading than the whole email.
  String get displayName {
    final full = [firstName, lastName]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');
    if (full.isNotEmpty) return full;
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  /// Built from the GoTrue user object. `user_metadata` is where the sign-up
  /// `data` block lands.
  static Account? fromUser(Map<String, dynamic>? user) {
    if (user == null) return null;
    final id = user['id'] ?? user['sub'];
    final email = user['email'];
    if (id is! String || id.isEmpty) return null;
    final meta =
        (user['user_metadata'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return Account(
      id: id,
      email: email is String ? email : '',
      firstName: _str(meta['first_name']) ?? _str(meta['given_name']),
      lastName: _str(meta['last_name']) ?? _str(meta['family_name']),
      // Both spellings: GoTrue's own metadata uses `avatar_url`, and Google's
      // OIDC claim arrives as `picture`.
      avatarUrl: _str(meta['avatar_url']) ?? _str(meta['picture']),
    );
  }

  static String? _str(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;
}

/// Who is signed in, shared across screens.
///
/// A [ChangeNotifier] facade over [SessionStore] and [AuthRepository]. The
/// tokens live in secure storage and identity comes from the server; this is
/// the part the widgets watch, so the nav and the account page flip the instant
/// state changes rather than on the next navigation.
class AuthStore extends ChangeNotifier {
  AuthStore._(this._auth) {
    // A refresh token can die while the app is closed, or be revoked. When it
    // does, the interceptor clears the tokens -- and without this the app would
    // carry on believing it was signed in, showing an account page whose every
    // request 401s, with no way out but a reinstall.
    _invalidation = SessionStore.instance.onInvalidated.listen((_) {
      if (_account == null) return;
      _account = null;
      _expired = true;
      notifyListeners();
    });
  }

  static final instance = AuthStore._(AuthRepository.instance);

  AuthRepository _auth;

  /// Swaps GoTrue for a stub. The store is a singleton, so this is the seam
  /// the widget tests drive sign-in through.
  @visibleForTesting
  set repositoryForTest(AuthRepository repo) => _auth = repo;
  late final StreamSubscription<void> _invalidation;

  Account? _account;
  bool _loaded = false;
  bool _expired = false;

  Account? get account => _account;
  bool get isSignedIn => _account != null;
  bool get isLoaded => _loaded;

  /// True when the last sign-out was not the shopper's doing. The account
  /// screen says so rather than silently showing the signed-out state, which
  /// otherwise looks like the app lost their account.
  bool get sessionExpired => _expired;

  void acknowledgeExpiry() {
    if (!_expired) return;
    _expired = false;
    notifyListeners();
  }

  /// Restores the session from secure storage. Cheap and idempotent; called at
  /// startup and by any screen that needs to know before it renders.
  Future<void> load() async {
    if (_loaded) return;
    final session = await SessionStore.instance.read();
    _account = Account.fromUser(session?.user);
    _loaded = true;
    notifyListeners();
  }

  /// Re-reads the account from the stored session.
  ///
  /// Unlike [load] this always reads, because it exists for the case where the
  /// session was just rewritten -- changing a name or an email on GoTrue
  /// updates the user object in secure storage, and without this the header
  /// would keep showing the old one until the app restarted.
  Future<void> reloadFromSession() async {
    final session = await SessionStore.instance.read();
    final account = Account.fromUser(session?.user);
    if (account == null) return;
    _account = account;
    _loaded = true;
    notifyListeners();
  }

  /// Throws [ApiError] with the server's own message on a bad password, an
  /// unconfirmed address or a dead connection.
  Future<void> signIn({required String email, required String password}) async {
    final session = await _auth.signIn(email, password);
    _adopt(session);
  }

  /// Returns true when the account was made but needs the emailed link before
  /// it can be used.
  Future<bool> signUp({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
  }) async {
    final result = await _auth.signUp(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
    );
    final session = result.session;
    if (session != null) _adopt(session);
    return result.needsConfirmation;
  }

  Future<void> completeOAuth(Uri returned) async {
    _adopt(await _auth.completeOAuth(returned));
  }

  Future<void> recover(String email) => _auth.recover(email);

  Future<void> signOut() async {
    // Locally first. Telling the server is worth doing but not worth waiting
    // for: on a bad connection a shopper who tapped Sign out should not be left
    // looking at their own account for twenty seconds.
    _account = null;
    _expired = false;
    _loaded = true;
    notifyListeners();
    await _auth.signOut();
  }

  void _adopt(AuthSession session) {
    _account = Account.fromUser(session.user);
    _loaded = true;
    _expired = false;
    notifyListeners();
  }

  @visibleForTesting
  void adoptForTest(Account? account) {
    _account = account;
    _loaded = true;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _account = null;
    _loaded = false;
    _expired = false;
  }

  @override
  void dispose() {
    _invalidation.cancel();
    super.dispose();
  }
}
