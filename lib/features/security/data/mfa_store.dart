import 'package:flutter/foundation.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/json.dart';
import '../../../core/network/session_store.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/auth_store.dart';
import 'mfa_repository.dart';

/// Where two-factor authentication stands for the signed-in account.
enum MfaStatus {
  /// Not read yet, or signed out.
  unknown,
  loading,

  /// A verified TOTP factor exists: signing in asks for a code.
  enabled,

  /// No factor at all.
  disabled,

  /// A setup was started and never confirmed with a code. It protects
  /// nothing -- sign-in does not ask for it -- and says so.
  setupIncomplete,

  /// The status could not be read. Shown as such, never guessed.
  error,
}

/// The account's 2FA state, **always read from GoTrue**, and the enable and
/// disable flows.
///
/// There is no local flag anywhere in here that says 2FA is on. [status] is
/// derived from the factors the server returns on `GET /user`, and every
/// change ends by reading them again, so the screen can only ever show what the
/// server holds.
///
/// Changing it requires proving it is the account holder: the password for
/// both directions, and for turning it off a current authenticator code as
/// well -- GoTrue itself refuses to remove a verified factor without one.
class MfaStore extends ChangeNotifier {
  MfaStore._() {
    AuthStore.instance.addListener(_onAuthChanged);
  }

  static final MfaStore instance = MfaStore._();

  MfaRepository _mfa = MfaRepository.instance;
  AuthRepository _auth = AuthRepository.instance;

  @visibleForTesting
  set mfaRepositoryForTest(MfaRepository repo) => _mfa = repo;

  @visibleForTesting
  set authRepositoryForTest(AuthRepository repo) => _auth = repo;

  MfaStatus _status = MfaStatus.unknown;
  String? _error;
  bool _busy = false;
  String? _accountId;

  MfaStatus get status => _status;
  String? get error => _error;

  /// True while an enable or disable is talking to the server. Every button
  /// reads it, so a second tap cannot start a second request.
  bool get busy => _busy;

  void _onAuthChanged() {
    final id = AuthStore.instance.account?.id;
    if (id == _accountId) return;
    // A different account, or none: the last one's state must not show.
    _accountId = id;
    _status = MfaStatus.unknown;
    _error = null;
    notifyListeners();
  }

  /// Reads the factors from the server.
  Future<void> load() async {
    // Yield before the first notification. Screens call this from initState,
    // and a listener on a page that is mid-build -- Profile Settings, under a
    // two-factor page being pushed -- must not be told synchronously.
    await Future<void>.value();
    if (!AuthStore.instance.isSignedIn) return;
    _accountId = AuthStore.instance.account?.id;
    _status = MfaStatus.loading;
    _error = null;
    notifyListeners();
    try {
      final session = await _auth.liveSession();
      final factors = await _mfa.factors(session.accessToken);
      _status = factors.any((f) => f.isVerified)
          ? MfaStatus.enabled
          : factors.isEmpty
          ? MfaStatus.disabled
          : MfaStatus.setupIncomplete;
    } on ApiError catch (e) {
      _status = MfaStatus.error;
      _error = e.message;
    } finally {
      notifyListeners();
    }
  }

  /// Whether this account has a password to confirm with. An account that
  /// only ever signed in with Google has none; for it the authenticator code
  /// is the proof, and the screen skips the password step.
  static bool hasPassword(AuthSession? session) {
    final providers = asMap(session?.user?['app_metadata'])['providers'];
    if (providers is List) return providers.contains('email');
    return true;
  }

  Future<AuthSession> currentSession() => _auth.liveSession();

  /// Step one of turning 2FA on: confirm the password, then have the server
  /// generate the secret. Returns the setup the screen shows. 2FA is **not** on
  /// after this -- only [confirmEnable] turns it on.
  Future<TotpEnrollment> startEnable({String? password}) => _guard(() async {
    await _confirmPassword(password);
    final session = await _auth.liveSession();
    final setup = await _mfa.enroll(session.accessToken);
    _status = MfaStatus.setupIncomplete;
    return setup;
  });

  /// Step two: the code from the authenticator app. GoTrue verifies it; only
  /// on success is the factor verified -- 2FA on -- and the session raised to
  /// `aal2`, which is stored so this device stays signed in at that level.
  Future<void> confirmEnable(String factorId, String code) => _guard(() async {
    final session = await _auth.liveSession();
    final challenge = await _mfa.challenge(session.accessToken, factorId);
    final raised = await _mfa.verify(
      accessToken: session.accessToken,
      factorId: factorId,
      challengeId: challenge,
      code: code,
    );
    await _store(raised, previous: session);
    await _reload();
  });

  /// Abandons a setup that was not confirmed, removing the unverified factor
  /// from the server so no half-setup is left behind. Best effort: GoTrue also
  /// replaces an abandoned setup on the next attempt.
  Future<void> cancelEnable(String factorId) async {
    try {
      final session = await _auth.liveSession();
      await _mfa.unenroll(session.accessToken, factorId);
    } on ApiError {
      // Left for the next setup to clear.
    }
    await load();
  }

  /// Turns 2FA off: password, then a current code verified by the server
  /// (which raises this session to `aal2`, as GoTrue requires), then the
  /// factor is removed on the server and the status read back.
  Future<void> disable({String? password, required String code}) =>
      _guard(() async {
        await _confirmPassword(password);
        final session = await _auth.liveSession();
        final factors = await _mfa.factors(session.accessToken);
        final verified = factors.where((f) => f.isVerified).toList();
        if (verified.isEmpty) {
          await _reload();
          return;
        }
        final factorId = verified.first.id;
        final challenge = await _mfa.challenge(session.accessToken, factorId);
        final raised = await _mfa.verify(
          accessToken: session.accessToken,
          factorId: factorId,
          challengeId: challenge,
          code: code,
        );
        await _store(raised, previous: session);
        for (final factor in factors) {
          await _mfa.unenroll(raised.accessToken, factor.id);
        }
        // The stored copy of the user still lists the factor; read it fresh.
        final user = await _auth.currentUser(raised.accessToken);
        if (user != null) await _store(raised.withUser(user), previous: raised);
        await _reload();
      });

  Future<void> _confirmPassword(String? password) async {
    if (password == null) return;
    final email = AuthStore.instance.account?.email;
    if (email == null) {
      throw const ApiError(
        statusCode: 401,
        message: 'Your session has expired. Sign in again.',
      );
    }
    try {
      await _auth.verifyPassword(email: email, password: password);
    } on ApiError catch (e) {
      if (e.statusCode == 400) {
        throw const ApiError(
          statusCode: 400,
          message: 'That password is not correct.',
        );
      }
      rethrow;
    }
  }

  Future<void> _store(AuthSession session, {required AuthSession previous}) async {
    final withUser = session.user == null && previous.user != null
        ? session.withUser(previous.user!)
        : session;
    await _auth.writeSession(withUser);
    await AuthStore.instance.reloadFromSession();
  }

  Future<void> _reload() async {
    final session = await _auth.liveSession();
    final factors = await _mfa.factors(session.accessToken);
    _status = factors.any((f) => f.isVerified)
        ? MfaStatus.enabled
        : factors.isEmpty
        ? MfaStatus.disabled
        : MfaStatus.setupIncomplete;
    _error = null;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    if (_busy) {
      throw const ApiError(
        statusCode: null,
        message: 'Already working on it.',
        local: true,
      );
    }
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @visibleForTesting
  void resetForTest() {
    _status = MfaStatus.unknown;
    _error = null;
    _busy = false;
    _accountId = null;
    _mfa = MfaRepository.instance;
    _auth = AuthRepository.instance;
  }
}
