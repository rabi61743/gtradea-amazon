import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/env.dart';
import '../network/session_store.dart';

/// Something the server says has happened.
///
/// Deliberately not a typed union. The server owns this vocabulary and adds to
/// it; the app routes on a prefix and ignores what it does not recognise,
/// rather than failing to decode a message it was not expecting.
@immutable
class RealtimeEvent {
  const RealtimeEvent({required this.name, this.orderId, this.raw = const {}});

  /// e.g. `order.shipped`, `order_status`, `notification.created`.
  final String name;

  /// The order this is about, when the frame says.
  ///
  /// Worth extracting even though most frames omit it: with an id, the open
  /// order can be refreshed rather than only the list behind it.
  final String? orderId;

  final Map<String, dynamic> raw;

  bool get isOrder => name.startsWith('order');
  bool get isNotification => name.startsWith('notification');

  @override
  String toString() => 'RealtimeEvent($name, order: $orderId)';
}

/// The live channel to the gateway.
///
/// One socket for the signed-in shopper, carrying cache-invalidation signals
/// rather than data: a frame says something changed, and the app asks over
/// HTTP what it changed to. That keeps one source of truth for every payload.
///
/// The sibling app has a version of this with a set of quiet failure modes
/// that are all fixed here rather than inherited -- each one is commented at
/// the point it is handled, because none of them are obvious from the outside:
/// a socket that looks healthy forever and delivers nothing is the worst shape
/// this can take.
class RealtimeService {
  RealtimeService._();

  static final RealtimeService instance = RealtimeService._();

  /// Switched off in tests.
  ///
  /// A widget test has no gateway to reach, so binding would schedule a
  /// reconnect and leave a pending timer that fails the test for a reason that
  /// has nothing to do with what it was checking.
  @visibleForTesting
  static bool enabled = true;

  final _events = StreamController<RealtimeEvent>.broadcast();

  Stream<RealtimeEvent> get events => _events.stream;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _stallTimer;
  _Lifecycle? _lifecycle;

  int _attempt = 0;
  bool _closed = true;
  String? _connectedUserId;

  /// True once a frame has arrived on this connection.
  ///
  /// The backoff resets on this rather than on the socket opening. A gateway
  /// that accepts the upgrade and then drops the connection -- a rejected
  /// token, most often -- would otherwise reset the counter every cycle and
  /// turn the backoff into a one-second reconnect loop forever.
  bool _proved = false;

  /// If nothing arrives for this long, the connection is presumed dead.
  ///
  /// Half-open sockets are the normal outcome of a phone changing network or
  /// sleeping: no close frame is ever delivered, so without this the app would
  /// sit on a silent socket believing it was live.
  static const _stallAfter = Duration(minutes: 5);

  /// Starts following the signed-in shopper.
  ///
  /// Idempotent. Connects when there is a session, disconnects when there is
  /// not, and reconnects when the account changes.
  void bind(Listenable auth, {required String? Function() userId}) {
    if (!enabled) return;
    _userId = userId;
    auth.addListener(_onAuthChanged);
    _lifecycle ??= _Lifecycle(onResume: _onResume)..attach();
    _onAuthChanged();
  }

  String? Function()? _userId;

  void _onAuthChanged() {
    final id = _userId?.call();
    if (id == null) {
      _teardown();
      return;
    }
    if (id == _connectedUserId && _channel != null) return;
    _connectedUserId = id;
    _closed = false;
    _attempt = 0;
    unawaited(_connect());
  }

  /// Coming back from the background.
  ///
  /// The OS tears sockets down while an app is suspended and frequently does
  /// so without delivering a close, so resume is treated as "assume it is
  /// gone" rather than trusting the stream to have noticed.
  void _onResume() {
    if (_closed || _connectedUserId == null) return;
    _attempt = 0;
    unawaited(_reconnect());
  }

  Future<void> _connect() async {
    if (_closed) return;

    final session = await SessionStore.instance.read();
    final token = session?.accessToken;
    final uid = session?.userId;

    // Re-checked after the await: close() may have run while the keystore was
    // being read, and connecting after that leaks a socket nobody will close.
    if (_closed) return;

    if (token == null || uid == null) {
      // Reachable mid-session, not only when signed out: a refresh can fail
      // and clear the session underneath. Retrying rather than returning
      // silently is what stops the socket disappearing until the next sign-in.
      _scheduleReconnect();
      return;
    }

    await _dropConnection();

    try {
      final uri = Uri.parse('${Env.realtimeUrl}?token=$token');
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready;
      if (_closed) {
        await _dropConnection();
        return;
      }

      _subscription = channel.stream.listen(
        _onFrame,
        onDone: _scheduleReconnect,
        onError: (Object _) => _scheduleReconnect(),
        // False on purpose: an error is handled by reconnecting, and letting
        // the subscription cancel itself would leave the channel open with
        // nothing listening to it.
        cancelOnError: false,
      );

      _send({'type': 'subscribe', 'topic': 'realtime:user:$uid'});
      _armStallTimer();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onFrame(dynamic raw) {
    _armStallTimer();

    if (raw is! String) {
      // A binary frame is not something this protocol uses. Ignored, but the
      // connection is proved alive by it arriving at all.
      _proved = true;
      _attempt = 0;
      return;
    }

    Map<String, dynamic> frame;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('not an object');
      frame = decoded.cast<String, dynamic>();
    } catch (_) {
      _log('dropped a frame that was not JSON');
      return;
    }

    if (frame['type'] == 'control') {
      // The subscribe acknowledgement, or a refusal. A refusal matters: the
      // socket stays open and delivers nothing forever, which from the client
      // side is indistinguishable from a quiet week.
      final error = frame['error'];
      if (error != null) {
        _log('subscribe refused: $error');
        _scheduleReconnect();
        return;
      }
      _proved = true;
      _attempt = 0;
      return;
    }

    _proved = true;
    _attempt = 0;

    final name = (frame['event'] ?? frame['type'] ?? '').toString();
    if (name.isEmpty) return;

    final payload = frame['payload'] is Map
        ? (frame['payload'] as Map).cast<String, dynamic>()
        : frame;

    _events.add(
      RealtimeEvent(
        name: name,
        orderId: _firstString(payload, const ['order_id', 'orderId', 'id']),
        raw: frame,
      ),
    );
  }

  static String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  void _send(Map<String, dynamic> message) {
    final sink = _channel?.sink;
    if (sink == null) {
      _scheduleReconnect();
      return;
    }
    try {
      sink.add(jsonEncode(message));
    } catch (_) {
      // The sink closed between opening and subscribing. Left unhandled this
      // ends up connected but subscribed to nothing.
      _scheduleReconnect();
    }
  }

  /// Reconnects after a delay that grows, then flattens.
  void _scheduleReconnect() {
    if (_closed || _reconnectTimer != null) return;
    _attempt++;
    final seconds = _attempt >= 6 ? 30 : 1 << (_attempt - 1);
    _log('reconnecting in ${seconds}s (attempt $_attempt)');
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      unawaited(_connect());
    });
  }

  Future<void> _reconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _connect();
  }

  void _armStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer(_stallAfter, () {
      _log('no traffic for ${_stallAfter.inMinutes} minutes, reconnecting');
      unawaited(_reconnect());
    });
  }

  /// Closes the current socket and forgets it, without ending the service.
  ///
  /// Both the subscription and the channel: cancelling the subscription alone
  /// leaves the socket open, and every reconnect would orphan another one.
  Future<void> _dropConnection() async {
    _stallTimer?.cancel();
    _stallTimer = null;
    _proved = false;

    final sub = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;

    await sub?.cancel();
    try {
      await channel?.sink.close(ws_status.normalClosure);
    } catch (_) {
      // Already gone.
    }
  }

  void _teardown() {
    _closed = true;
    _connectedUserId = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_dropConnection());
  }

  /// Stops for good. Signing out, or the app shutting down.
  Future<void> close() async {
    _teardown();
    _lifecycle?.detach();
    _lifecycle = null;
  }

  void _log(String message) {
    assert(() {
      debugPrint('[realtime] $message');
      return true;
    }());
  }

  @visibleForTesting
  bool get isConnected => _channel != null;

  @visibleForTesting
  bool get hasProvedAlive => _proved;

  @visibleForTesting
  void emitForTest(RealtimeEvent event) => _events.add(event);

  @visibleForTesting
  Future<void> resetForTest() async {
    _userId = null;
    _attempt = 0;
    await close();
    _closed = true;
  }
}

/// Watches for the app coming back to the foreground.
class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle({required this.onResume});

  final VoidCallback onResume;

  void attach() => WidgetsBinding.instance.addObserver(this);
  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
