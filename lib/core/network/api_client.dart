import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/env.dart';
import 'api_error.dart';
import 'auth_interceptor.dart';
import 'session_store.dart';

/// The one HTTP client.
///
/// Single instance so connections are pooled and, more importantly, so there is
/// exactly one [AuthInterceptor] -- its single-flight refresh only prevents a
/// stampede if every request goes through the same one.
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  late final Dio dio = _build();

  Dio _build() {
    final dio = Dio(
      BaseOptions(
        baseUrl: Env.apiRoot,
        connectTimeout: Env.requestTimeout,
        receiveTimeout: Env.requestTimeout,
        sendTimeout: Env.requestTimeout,
        contentType: 'application/json',
        responseType: ResponseType.json,
      ),
    );

    dio.interceptors.add(AuthInterceptor(SessionStore.instance));

    assert(() {
      dio.interceptors.add(LogInterceptor(
        requestHeader: false,
        responseHeader: false,
        responseBody: false,
        requestBody: false,
        logPrint: (o) => debugPrint('[api] $o'),
      ));
      return true;
    }());

    return dio;
  }

  /// Swaps in a stub for tests. Repositories talk to `ApiClient.instance.dio`,
  /// so this is the single seam the whole data layer can be faked at.
  @visibleForTesting
  static Dio? overrideDio;

  static Dio get http => overrideDio ?? instance.dio;
}

/// Turns whatever went wrong into an [ApiError], so no caller ever has to
/// catch `DioException` itself.
Future<T> guarded<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DioException catch (e) {
    throw ApiError.fromDio(e);
  } on ApiError {
    rethrow;
  } catch (e, stack) {
    // Something in our own decoding threw. Reported as a distinct kind of
    // failure: it arrives with no status code, exactly like a dead connection,
    // and without the flag the screen tells a shopper on full signal to check
    // their network.
    assert(() {
      debugPrint('[api] failed inside the app: $e\n$stack');
      return true;
    }());
    throw ApiError(
      statusCode: null,
      message: 'Something went wrong loading this.',
      body: e,
      local: true,
    );
  }
}

/// Options for a call that is public and should not carry a credential.
final guestCall = Options(extra: const {'skipAuth': true});
