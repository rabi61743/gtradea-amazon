import 'package:dio/dio.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/session_store.dart';

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

  Future<AuthSession> signIn(String email, String password) async {
    try {
      final res = await _dio.post(
        '/token',
        queryParameters: {'grant_type': 'password'},
        data: {'email': email.trim(), 'password': password},
      );
      final session = AuthSession.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
      await _sessions.write(session);
      return session;
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
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
  Future<void> recover(String email) async {
    try {
      await _dio.post('/recover', data: {'email': email.trim()});
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  Future<void> signOut() async {
    final session = await _sessions.read();
    if (session != null) {
      try {
        await _dio.post(
          '/logout',
          options: Options(
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          ),
        );
      } on DioException {
        // Best effort. The local clear below is what actually signs them out;
        // failing that over a dropped connection would trap them signed in.
      }
    }
    await _sessions.clear();
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
      final session = AuthSession.fromJson({
        ...fragment,
        'user': (me.data as Map).cast<String, dynamic>(),
      });
      await _sessions.write(session);
      return session;
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
}
