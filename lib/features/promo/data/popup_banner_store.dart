import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import 'popup_banner.dart';

/// The startup popup: what the admin has set, and whether this device has
/// already closed it.
///
/// Silent on every failure. A popup is never worth an error message, so a
/// gateway that is down, a setting that is null or a value that does not
/// decode all mean the same thing -- nothing to show.
class PopupBannerStore extends ChangeNotifier {
  PopupBannerStore._();

  static final PopupBannerStore instance = PopupBannerStore._();

  static const settingKey = 'app_popup_banner';
  static const _seenKey = 'gtradea_popup_seen';

  Dio get _dio => ApiClient.http;

  PopupBanner? _banner;
  Set<String> _seen = const {};
  bool _loaded = false;
  Future<void>? _inFlight;

  bool get isLoaded => _loaded;
  PopupBanner? get banner => _banner;

  /// Loaded, live today, and not closed on this device before.
  bool shouldShow([DateTime? now]) {
    final banner = _banner;
    if (!_loaded || banner == null) return false;
    if (_seen.contains(banner.id)) return false;
    return banner.isLive(now ?? DateTime.now());
  }

  Future<void> load() => _inFlight ??= _load();

  Future<void> _load() async {
    var seen = <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      seen = (prefs.getStringList(_seenKey) ?? const []).toSet();
    } catch (_) {
      // Unreadable: nothing remembered, so the popup can show once more.
    }

    PopupBanner? banner;
    try {
      banner = await guarded(() async {
        final res = await _dio.get(
          '/site-settings/$settingKey',
          options: guestCall,
        );
        final body = asMap(res.data);
        Object? value = body.containsKey('setting_value')
            ? body['setting_value']
            : body;
        // Stored as text by some admin tools, as JSON by others.
        if (value is String && value.trim().isNotEmpty) {
          value = jsonDecode(value);
        }
        return PopupBanner.fromJson(value);
      });
    } catch (_) {
      banner = null;
    }

    _seen = seen;
    _banner = banner;
    _loaded = true;
    notifyListeners();
  }

  /// Remembers that this campaign was closed or followed, so it stays gone.
  Future<void> markSeen(String id) async {
    if (_seen.contains(id)) return;
    _seen = {..._seen, id};
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_seenKey, _seen.toList());
    } catch (_) {
      // Best effort: the cost of a failed write is seeing it once more.
    }
  }

  @visibleForTesting
  void resetForTest() {
    _banner = null;
    _seen = const {};
    _loaded = false;
    _inFlight = null;
  }
}
