import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/json.dart';
import 'popup_banner.dart';

/// The startup popup: what the admin has set, and whether this launch has
/// already dealt with it.
///
/// Silent on every failure. A popup is never worth an error message, so a
/// gateway that is down, a setting that is null or a value that does not
/// decode all mean the same thing -- nothing to show.
class PopupBannerStore extends ChangeNotifier {
  PopupBannerStore._();

  static final PopupBannerStore instance = PopupBannerStore._();

  static const settingKey = 'app_popup_banner';

  Dio get _dio => ApiClient.http;

  PopupBanner? _banner;
  bool _loaded = false;
  Future<void>? _inFlight;

  /// Whether this launch has already decided about the popup, shown or not.
  ///
  /// Held in memory on the singleton on purpose: it lives exactly as long as
  /// the app's process. A fresh launch from a closed app is a new process and
  /// starts false, so the popup shows again. Returning from the background,
  /// moving between pages or the home screen being rebuilt all happen inside
  /// the same process, where this is already true -- so none of them can show
  /// it a second time.
  bool _launchHandled = false;

  bool get isLoaded => _loaded;
  PopupBanner? get banner => _banner;
  bool get launchHandled => _launchHandled;

  /// Loaded, and live today.
  bool shouldShow([DateTime? now]) {
    final banner = _banner;
    if (!_loaded || banner == null) return false;
    return banner.isLive(now ?? DateTime.now());
  }

  /// Claims this launch's one decision. True only the first time per process.
  bool claimLaunch() {
    if (_launchHandled) return false;
    _launchHandled = true;
    return true;
  }

  Future<void> load() => _inFlight ??= _load();

  Future<void> _load() async {
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

    _banner = banner;
    _loaded = true;
    notifyListeners();
  }

  /// A fresh process, for tests: what a cold launch starts from.
  @visibleForTesting
  void resetForTest() {
    _banner = null;
    _loaded = false;
    _inFlight = null;
    _launchHandled = false;
  }
}
