import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_store.dart';

/// History rows this shopper has hidden from their own view.
///
/// **Nothing here touches the server.** The rows stay in `/product-views`
/// exactly as they were; this is a list of what not to draw, kept on this
/// device and keyed to the account so one person's hidden rows are never
/// another's. Signing in on a second phone shows the full history again, which
/// is the honest consequence of a view-side setting rather than a deletion.
///
/// Persisted, because a hidden row that came back on the next open would read
/// as the delete having failed.
class HiddenHistoryStore extends ChangeNotifier {
  HiddenHistoryStore._();

  static final instance = HiddenHistoryStore._();

  static const _prefix = 'gtradea_hidden_history_';

  final Set<String> _hidden = {};
  String? _loadedFor;

  /// The key a row is hidden by: the product and the moment it was opened, so
  /// hiding one visit does not hide the next one to the same product.
  static String keyFor({required String productId, required DateTime at}) =>
      '$productId|${at.toUtc().toIso8601String()}';

  /// Which account's list is in memory. Null when signed out -- there is no
  /// history to hide then.
  static String? get _account => AuthStore.instance.account?.id;

  bool isHidden(String key) => _hidden.contains(key);

  int get count => _hidden.length;

  /// Reads this account's list, once per account.
  ///
  /// Re-read when the signed-in account changes: the previous shopper's hidden
  /// rows must not filter this one's history.
  Future<void> load() async {
    final account = _account;
    if (account == null) {
      if (_hidden.isEmpty && _loadedFor == null) return;
      _hidden.clear();
      _loadedFor = null;
      notifyListeners();
      return;
    }
    if (_loadedFor == account) return;

    _hidden
      ..clear()
      ..addAll(
        (await SharedPreferences.getInstance()).getStringList(
              '$_prefix$account',
            ) ??
            const [],
      );
    _loadedFor = account;
    notifyListeners();
  }

  /// Hides [keys] from this shopper's own history.
  Future<void> hide(Iterable<String> keys) async {
    final added = keys.where(_hidden.add).length;
    if (added == 0) return;
    notifyListeners();
    await _persist();
  }

  /// Puts them back, for an undo.
  Future<void> show(Iterable<String> keys) async {
    final removed = keys.where(_hidden.remove).length;
    if (removed == 0) return;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final account = _account;
    if (account == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('$_prefix$account', _hidden.toList());
  }

  @visibleForTesting
  void resetForTest() {
    _hidden.clear();
    _loadedFor = null;
  }
}
