import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_error.dart';
import '../../product/data/storefront_config.dart';

/// How the shopper wants this order carried, and what the shop offers.
///
/// One answer for the whole app. The product page chooses it, the cart prices
/// freight with it and the checkout sends it as `shippingMode`, so the mode a
/// shopper picked on a product page is the mode their order is actually placed
/// under -- not a label on a card.
///
/// The options themselves are the shop's, read from the site settings by
/// [StorefrontConfigRepository.logistics]. Nothing is named here: if the shop
/// publishes two modes there are two, if it renames one the app renames it,
/// and if it publishes none there is nothing to choose.
class ShippingModeStore extends ChangeNotifier {
  ShippingModeStore._();

  static final ShippingModeStore instance = ShippingModeStore._();

  static const _prefsKey = 'shipping_mode';

  /// What the shop publishes. Empty until [load] has answered.
  List<LogisticsMode> get modes => _config.modes;
  LogisticsConfig get config => _config;
  LogisticsConfig _config = const LogisticsConfig();

  /// True while the options are being read.
  bool get isLoading => _loading;
  bool _loading = false;

  /// Why the options could not be read, if they could not be.
  ApiError? get error => _error;
  ApiError? _error;

  /// The chosen mode's key. Null when the shop publishes nothing, or before
  /// the settings have arrived.
  String? get selectedKey => _selectedKey;
  String? _selectedKey;

  /// The chosen mode itself, or null when there is nothing to choose.
  LogisticsMode? get selected {
    for (final mode in _config.modes) {
      if (mode.key == _selectedKey) return mode;
    }
    return _config.modes.isEmpty ? null : _config.modes.first;
  }

  /// What checkout should be told to ship by.
  ///
  /// Falls back to `air` only when the shop has published nothing at all --
  /// that is the value this app sent before there was a choice, so a storefront
  /// with no modes configured behaves exactly as it did.
  String get checkoutMode => selected?.key ?? 'air';

  bool _loaded = false;

  /// Reads the options once, and restores what the shopper last chose.
  ///
  /// Safe to call from every product page: the second call is free, and a
  /// failed first call can be retried by passing [force].
  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (_loaded && !force && _error == null) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final config = await StorefrontConfigRepository.instance.logistics();
      _config = config;
      _loaded = true;

      final saved = _saved ?? await _readSaved();
      // A saved choice only stands while the shop still offers it. A mode
      // that has been withdrawn cannot quietly remain selected -- the order
      // would be placed under something the shop no longer carries.
      final stillOffered = config.modes.any((mode) => mode.key == saved);
      _selectedKey = stillOffered
          ? saved
          : (config.modes.isEmpty ? null : config.modes.first.key);
    } on ApiError catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  String? _saved;

  Future<String?> _readSaved() async {
    final prefs = await SharedPreferences.getInstance();
    return _saved = prefs.getString(_prefsKey);
  }

  /// Chooses a mode the shop actually offers.
  ///
  /// Silently ignores anything else: a key that is not on the published list
  /// would be sent to checkout as a shipping mode the shop does not carry.
  void select(String key) {
    if (_selectedKey == key) return;
    if (!_config.modes.any((mode) => mode.key == key)) return;

    _selectedKey = key;
    _saved = key;
    notifyListeners();
    // Fire and forget, as the rest of the app's preferences are: the choice is
    // already live in memory, and a slow disk should not hold up the flyout.
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setString(_prefsKey, key),
    );
  }

  @visibleForTesting
  void resetForTest() {
    _config = const LogisticsConfig();
    _selectedKey = null;
    _saved = null;
    _loaded = false;
    _loading = false;
    _error = null;
  }
}
