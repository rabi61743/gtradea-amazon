import 'dart:async';

import 'package:dio/dio.dart';

import '../config/env.dart';
import 'session_store.dart';

/// Puts the bearer token on outgoing requests and quietly renews it when it has
/// run out.
///
/// A [QueuedInterceptor] rather than a plain one so requests are handled in
/// order: several screens loading at once would otherwise each notice the same
/// expired token and each start their own refresh.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this._sessions);

  final SessionStore _sessions;

  /// The refresh call goes out on its own Dio with no interceptors, because a
  /// refresh that went through this one would refresh in order to refresh.
  final Dio _refreshDio = Dio(
    BaseOptions(
      baseUrl: Env.authBaseUrl,
      connectTimeout: Env.requestTimeout,
      receiveTimeout: Env.requestTimeout,
    ),
  );

  Future<AuthSession?>? _inflightRefresh;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // The catalogue is public. Sending a token with it would work, but it means
    // a guest browsing session carries a credential it has no use for.
    if (options.extra['skipAuth'] == true) {
      return handler.next(options);
    }

    var session = await _sessions.read();

    // Refresh before sending rather than after being refused: a 401 costs a
    // round trip, and on a slow connection that is a visible stall.
    if (session != null && session.isExpired) {
      session = await _refresh(session.refreshToken);
    }
    if (session != null) {
      options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final req = err.requestOptions;
    final refusable = err.response?.statusCode == 401 &&
        req.extra['retried'] != true &&
        req.extra['skipAuth'] != true;

    if (!refusable) return handler.next(err);

    // A multipart body is a one-shot stream: Dio finalises it on send, so
    // replaying the same RequestOptions would post an empty body and the
    // failure would look like a server bug. Let the caller retry instead.
    if (req.data is FormData) return handler.next(err);

    final session = await _sessions.read();
    if (session == null) return handler.next(err);

    final refreshed = await _refresh(session.refreshToken);
    if (refreshed == null) return handler.next(err);

    req.extra['retried'] = true;
    req.headers['Authorization'] = 'Bearer ${refreshed.accessToken}';
    try {
      // Replayed on the bare Dio so it does not queue behind itself.
      return handler.resolve(await _refreshDio.fetch(req));
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  /// One refresh at a time. Callers that arrive while one is in flight wait for
  /// its answer instead of asking again -- a rotating refresh token would treat
  /// the second ask as a replay and kill the session.
  Future<AuthSession?> _refresh(String refreshToken) {
    return _inflightRefresh ??= _doRefresh(refreshToken).whenComplete(() {
      _inflightRefresh = null;
    });
  }

  Future<AuthSession?> _doRefresh(String refreshToken) async {
    if (refreshToken.isEmpty) {
      await _sessions.clear(notify: true);
      return null;
    }
    try {
      final res = await _refreshDio.post(
        '/token',
        queryParameters: {'grant_type': 'refresh_token'},
        data: {'refresh_token': refreshToken},
      );
      final session =
          AuthSession.fromJson((res.data as Map).cast<String, dynamic>());
      await _sessions.write(session);
      return session;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Only a refusal means the token is dead. A timeout means the network is
      // down, and throwing the session away over a flaky connection would sign
      // people out on the train.
      if (status != null && status >= 400 && status < 500) {
        await _sessions.clear(notify: true);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
