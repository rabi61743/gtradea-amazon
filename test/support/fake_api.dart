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

  final _routes = <String, _Handler>{};

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
    _routes['${method.toUpperCase()} $path'] =
        (_) => _Reply(status: status, body: body, headers: headers);
  }

  /// For answers that depend on the request, or that change between calls (a
  /// 401 first and a 200 after a refresh, say).
  void onCall(String method, String path, _Handler handler) {
    _routes['${method.toUpperCase()} $path'] = handler;
  }

  Dio dio({String baseUrl = 'https://test.local/api/v1'}) {
    final dio = Dio(BaseOptions(baseUrl: baseUrl, contentType: 'application/json'))
      ..httpClientAdapter = this;
    return dio;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final call = RecordedCall(
      method: options.method.toUpperCase(),
      path: options.path,
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

typedef _Handler = _Reply Function(RecordedCall call);

class _Reply {
  const _Reply({required this.status, this.body, this.headers});

  final int status;
  final Object? body;
  final Map<String, List<String>>? headers;
}

/// A reply built inside an [FakeApi.onCall] handler.
_Reply reply(Object? body, {int status = 200}) =>
    _Reply(status: status, body: body);

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
