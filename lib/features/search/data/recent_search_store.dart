import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The queries this shopper has run, newest first.
///
/// Local, and staying local: the API has no search-history endpoint, and
/// inventing one client-side that pretended to sync would be worse than an
/// honest device-only list. It also means a shared phone does not leak one
/// person's searches to the next -- there is nothing to leak from a server.
class RecentSearchStore extends ChangeNotifier {
  RecentSearchStore._();

  static final instance = RecentSearchStore._();

  static const _key = 'gtradea_recent_searches';
  static const _limit = 8;

  List<String> _queries = const [];
  bool _loaded = false;

  List<String> get queries => _queries;
  bool get isEmpty => _queries.isEmpty;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _queries = decoded.whereType<String>().take(_limit).toList();
        }
      }
    } catch (_) {
      // An unreadable list is an empty list. Nothing here is worth a failure.
    }
    notifyListeners();
  }

  void record(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    // Case-insensitive, so "shoes" typed again moves the existing entry to the
    // front rather than sitting beside "Shoes".
    final lower = trimmed.toLowerCase();
    _queries = [
      trimmed,
      ..._queries.where((q) => q.toLowerCase() != lower),
    ].take(_limit).toList(growable: false);
    _loaded = true;
    notifyListeners();
    unawaited(_persist());
  }

  void clear() {
    _queries = const [];
    _loaded = true;
    notifyListeners();
    unawaited(_persist());
  }

  @visibleForTesting
  void resetForTest() {
    _queries = const [];
    _loaded = false;
  }

  Future<void> _persist() async {
    final payload = jsonEncode(_queries);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, payload);
    } catch (_) {
      // Best effort, like every other convenience cache in the app.
    }
  }
}
