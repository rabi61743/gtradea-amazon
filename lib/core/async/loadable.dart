import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_error.dart';

/// One piece of server data and everything the UI needs to know about it.
///
/// The app has no state-management package, and this is the whole reason it
/// does not need one: every screen section owns a [Loadable], listens to it,
/// and renders the three states honestly. Sections load independently, so one
/// failing rail shows a retry inside itself rather than blanking the page.
///
/// Optionally remembers its last good answer on disk, so a returning shopper
/// sees the catalogue immediately and a dead connection shows yesterday's
/// products rather than a spinner over nothing.
class Loadable<T> extends ChangeNotifier {
  Loadable(this._fetch, {this.cacheKey, this.encode, this.decode});

  final Future<T> Function() _fetch;

  /// Where the last good answer is kept. Null means do not cache -- correct for
  /// anything personal or fast-moving.
  final String? cacheKey;

  final Object? Function(T value)? encode;
  final T Function(Object json)? decode;

  T? _value;
  ApiError? _error;
  bool _loading = false;
  bool _everLoaded = false;

  /// True when this value came off disk and no server answer has landed yet.
  bool _stale = false;

  T? get value => _value;
  ApiError? get error => _error;
  bool get isLoading => _loading;
  bool get hasValue => _value != null;
  bool get isStale => _stale;

  /// The first load. Idempotent, so a rebuilding widget can call it in
  /// `initState` without guarding.
  Future<void> load() {
    if (_everLoaded || _loading) return Future.value();
    return refresh();
  }

  /// Show what is held, and quietly go and check.
  ///
  /// For data that is cached to disk and changes on the server without the app
  /// being told -- the department tree is the case this exists for. [load]
  /// alone never revalidates: it returns early once anything has loaded, so a
  /// cached tree would go on being shown until the app was restarted, and an
  /// edit made in the backoffice would be invisible.
  ///
  /// Returns immediately when there is something to paint. The fetch runs
  /// behind it and swaps the value in if it differs, so there is no spinner
  /// over data the shopper can already see.
  Future<void> revalidate() {
    if (_loading) return Future.value();

    // Nothing to show yet: behave exactly like `load`, spinner and all.
    // Deferring this one instead would blank the screen for a turn, and
    // whatever `empty` says would flash before the spinner replaced it.
    if (!_everLoaded && _value == null) return refresh();

    // Deferred, because this is called from `build`. `refresh` notifies its
    // listeners on the way in, and notifying during a build asks every other
    // widget listening to this same store to rebuild while the framework is
    // already building -- which is an assertion, not a warning. A microtask
    // puts it after the frame, where a state change belongs.
    unawaited(Future.microtask(refresh));
    return Future.value();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    // Paint something while the network runs, but only on the first load --
    // a refresh already has fresher data on screen than the cache does.
    if (!_everLoaded && _value == null) {
      unawaited(_readCache());
    }

    try {
      final result = await _fetch();
      _value = result;
      _error = null;
      _stale = false;
      _everLoaded = true;
      unawaited(_writeCache(result));
    } on ApiError catch (e) {
      _error = e;
      _everLoaded = true;
    } catch (e) {
      _error = ApiError(statusCode: null, message: e.toString());
      _everLoaded = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Drops what is held so the next [load] goes back to the server. Used when
  /// the signed-in account changes: one shopper's data must not survive into
  /// another's session.
  void invalidate() {
    _value = null;
    _error = null;
    _everLoaded = false;
    _stale = false;
    // The disk copy goes too. Clearing memory alone left the next load reading
    // the departed account's data straight back off disk, which is the one
    // thing this method exists to prevent.
    unawaited(_clearCache());
    notifyListeners();
  }

  Future<void> _readCache() async {
    final key = cacheKey;
    final decoder = decode;
    if (key == null || decoder == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cache_$key');
      if (raw == null || _value != null) return;
      _value = decoder(jsonDecode(raw) as Object);
      _stale = true;
      notifyListeners();
    } catch (_) {
      // A cache that will not decode is a cache worth ignoring.
    }
  }

  Future<void> _clearCache() async {
    final key = cacheKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cache_$key');
    } catch (_) {
      // Best effort, like the write.
    }
  }

  Future<void> _writeCache(T value) async {
    final key = cacheKey;
    final encoder = encode;
    if (key == null || encoder == null) return;
    try {
      final payload = encoder(value);
      if (payload == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cache_$key', jsonEncode(payload));
    } catch (_) {
      // Best effort. Losing the cache costs a spinner, never the data.
    }
  }
}
