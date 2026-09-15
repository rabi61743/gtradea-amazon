import 'package:dio/dio.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/session_store.dart';
import '../../security/data/mfa_repository.dart';

/// What came back from a sign-up.
///
/// A tokenless answer is not a failure: when the project requires email
/// confirmation, GoTrue creates the account and returns no session, and the
/// only correct thing to show is "check your email".
class SignUpResult {
  const SignUpResult({this.session, this.needsConfirmation = false});

  final AuthSession? session;
  final bool needsConfirmation;
}

/// Sign-in, sign-up and password recovery, against GoTrue.
///
/// On its own Dio, with no interceptors. That is not tidiness -- the shared
/// client refreshes tokens by calling this server, so routing these calls
/// through it would mean a failed login could trigger a token refresh.
class AuthRepository {
  AuthRepository({SessionStore? sessions, Dio? dio})
    : _sessions = sessions ?? SessionStore.instance,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: Env.authBaseUrl,
              connectTimeout: Env.requestTimeout,
              receiveTimeout: Env.requestTimeout,
              contentType: 'application/json',
            ),
          );

  static final AuthRepository instance = AuthRepository();

  final SessionStore _sessions;
  final Dio _dio;

  /// Exchanges an email and password for a session, **without storing it**.
  ///
  /// Storing is [AuthStore]'s decision, because for an account with
  /// two-factor authentication this session is only `aal1` -- the password
  /// has been proved and the second factor has not. Written to secure storage
  /// here, it would survive a restart as a signed-in account that never
  /// passed 2FA.
  Future<AuthSession> signIn(String email, String password) async {
    try {
      final res = await _dio.post(
        '/token',
        queryParameters: {'grant_type': 'password'},
        data: {'email': email.trim(), 'password': password},
      );
      return AuthSession.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// Stores [session] as the active one. The one place [AuthStore] commits a
  /// session it has decided is fully signed in.
  Future<void> writeSession(AuthSession session) => _sessions.write(session);

  /// The active session, renewed first if its hour is up. Throws a 401
  /// [ApiError] when there is none or the server will not renew it.
  Future<AuthSession> liveSession() async {
    final session = await _sessions.read();
    if (session == null) {
      throw const ApiError(
        statusCode: 401,
        message: 'Your session has expired. Sign in again.',
      );
    }
    return session.isExpired ? _refresh(session) : session;
  }

  Future<SignUpResult> signUp({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
  }) async {
    try {
      final res = await _dio.post(
        '/signup',
        data: {
          'email': email.trim(),
          'password': password,
          'data': {
            if (firstName != null && firstName.isNotEmpty)
              'first_name': firstName,
            if (lastName != null && lastName.isNotEmpty) 'last_name': lastName,
          },
        },
      );
      final body = (res.data as Map).cast<String, dynamic>();
      if (body['access_token'] != null) {
        final session = AuthSession.fromJson(body);
        await _sessions.write(session);
        return SignUpResult(session: session);
      }
      return const SignUpResult(needsConfirmation: true);
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// Sends the reset email.
  ///
  /// Answers the same whether or not the address has an account -- GoTrue
  /// deliberately will not confirm which addresses are registered, and the UI
  /// must not either. "Check your email" is the only honest message.
  /// Asks GoTrue to email a reset link.
  ///
  /// Answers the same for an address with an account and one without -- that
  /// is GoTrue's behaviour, and it is the right one: a different answer would
  /// tell anybody with the form which addresses are registered.
  ///
  /// `redirect_to` is where the link lands, and it is the storefront's own
  /// reset page: the same page the website sends people to, so a link works
  /// wherever it is opened. GoTrue substitutes its SITE_URL for any redirect
  /// that is not allow-listed, so the worst case is the site's front door
  /// rather than a broken link.
  Future<void> recover(String email) async {
    try {
      await _dio.post(
        '/recover',
        data: {'email': email.trim(), 'redirect_to': Env.passwordResetUrl},
      );
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// Sets a new password from a reset token.
  ///
  /// Two calls, which is what the token is for and all it is for:
  ///
  ///   1. `POST /verify` trades the one-time `token_hash` from the email for a
  ///      short-lived session. This is where an expired or already-used link is
  ///      refused -- by the server, not here.
  ///   2. `PUT /user` sets the password with that session's token.
  ///
  /// The session is adopted at the end, because that is what the exchange
  /// produced: the person proved they hold the mailbox and then set a
  /// password, and asking them to type it again immediately serves nothing.
  ///
  /// The token never leaves this method, and the password is sent once and
  /// never written down.
  ///
  /// Split in two -- [verifyRecovery] then [setPassword] -- and nothing is
  /// stored here, so that an account with two-factor authentication can pass
  /// its second factor between the two steps. GoTrue will not change the
  /// password of such an account on a session that has not.
  Future<AuthSession> verifyRecovery(String token) async {
    try {
      final verified = await _dio.post(
        '/verify',
        data: {'type': 'recovery', 'token_hash': token.trim()},
      );
      final body = (verified.data as Map).cast<String, dynamic>();
      final access = body['access_token'];
      if (access is! String || access.isEmpty) {
        throw const ApiError(
          statusCode: null,
          message: 'That reset link is no longer valid. Request a new one.',
        );
      }
      return AuthSession.fromJson(body);
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// Sets the password with [session]'s token and returns the session carrying
  /// the updated user. Stores nothing.
  Future<AuthSession> setPassword(AuthSession session, String password) async {
    try {
      final updated = await _dio.put(
        '/user',
        data: {'password': password},
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
      return session.withUser((updated.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// The reset token out of whatever was pasted in.
  ///
  /// The email's link carries it as `token` or `token_hash`, in the query or
  /// the fragment depending on which hop of the redirect chain was copied. A
  /// bare code pasted on its own is taken as the token itself.
  static String? tokenFromLink(String pasted) {
    final trimmed = pasted.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) {
      for (final source in [
        uri.queryParameters,
        Uri.splitQueryString(uri.fragment),
      ]) {
        final token = source['token_hash'] ?? source['token'];
        if (token != null && token.isNotEmpty) return token;
      }
      // A link with no token in it is not a token.
      return null;
    }

    // Not a URL: the code on its own, which is what somebody who copied it out
    // of the address bar by hand will have.
    return trimmed.contains(RegExp(r'\s')) ? null : trimmed;
  }

  /// Signs the active account out: on the server, then on this device.
  ///
  /// Returns true when GoTrue confirmed the session ended. The local clear
  /// happens either way -- failing it over a dropped connection would trap
  /// someone signed in -- and a false answer is the caller's to report.
  Future<bool> signOut() async {
    final session = await _sessions.read();
    var revoked = true;
    if (session != null) {
      revoked = await _logout(session, scope: null);
    }
    await _sessions.clear();
    return revoked;
  }

  /// Ends a saved account's session on this device, on the server.
  ///
  /// `scope=local`: this device's session for that account, and only that.
  /// The same person signed in on a laptop stays signed in there. True when
  /// GoTrue confirmed it.
  Future<bool> revokeSession(AuthSession session) =>
      _logout(session, scope: 'local');

  Future<bool> _logout(AuthSession session, {required String? scope}) async {
    var live = session;
    // An access token past its hour is refused by /logout, which would leave
    // the refresh token -- the part that matters -- alive on the server.
    if (live.isExpired) {
      try {
        live = await _renew(live);
      } on ApiError {
        // Already dead on the server: nothing left to end.
        return true;
      }
    }
    try {
      await _dio.post(
        '/logout',
        queryParameters: {'scope': ?scope},
        options: Options(
          headers: {'Authorization': 'Bearer ${live.accessToken}'},
        ),
      );
      return true;
    } on DioException catch (e) {
      // 401 means the server no longer knows the session: ended already.
      return e.response?.statusCode == 401;
    }
  }

  /// Checks that a saved account's session still works, renewing it when its
  /// hour is up, and returns it with a fresh copy of the user.
  ///
  /// Stores nothing. The caller makes it the active session only once it is
  /// known to be good, so a dead one never replaces a working one. Throws a
  /// 401 [ApiError] when the server will not take it any more.
  Future<AuthSession> checkSession(AuthSession saved) async {
    var session = saved;
    var renewed = false;
    if (session.isExpired) {
      session = await _renew(session);
      renewed = true;
    }
    try {
      return session.withUser(await _userFor(session.accessToken));
    } on ApiError catch (e) {
      // An access token revoked early, with a refresh token still good.
      if (!e.isUnauthorized || renewed) rethrow;
      session = await _renew(session);
      return session.withUser(await _userFor(session.accessToken));
    }
  }

  Future<Map<String, dynamic>> _userFor(String accessToken) async {
    try {
      final res = await _dio.get(
        '/user',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// A refresh that stores nothing, for sessions that are not the active one.
  Future<AuthSession> _renew(AuthSession session) async {
    if (session.refreshToken.isEmpty) {
      throw const ApiError(
        statusCode: 401,
        message: 'Your session has expired. Sign in again.',
      );
    }
    try {
      final res = await _dio.post(
        '/token',
        queryParameters: {'grant_type': 'refresh_token'},
        data: {'refresh_token': session.refreshToken},
      );
      final fresh = AuthSession.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
      return fresh.user == null && session.user != null
          ? fresh.withUser(session.user!)
          : fresh;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != null && status >= 400 && status < 500) {
        throw const ApiError(
          statusCode: 401,
          message: 'Your session has expired. Sign in again.',
        );
      }
      throw ApiError.fromDio(e);
    }
  }

  /// Ends every session this account has except the one on this device.
  ///
  /// GoTrue's own `POST /logout?scope=others`: the server revokes the other
  /// sessions' refresh tokens, so another phone or browser is signed out the
  /// next time its access token runs out -- at most an hour, GoTrue's token
  /// lifetime -- and can never renew it. This session is untouched.
  ///
  /// Unlike [signOut] this is not best effort. It is a security action, and
  /// the caller must only say it worked when the server said so; any failure
  /// is thrown.
  Future<void> signOutOtherDevices() async {
    var session = await _sessions.read();
    if (session == null) {
      throw const ApiError(
        statusCode: 401,
        message: 'Your session has expired. Sign in again.',
      );
    }
    // This client has no refresh interceptor, and an access token past its
    // hour would be refused -- which would read as the action failing.
    if (session.isExpired) session = await _refresh(session);

    try {
      await _dio.post(
        '/logout',
        queryParameters: {'scope': 'others'},
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
    } on DioException catch (e) {
      final error = ApiError.fromDio(e);
      if (error.statusCode == 401) {
        // This session itself has been revoked -- from another device, or by
        // the server. Signed out is the truth; the store hears about it.
        await _sessions.clear(notify: true);
        throw const ApiError(
          statusCode: 401,
          message: 'Your session has expired. Sign in again.',
        );
      }
      throw error;
    }
  }

  /// This account's GoTrue user object, read fresh from the server.
  ///
  /// The server answers only for the bearer of the token, so this cannot
  /// return anybody else's record. Unlike [currentUser] a failure is thrown,
  /// because the screen that asks has an error state to show.
  Future<Map<String, dynamic>> me() async {
    var session = await _sessions.read();
    if (session == null) {
      throw const ApiError(
        statusCode: 401,
        message: 'Your session has expired. Sign in again.',
      );
    }
    if (session.isExpired) session = await _refresh(session);
    try {
      final res = await _dio.get(
        '/user',
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      final error = ApiError.fromDio(e);
      if (error.statusCode == 401) {
        await _sessions.clear(notify: true);
        throw const ApiError(
          statusCode: 401,
          message: 'Your session has expired. Sign in again.',
        );
      }
      throw error;
    }
  }

  Future<AuthSession> _refresh(AuthSession session) async {
    try {
      final res = await _dio.post(
        '/token',
        queryParameters: {'grant_type': 'refresh_token'},
        data: {'refresh_token': session.refreshToken},
      );
      final fresh = AuthSession.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
      await _sessions.write(fresh.user == null && session.user != null
          ? fresh.withUser(session.user!)
          : fresh);
      return fresh;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != null && status >= 400 && status < 500) {
        await _sessions.clear(notify: true);
        throw const ApiError(
          statusCode: 401,
          message: 'Your session has expired. Sign in again.',
        );
      }
      throw ApiError.fromDio(e);
    }
  }

  /// Which providers the server actually has configured. Asked rather than
  /// assumed, so a Google button is only offered when it would work.
  Future<Set<String>> enabledProviders() async {
    try {
      final res = await _dio.get('/settings');
      final external = (res.data as Map)['external'];
      if (external is! Map) return const {};
      return external.entries
          .where((e) => e.value == true)
          .map((e) => e.key.toString())
          .toSet();
    } on DioException {
      return const {};
    }
  }

  /// Start of a provider handshake. The caller opens this in a WebView and
  /// watches for [isOAuthReturn].
  Uri authorizeUrl(String provider) => Uri.parse('${Env.authBaseUrl}/authorize')
      .replace(
        queryParameters: {
          'provider': provider,
          'redirect_to': Env.oauthRedirect,
        },
      );

  static bool isOAuthReturn(Uri uri) {
    final expected = Uri.parse(Env.oauthRedirect);
    return uri.host == expected.host && uri.path.startsWith(expected.path);
  }

  /// Finishes a provider sign-in from the URL the WebView landed on.
  ///
  /// The handshake has no PKCE state, so GoTrue uses the implicit flow and puts
  /// everything in the URL fragment -- where every value is a string and there
  /// is no user object at all. The profile is fetched before the session is
  /// stored, because a session with no user has no id, and the id is what every
  /// user-scoped call keys on.
  Future<AuthSession> completeOAuth(Uri returned) async {
    final fragment = Uri.splitQueryString(returned.fragment);
    final error = fragment['error_description'] ?? fragment['error'];
    if (error != null) {
      throw ApiError(statusCode: null, message: error.replaceAll('+', ' '));
    }
    final access = fragment['access_token'];
    if (access == null || fragment['refresh_token'] == null) {
      throw const ApiError(
        statusCode: null,
        message: 'Sign-in did not complete. Please try again.',
      );
    }

    try {
      final me = await _dio.get(
        '/user',
        options: Options(headers: {'Authorization': 'Bearer $access'}),
      );
      // Not stored here, for the same reason as [signIn]: a provider sign-in
      // to an account with 2FA is `aal1` until the second factor is passed.
      return AuthSession.fromJson({
        ...fragment,
        'user': (me.data as Map).cast<String, dynamic>(),
      });
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// Checks a password without disturbing the session.
  ///
  /// GoTrue has no "verify my password" call, so this is the token grant used
  /// for what it proves rather than for what it returns: a wrong password is a
  /// 400 here exactly as it is at sign-in. The session it hands back is
  /// **deliberately dropped** -- adopting it would replace a working session
  /// with a new one in the middle of an operation that may still fail, and the
  /// point of asking is to guard the change, not to re-authenticate.
  ///
  /// Why ask at all, when `PUT /user` does not require it: without it, anyone
  /// who picks up an unlocked phone can change the password and keep the
  /// account. The storefront does not ask; that is a weakness of the
  /// storefront, not a contract this has to match.
  Future<void> verifyPassword({
    required String email,
    required String password,
  }) async {
    try {
      await _dio.post(
        '/token',
        queryParameters: {'grant_type': 'password'},
        data: {'email': email.trim(), 'password': password},
      );
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// Updates the signed-in user: their address, their password, or both.
  ///
  /// `PUT /user`, which is the same call the storefront's own account page
  /// makes to change a password. Returns the updated GoTrue user.
  ///
  /// **Email changes are not immediate.** GoTrue sends a confirmation link to
  /// the new address and leaves `email` as it was until the link is followed;
  /// what comes back carries the pending address in `new_email`. That is the
  /// existing verification flow, and the caller reports it rather than
  /// pretending the address changed.
  Future<Map<String, dynamic>> updateUser({
    String? email,
    String? password,
    Map<String, dynamic>? data,
  }) async {
    final session = await _sessions.read();
    if (session == null) {
      throw const ApiError(
        statusCode: 401,
        message: 'Sign in again to change your account details.',
      );
    }

    try {
      final res = await _dio.put(
        '/user',
        data: {'email': ?email?.trim(), 'password': ?password, 'data': ?data},
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
      final user = (res.data as Map).cast<String, dynamic>();
      // The stored session carries a copy of the user object, and the account
      // header is drawn from it. Left alone it would keep showing the old name
      // until the next sign-in.
      await _sessions.write(session.withUser(user));
      return user;
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// Re-reads the user from the server. Used after sign-in to pick up profile
  /// changes made elsewhere.
  Future<Map<String, dynamic>?> currentUser(String accessToken) async {
    try {
      final res = await _dio.get(
        '/user',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return (res.data as Map).cast<String, dynamic>();
    } on DioException {
      return null;
    }
  }

  /// Sends a six-digit code to an address the account is moving to.
  ///
  /// `POST /otp`. Nothing about the code exists in this app: it is generated
  /// and checked by the server, which is what makes this a verification rather
  /// than a screen that agrees with itself.
  ///
  /// GoTrue can be configured to mail a *link* instead, which is what
  /// [updateUser] with an email does and what `ProfileStore.changeEmail`
  /// already uses. A project set up that way refuses this, and the refusal is
  /// reported in its own words rather than guessed at.
  Future<void> sendEmailOtp(String email) async {
    try {
      await _dio.post('/otp', data: {'email': email.trim()});
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// Checks a code sent to a new address.
  ///
  /// `type: email_change` is GoTrue's name for a code sent to the address an
  /// account is moving to, as opposed to one signing in with a magic link.
  Future<Map<String, dynamic>> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    try {
      final res = await _dio.post(
        '/verify',
        data: {
          'type': 'email_change',
          'email': email.trim(),
          'token': token.trim(),
        },
      );
      final body = (res.data as Map).cast<String, dynamic>();
      final access = body['access_token'];
      if (access is String && access.isNotEmpty) {
        await _writeKeepingAssurance(AuthSession.fromJson(body));
      }
      return body['user'] is Map
          ? (body['user'] as Map).cast<String, dynamic>()
          : body;
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// The same read, for callers that hold no access token of their own.
  ///
  /// Null when nobody is signed in, which is a fact rather than a failure --
  /// the phone screens ask for the account's numbers before they know whether
  /// there is an account.
  Future<Map<String, dynamic>?> currentUserOrNull() async {
    final session = await _sessions.read();
    if (session == null) return null;
    return currentUser(session.accessToken);
  }

  /// Asks GoTrue to text a one-time code to [phone].
  ///
  /// `POST /otp`, which is where the code is generated and the SMS is sent.
  /// **Nothing about the code exists in this app** -- it is not returned, not
  /// stored and not checkable here, which is the property that makes this a
  /// real verification rather than a screen that agrees with itself.
  ///
  /// GoTrue rate-limits this per number and per project and answers 429 with
  /// how long to wait. That refusal is passed up untouched: the wait is the
  /// server's to set, and a client that invented its own would either nag a
  /// server that is still refusing or claim a number was sent one that was not.
  ///
  /// Sent with the session so the code is attached to *this* account rather
  /// than starting a passwordless sign-in for whoever owns the number.
  Future<void> sendPhoneOtp(String phone) async {
    final session = await _sessions.read();
    if (session == null) {
      throw const ApiError(
        statusCode: 401,
        message: 'Sign in again to change your phone number.',
      );
    }

    try {
      await _dio.post(
        '/otp',
        data: {'phone': phone.trim()},
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// Hands a typed code back to GoTrue, which decides.
  ///
  /// `POST /verify` with `type: sms`. A wrong code, an expired one and a code
  /// for a different number are all refused here, by the server, and arrive as
  /// an [ApiError] carrying its words.
  ///
  /// Returns the updated user. The session it answers with is written, because
  /// GoTrue issues a fresh token pair on a successful verify and the stored
  /// user object is what the rest of the app reads -- left alone, the account
  /// would go on believing the number was unconfirmed while the screen said it
  /// had been.
  Future<Map<String, dynamic>> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {
    try {
      final res = await _dio.post(
        '/verify',
        data: {
          'type': 'sms',
          'phone': phone.trim(),
          'token': token.trim(),
        },
      );
      final body = (res.data as Map).cast<String, dynamic>();

      final user = body['user'] is Map
          ? (body['user'] as Map).cast<String, dynamic>()
          : body;

      final access = body['access_token'];
      if (access is String && access.isNotEmpty) {
        await _writeKeepingAssurance(AuthSession.fromJson(body));
      } else {
        // Verified without a new session: keep the one we have but refresh its
        // copy of the user, so `phone_confirmed_at` is visible to everything
        // that reads the session.
        final current = await _sessions.read();
        if (current != null) {
          await _sessions.write(current.withUser(user));
        }
      }
      return user;
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// Stores a session minted by a code check, **without lowering assurance**.
  ///
  /// Verifying an email or phone code answers a fresh token pair at `aal1`.
  /// For an account that signed in through its second factor, storing that
  /// would quietly downgrade it to a password-level session. So when the
  /// stored session is the same account at `aal2` and the new one is not, the
  /// stored tokens are kept and only the user object is refreshed.
  Future<void> _writeKeepingAssurance(AuthSession fresh) async {
    final current = await _sessions.read();
    final sameAccount =
        current != null &&
        (fresh.userId == null || current.userId == fresh.userId);
    if (sameAccount &&
        MfaRepository.aalOf(current.accessToken) == 'aal2' &&
        MfaRepository.aalOf(fresh.accessToken) != 'aal2') {
      await _sessions.write(current.withUser(fresh.user ?? current.user!));
      return;
    }
    await _sessions.write(fresh);
  }
}
