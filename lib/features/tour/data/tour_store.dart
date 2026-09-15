import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_store.dart';

/// How a tour ended, as the shopper left it.
enum TourOutcome {
  /// Walked to the last step and pressed Get Started.
  completed,

  /// Dismissed part-way. Deliberately distinct from [completed]: the two mean
  /// different things when deciding what a later version should replay.
  skipped,
}

/// What this device knows about one account's onboarding.
///
/// A record rather than a bare bool: the spec asks for the version, the
/// outcome and when it happened, and a flag cannot carry any of that.
@immutable
class TourProgress {
  const TourProgress({required this.version, required this.outcome, this.at});

  /// The highest tour version this shopper has been shown.
  ///
  /// What makes a later release show only its new steps: the tour asks for the
  /// steps above this number rather than replaying from the beginning.
  final int version;

  final TourOutcome outcome;
  final DateTime? at;

  bool get isCompleted => outcome == TourOutcome.completed;

  Map<String, dynamic> toJson() => {
    'version': version,
    'outcome': outcome.name,
    'at': at?.millisecondsSinceEpoch,
  };

  static TourProgress? fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int) return null;
    final raw = json['outcome'];
    final outcome = TourOutcome.values.where((o) => o.name == raw).firstOrNull;
    if (outcome == null) return null;
    final at = json['at'];
    return TourProgress(
      version: version,
      outcome: outcome,
      at: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
    );
  }
}

/// Whether the guided tour has been seen, and up to which version.
///
/// Scoped per shopper exactly like [NotificationSettings] and the cart: a guest
/// key, a key per account, and what a guest saw carried into the account they
/// sign into. Two people sharing a device each get their own first run, and
/// signing in must not replay a tour the guest already finished on that phone.
///
/// **Nothing here decides to show anything until it has read the disk.** The
/// first frame of a cold start has no answer yet, and guessing "show" for that
/// moment would flash an overlay over the storefront on every launch. See
/// [shouldStart], which is false until [load] has resolved.
class TourStore extends ChangeNotifier {
  TourStore._();

  static final TourStore instance = TourStore._();

  static const _key = 'gtradea_tour';

  /// The tour as it currently stands.
  ///
  /// Raised only when steps are **added**. A shopper who finished version 1
  /// is then offered the steps above 1 rather than the whole thing again --
  /// see [unseenFrom].
  ///
  /// 2 since the coins step joined it. Anybody who has already walked the
  /// original five gets that one step on their next launch; a first install
  /// still gets all six.
  static const currentVersion = 2;

  /// Where [accountId]'s progress lives. A guest's is the bare key.
  static String storageKeyFor(String? accountId) =>
      (accountId == null || accountId.isEmpty) ? _key : '${_key}_$accountId';

  TourProgress? _progress;
  bool _loaded = false;
  bool _bound = false;

  /// The account whose progress is held; null for a guest.
  String? _scope;

  /// Bumped on every change of account, so a disk read begun for the last
  /// account cannot land under this one.
  int _epoch = 0;

  /// Off in tests by default.
  ///
  /// Every widget test seeds an empty [SharedPreferences], which *is* a first
  /// install -- so without this the tour would open over eight existing home
  /// screen suites that measure the widgets it covers. The same seam
  /// `AppSound.enabled` uses, and for the same reason.
  @visibleForTesting
  static bool enabled = true;

  TourProgress? get progress => _progress;
  bool get isLoaded => _loaded;

  /// True when the tour should open on its own.
  ///
  /// False until the disk has answered, false once this account has seen the
  /// current version, and false when switched off for a test. Never a guess.
  bool get shouldStart => enabled && _loaded && hasUnseen;

  /// Whether any step of the current tour is still unshown.
  ///
  /// Somebody who has seen nothing is at 1, which is at or below the current
  /// version, so there is something to show. Somebody who finished the current
  /// version is at `currentVersion + 1`, which is past it, so there is not.
  bool get hasUnseen => unseenFrom <= currentVersion;

  /// The first version this shopper has not been shown.
  ///
  /// 1 for somebody who has never seen it, which is the whole tour. For
  /// somebody who finished version 1 of a two-version tour it is 2, and only
  /// the steps introduced in 2 are shown.
  int get unseenFrom {
    final seen = _progress;
    if (seen == null) return 1;
    return seen.version + 1;
  }

  /// Follows the active account for the rest of the app's life.
  void bindToAuth([AuthStore? auth]) {
    if (_bound) return;
    _bound = true;
    (auth ?? AuthStore.instance).addListener(_onIdentityChanged);
  }

  void _onIdentityChanged() {
    final id = AuthStore.instance.account?.id;
    if (id == _scope && _loaded) return;
    _scope = id;
    _epoch++;
    // Nothing shown, and nothing claimed, until this account's own record is
    // read. Keeping the last account's progress for the length of a disk read
    // is how one shopper's finished tour silences another's first run.
    _progress = null;
    _loaded = false;
    notifyListeners();
    unawaited(_readInto(storageKeyFor(id), _epoch, migrateLegacy: true));
  }

  Future<void> load() async {
    if (_loaded) return;
    _scope = AuthStore.instance.account?.id;
    await _readInto(storageKeyFor(_scope), _epoch, migrateLegacy: true);
  }

  Future<void> _readInto(
    String key,
    int epoch, {
    bool migrateLegacy = false,
  }) async {
    TourProgress? found;
    try {
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString(key);
      // What a guest saw on this device becomes the account's, once, and only
      // if that account has no record of its own. Signing up after finishing
      // the tour must not replay it.
      if (migrateLegacy && raw == null && key != _key) {
        raw = prefs.getString(_key);
        if (raw != null) await prefs.setString(key, raw);
      }
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          found = TourProgress.fromJson(decoded.cast<String, dynamic>());
        }
      }
    } catch (_) {
      // Unreadable: treated as never seen. Showing the tour twice is a small
      // annoyance; never showing it is the feature not existing.
    }
    if (epoch != _epoch) return;
    _progress = found;
    _loaded = true;
    notifyListeners();
  }

  /// Records that the shopper finished or dismissed the tour.
  ///
  /// Written for the version they were actually shown, which is [currentVersion]
  /// -- not for the version they started at. Somebody who joins at step 4 of a
  /// version 2 tour has now seen version 2.
  Future<void> finish(TourOutcome outcome, {DateTime? at}) async {
    final progress = TourProgress(
      version: currentVersion,
      outcome: outcome,
      at: at ?? DateTime.now(),
    );
    _progress = progress;
    _loaded = true;
    notifyListeners();

    final key = storageKeyFor(_scope);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(progress.toJson()));
    } catch (_) {
      // Best effort, as everywhere else this app persists a preference. The
      // cost of a failed write is the tour opening once more, not a wrong
      // claim about what the shopper has seen.
    }
  }

  @visibleForTesting
  void resetForTest() {
    _progress = null;
    _loaded = false;
    _bound = false;
    _scope = null;
    _epoch++;
  }
}
