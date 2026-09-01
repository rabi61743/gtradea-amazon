import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A stand-in server.
///
/// Tests register handlers by method and path and get a Dio that answers from
/// them, so the data layer can be exercised end to end -- interceptors,
/// refresh, error mapping and all -- without a network.
class FakeApi implements HttpClientAdapter {
  FakeApi();

  final _routes = <String, FakeHandler>{};

  /// Every request that reached this adapter, in order. The point of recording
  /// them is that most of what is worth asserting about a repository is what it
  /// *sent*, not what it did with the reply.
  final calls = <RecordedCall>[];

  void on(
    String method,
    String path, {
    Object? body,
    int status = 200,
    Map<String, List<String>>? headers,
  }) {
    // Keyed by path whether the caller wrote a path or a full URL, matching
    // the same normalisation applied to incoming requests below. Several
    // services sit outside the versioned API and are registered -- and called
    // -- with an absolute URL.
    _routes['${method.toUpperCase()} ${_pathOf(path)}'] = (_) =>
        FakeReply(status: status, body: body, headers: headers);
  }

  /// For answers that depend on the request, or that change between calls (a
  /// 401 first and a 200 after a refresh, say).
  void onCall(String method, String path, FakeHandler handler) {
    _routes['${method.toUpperCase()} ${_pathOf(path)}'] = handler;
  }

  Dio dio({String baseUrl = 'https://test.local/api/v1'}) {
    final dio = Dio(
      BaseOptions(baseUrl: baseUrl, contentType: 'application/json'),
    )..httpClientAdapter = this;
    return dio;
  }

  static String _pathOf(String pathOrUrl) {
    if (!pathOrUrl.startsWith('http')) return pathOrUrl;
    return Uri.tryParse(pathOrUrl)?.path ?? pathOrUrl;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final call = RecordedCall(
      method: options.method.toUpperCase(),
      // Absolute URLs are reduced to their path, so a route registered as
      // '/api/1688/image-search' matches whether the caller used a path or a
      // full URL. Some services sit outside the versioned API and are called
      // with an absolute URL to override the Dio base; without this they miss
      // every route and look like a missing endpoint.
      path: _pathOf(options.path),
      query: Map<String, dynamic>.from(options.queryParameters),
      body: options.data,
      headers: Map<String, dynamic>.from(options.headers),
    );
    calls.add(call);

    final handler = _routes['${call.method} ${call.path}'];
    if (handler == null) {
      return ResponseBody.fromString(
        jsonEncode({'error': 'no fake route for ${call.method} ${call.path}'}),
        404,
        headers: _jsonHeaders,
      );
    }

    final reply = handler(call);

    // A reply that takes time, and a caller that can give up on it.
    //
    // Both are needed to test anything about latency: the typeahead's two
    // endpoints differ by more than a second in production, and the whole point
    // of splitting them is that the fast one is not held behind the slow one.
    // Without a delay here every stub answers in the same microtask and that
    // difference cannot be expressed.
    final delay = reply.delay;
    if (delay != null) {
      // A timer that is actually cancelled, not a `Future.any` race.
      //
      // `Future.any` abandons the loser but leaves it running, so a cancelled
      // request left its delay ticking and every test that ended before it
      // fired failed with "pending timers" -- a harness artefact reported as a
      // leak in the app.
      //
      // `cancelFuture` is dio's own signal, completed when the caller's
      // CancelToken fires, so this behaves the way the real client does rather
      // than approximating it.
      final settled = Completer<bool>();
      final timer = Timer(delay, () {
        if (!settled.isCompleted) settled.complete(false);
      });
      unawaited(
        cancelFuture?.then((_) {
          if (settled.isCompleted) return;
          timer.cancel();
          settled.complete(true);
        }),
      );

      if (await settled.future) {
        throw DioException.requestCancelled(
          requestOptions: options,
          reason: 'cancelled',
        );
      }
    }

    return ResponseBody.fromString(
      reply.body == null ? '' : jsonEncode(reply.body),
      reply.status,
      headers: reply.headers ?? _jsonHeaders,
    );
  }

  @override
  void close({bool force = false}) {}

  static const _jsonHeaders = {
    Headers.contentTypeHeader: ['application/json'],
  };
}

typedef FakeHandler = FakeReply Function(RecordedCall call);

class FakeReply {
  const FakeReply({required this.status, this.body, this.headers, this.delay});

  final int status;
  final Object? body;
  final Map<String, List<String>>? headers;

  /// How long the server takes to answer. Null answers immediately, which is
  /// what almost every test wants.
  final Duration? delay;
}

/// A reply built inside an [FakeApi.onCall] handler.
FakeReply reply(Object? body, {int status = 200, Duration? delay}) =>
    FakeReply(status: status, body: body, delay: delay);

class RecordedCall {
  RecordedCall({
    required this.method,
    required this.path,
    required this.query,
    required this.body,
    required this.headers,
  });

  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Object? body;
  final Map<String, dynamic> headers;

  Map<String, dynamic> get json =>
      body is Map ? (body as Map).cast<String, dynamic>() : const {};

  String? get authorization => headers['Authorization'] as String?;

  @override
  String toString() => '$method $path';
}
