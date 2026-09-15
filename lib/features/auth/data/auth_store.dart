import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_error.dart';
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

/// An account signed in on this device, active or not.
///
/// What the account list shows and nothing more: who it is and how it signs
/// in. The tokens stay in [SessionStore]; nothing here could be used to act as
/// the account.
@immutable
class SavedAccount {
  const SavedAccount({required this.account, this.provider});

  final Account account;

  /// How it signs in -- `email`, `google` -- as the server recorded it.
  final String? provider;

  String get id => account.id;

  static SavedAccount? fromSession(AuthSession session) {
    final account = Account.fromUser(session.user);
    if (account == null) return null;
    final provider = (session.user?['app_metadata'] as Map?)?['provider'];
    return SavedAccount(
      account: account,
      provider: provider is String ? provider : null,
    );
  }

  bool _sameAs(SavedAccount other) =>
      id == other.id &&
      account.email == other.account.email &&
      account.displayName == other.account.displayName &&
      account.avatarUrl == other.account.avatarUrl &&
      provider == other.provider;
}

/// A saved account the server no longer accepts: revoked, signed out
/// elsewhere, or idle past its lifetime. It has been forgotten here, and the
/// way back is to sign in to it again.
class SavedSessionExpired implements Exception {
  const SavedSessionExpired(this.email);

  final String email;

  @override
  String toString() => 'The session for $email has ended. Sign in again.';
}

/// What a sign-out or a removal did.
@immutable
class SignOutResult {
  const SignOutResult({required this.revoked, this.switchedTo});

  /// True when the server confirmed the session ended. False means it was
  /// forgotten here but the server could not be reached; the session then
  /// expires on its own.
  final bool revoked;

  /// The account now active instead, when another one was on this device.
  final Account? switchedTo;
}

/// Who is signed in, shared across screens.
///
/// A [ChangeNotifier] facade over [SessionStore] and [AuthRepository]. The
/// tokens live in secure storage and identity comes from the server; this is
/// the part the widgets watch, so the nav and the account page flip the instant
/// state changes rather than on the next navigation.
///
/// Several accounts can be signed in on one device. Exactly one is active --
/// the one every request is sent as -- and every account-scoped store follows
/// it through this notifier, the same way it always followed sign-in and
/// sign-out.
class AuthStore extends ChangeNotifier {
  AuthStore._(this._auth) {
    // A refresh token can die while the app is closed, or be revoked. When it
    // does, the interceptor clears the tokens -- and without this the app would
    // carry on believing it was signed in, showing an account page whose every
    // request 401s, with no way out but a reinstall.
    _invalidation = SessionStore.instance.onInvalidated.listen((_) {
      unawaited(refreshSavedAccounts());
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

  @visibleForTesting
  AuthRepository get repositoryForTestValue => _auth;
  late final StreamSubscription<void> _invalidation;

  Account? _account;
  bool _loaded = false;
  bool _expired = false;

  List<SavedAccount> _saved = const [];
  bool _switching = false;
  bool _lastWasAlreadySaved = false;

  Account? get account => _account;
  bool get isSignedIn => _account != null;
  bool get isLoaded => _loaded;

  /// Every account signed in on this device, most recently used first. The
  /// active one is among them.
  List<SavedAccount> get savedAccounts => _saved;

  /// True while a switch is checking the chosen account with the server.
  bool get isSwitching => _switching;

  /// True when the last sign-in was to an account already on this device.
  /// Read once: the screen that added it says so, and nothing else should.
  bool takeWasAlreadySaved() {
    final value = _lastWasAlreadySaved;
    _lastWasAlreadySaved = false;
    return value;
  }

  /// True when the last sign-out was not the shopper's doing. The account
  /// screen says so rather than silently showing the signed-out state, which
  /// otherwise looks like the app lost their account.
  bool get sessionExpired => _expired;

  void acknowledgeExpiry() {
    if (!_expired) return;
    _expired = false;
    notifyListeners();
  }

  // ── Before the active account changes ───────────────────────────────────

  final List<Future<void> Function()> _beforeChange = [];

  /// Runs [hook] before the active account changes, while requests still go
  /// out as the old one.
  ///
  /// For a store holding an unsent write -- the cart's debounced sync -- that
  /// must reach the account it was made in rather than the next one.
  void addBeforeAccountChange(Future<void> Function() hook) =>
      _beforeChange.add(hook);

  Future<void> _runBeforeChange() async {
    for (final hook in List.of(_beforeChange)) {
      try {
        await hook().timeout(const Duration(seconds: 8));
      } catch (_) {
        // A write that cannot finish is the store's to report; it must not
        // hold up the change the shopper asked for.
      }
    }
  }

  /// Restores the session from secure storage. Cheap and idempotent; called at
  /// startup and by any screen that needs to know before it renders.
  Future<void> load() async {
    if (_loaded) return;
    final session = await SessionStore.instance.read();
    _account = Account.fromUser(session?.user);
    _loaded = true;
    notifyListeners();
    unawaited(refreshSavedAccounts());
  }

  /// Re-reads the accounts saved on this device.
  Future<void> refreshSavedAccounts() async {
    final sessions = await SessionStore.instance.savedSessions();
    final next = <SavedAccount>[
      for (final session in sessions.reversed)
        ?SavedAccount.fromSession(session),
    ];
    final same =
        next.length == _saved.length &&
        [for (var i = 0; i < next.length; i++) next[i]._sameAs(_saved[i])]
            .every((equal) => equal);
    if (same) return;
    _saved = List.unmodifiable(next);
    notifyListeners();
  }

  Future<Set<String>> _savedIds() async => {
    for (final session in await SessionStore.instance.savedSessions())
      ?session.userId,
  };

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
    unawaited(refreshSavedAccounts());
  }

  /// Brings this device's copy of the active account's photograph in step
  /// with its profile.
  ///
  /// The profile is where the shopper changes their photo; the saved session
  /// carries an older copy from sign-in -- for a Google account, Google's
  /// picture -- and the list of accounts on this device is drawn from it.
  /// This rewrites that copy here, and only here: the server's record is the
  /// profile's business.
  Future<void> adoptProfilePhoto(String url) async {
    if (url.isEmpty) return;
    final session = await SessionStore.instance.read();
    final user = session?.user;
    if (session == null || user == null) return;
    // Only ever the account the photo belongs to.
    if (session.userId == null || session.userId != _account?.id) return;

    final meta = <String, dynamic>{
      ...?(user['user_metadata'] as Map?)?.cast<String, dynamic>(),
    };
    if (meta['avatar_url'] == url) return;
    meta['avatar_url'] = url;

    final updated = session.withUser({...user, 'user_metadata': meta});
    await SessionStore.instance.write(updated);
    // A switch that landed during the write owns the account now.
    if (updated.userId != _account?.id) return;
    _account = Account.fromUser(updated.user);
    notifyListeners();
    await refreshSavedAccounts();
  }

  /// Throws [ApiError] with the server's own message on a bad password, an
  /// unconfirmed address or a dead connection.
  ///
  /// Signing in while another account is active adds this one beside it:
  /// the other stays saved on the device, and this one becomes active.
  Future<void> signIn({required String email, required String password}) async {
    final known = await _savedIds();
    await _runBeforeChange();
    final session = await _auth.signIn(email, password);
    _lastWasAlreadySaved = known.contains(session.userId);
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
    final known = await _savedIds();
    await _runBeforeChange();
    final result = await _auth.signUp(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
    );
    final session = result.session;
    if (session != null) {
      _lastWasAlreadySaved = known.contains(session.userId);
      _adopt(session);
    }
    return result.needsConfirmation;
  }

  Future<void> completeOAuth(Uri returned) async {
    final known = await _savedIds();
    await _runBeforeChange();
    final session = await _auth.completeOAuth(returned);
    _lastWasAlreadySaved = known.contains(session.userId);
    _adopt(session);
  }

  Future<void> recover(String email) => _auth.recover(email);

  /// Sets a new password from a reset token, and adopts the session the
  /// exchange produced. See [AuthRepository.resetPassword].
  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    await _runBeforeChange();
    _adopt(await _auth.resetPassword(token: token, password: password));
  }

  /// Which providers the server has configured, asked through the same
  /// repository everything else here uses -- so a test that stubs GoTrue stubs
  /// this too.
  Future<Set<String>> enabledProviders() => _auth.enabledProviders();

  /// Where a provider handshake starts.
  Uri authorizeUrl(String provider) => _auth.authorizeUrl(provider);

  /// Makes a saved account the active one.
  ///
  /// The saved session is checked with the server first -- renewed if its
  /// hour is up -- and adopted only once it is known to work, so a failed
  /// switch leaves the current account exactly as it was. Nothing is signed
  /// out: the account switched away from stays saved.
  ///
  /// Throws [SavedSessionExpired] when the server no longer takes the saved
  /// session (it is forgotten here, and the shopper signs in to it again), and
  /// [ApiError] when the server could not be reached.
  Future<void> switchAccount(String id) async {
    if (_account?.id == id || _switching) return;
    AuthSession? target;
    for (final session in await SessionStore.instance.savedSessions()) {
      if (session.userId == id) target = session;
    }
    if (target == null) {
      await refreshSavedAccounts();
      throw const ApiError(
        statusCode: null,
        message: 'That account is no longer on this device.',
        local: true,
      );
    }

    _switching = true;
    notifyListeners();
    try {
      final AuthSession fresh;
      try {
        fresh = await _auth.checkSession(target);
      } on ApiError catch (e) {
        if (!e.isUnauthorized) rethrow;
        await SessionStore.instance.forget(id);
        throw SavedSessionExpired(
          Account.fromUser(target.user)?.email ?? 'that account',
        );
      }
      await _runBeforeChange();
      await SessionStore.instance.write(fresh);
      _adopt(fresh);
    } finally {
      _switching = false;
      notifyListeners();
      await refreshSavedAccounts();
    }
  }

  /// Signs the active account out of this device, on the server as well.
  ///
  /// When another account is saved here, the app carries on as that one
  /// rather than landing signed out; [SignOutResult.switchedTo] says which.
  Future<SignOutResult> signOut() async {
    // No pending-write flush here, unlike a switch: signing out leaves no
    // account for a late write to land in -- the stores drop it on the change
    // of account -- and the shopper is owed an immediate sign-out.
    //
    // Locally first. Telling the server is worth doing but not worth waiting
    // for: on a bad connection a shopper who tapped Sign out should not be left
    // looking at their own account for twenty seconds.
    _account = null;
    _expired = false;
    _loaded = true;
    notifyListeners();
    final revoked = await _auth.signOut();
    await refreshSavedAccounts();

    for (final saved in List.of(_saved)) {
      try {
        await switchAccount(saved.id);
        return SignOutResult(revoked: revoked, switchedTo: saved.account);
      } catch (_) {
        // A saved account that will not come back is forgotten by the
        // switch; the next one gets its turn.
      }
    }
    return SignOutResult(revoked: revoked);
  }

  /// Takes an account off this device without deleting it from the shop.
  ///
  /// Its session on this device is ended on the server, and it leaves the
  /// saved list. Removing the active account is a sign-out.
  Future<SignOutResult> removeAccount(String id) async {
    if (_account?.id == id) return signOut();
    AuthSession? target;
    for (final session in await SessionStore.instance.savedSessions()) {
      if (session.userId == id) target = session;
    }
    var revoked = true;
    if (target != null) revoked = await _auth.revokeSession(target);
    await SessionStore.instance.forget(id);
    await refreshSavedAccounts();
    return SignOutResult(revoked: revoked);
  }

  /// This account's user record as the server holds it now: when and how it
  /// last signed in. See [AuthRepository.me].
  Future<Map<String, dynamic>> loginDetails() => _auth.me();

  /// Signs out every other device, after proving it is the account holder
  /// asking.
  ///
  /// [password] is checked first when given; an account that signs in only
  /// through a provider has none, and the caller confirms instead. Throws
  /// [ApiError] -- a wrong password, an expired session, a dropped
  /// connection -- and returns only once GoTrue has revoked the sessions.
  Future<void> signOutOtherDevices({String? password}) async {
    final account = _account;
    if (account == null) {
      throw const ApiError(
        statusCode: 401,
        message: 'Your session has expired. Sign in again.',
      );
    }
    if (password != null) {
      try {
        await _auth.verifyPassword(email: account.email, password: password);
      } on ApiError catch (e) {
        // GoTrue answers a wrong password with a 400 and "Invalid login
        // credentials", which reads as a sign-in rather than a check.
        if (e.statusCode == 400) {
          throw const ApiError(
            statusCode: 400,
            message: 'That password is not correct.',
          );
        }
        rethrow;
      }
    }
    await _auth.signOutOtherDevices();
  }

  void _adopt(AuthSession session) {
    _account = Account.fromUser(session.user);
    _loaded = true;
    _expired = false;
    notifyListeners();
    unawaited(refreshSavedAccounts());
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
    _saved = const [];
    _switching = false;
    _lastWasAlreadySaved = false;
  }

  @override
  void dispose() {
    _invalidation.cancel();
    super.dispose();
  }
}
