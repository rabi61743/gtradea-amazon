import 'package:dio/dio.dart';

/// One error type for the whole app, because a screen should not have to know
/// whether it is holding a `DioException`, a `SocketException` or a Go handler's
/// error envelope to decide what to put on screen.
///
/// The gateway answers failures as `{"error": "..."}`; GoTrue uses the same
/// shape with `message` sometimes instead. Both land here as [message], which
/// is safe to show a shopper: these are server-authored strings, not stack
/// traces.
class ApiError implements Exception {
  const ApiError({
    required this.statusCode,
    required this.message,
    this.body,
  });

  /// Null when the request never reached the server at all.
  final int? statusCode;
  final String message;
  final Object? body;

  bool get isUnauthorized => statusCode == 401;

  /// No status means no response: airplane mode, dead wifi, DNS, a timeout.
  /// Worth separating because it is the one failure the shopper can fix.
  bool get isNetwork => statusCode == null;

  bool get isNotFound => statusCode == 404;

  factory ApiError.fromDio(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;

    final String message;
    if (data is Map && data['error'] is String) {
      message = data['error'] as String;
    } else if (data is Map && data['message'] is String) {
      message = data['message'] as String;
    } else if (data is Map && data['msg'] is String) {
      // GoTrue's own shape.
      message = data['msg'] as String;
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      message = 'The server took too long to answer. Try again.';
    } else if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown) {
      message = 'Cannot reach the server. Check your connection.';
    } else {
      message = e.message ?? 'Something went wrong.';
    }

    return ApiError(statusCode: status, message: message, body: data);
  }

  /// For the gateway's other failure convention: HTTP 200 carrying
  /// `{"success": false, "error": "..."}`. Rare, but it is how the 1688 product
  /// service reports a missing product, so it cannot be ignored.
  factory ApiError.fromEnvelope(Map body, {int status = 400}) {
    final raw = body['error'] ?? body['message'];
    return ApiError(
      statusCode: status,
      message: raw is String ? raw : 'Something went wrong.',
      body: body,
    );
  }

  @override
  String toString() => 'ApiError($statusCode): $message';
}
