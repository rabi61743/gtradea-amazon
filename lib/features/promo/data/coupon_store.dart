import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_store.dart';
import '../../cart/data/cart_store.dart';
import 'coupon.dart';

/// Which coupon is on the basket, and which ones this shopper has spent.
///
/// Scoped per shopper like the cart and the orders. A one-per-shopper offer is
/// meaningless if signing out resets it, and a guest's spent codes follow them
/// into their account so signing up is not a way to claim it twice.
class CouponStore extends ChangeNotifier {
  CouponStore._();

  static final instance = CouponStore._();

  static const _guestKey = 'gtradea_coupons';

  String? _appliedCode;
  final Set<String> _used = {};

  String? _scope;
  bool _loaded = false;
  bool _bound = false;
  Future<void>? _loading;

  Coupon? get applied =>
      _appliedCode == null ? null : CouponContent.byCode(_appliedCode!);

  bool get hasApplied => applied != null;
  bool get isLoaded => _loaded;
  Set<String> get used => Set.unmodifiable(_used);

  bool hasUsed(String code) => _used.contains(code.trim().toUpperCase());

  static String storageKeyFor(String? email) =>
      (email == null || email.isEmpty) ? _guestKey : 'gtradea_coupons_$email';

  void bindToAuth([AuthStore? auth]) {
    if (_bound) return;
    _bound = true;
    (auth ?? AuthStore.instance).addListener(_onIdentityChanged);
  }

  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    _scope = AuthStore.instance.account?.email;
    await _readInto(storageKeyFor(_scope));
    _loaded = true;
    _loading = null;
    notifyListeners();
  }

  void _onIdentityChanged() {
    unawaited(_switchTo(AuthStore.instance.account?.email));
  }

  Future<void> _switchTo(String? email) async {
    if (email == _scope) return;

    final wasGuest = _scope == null || _scope!.isEmpty;
    final carried = wasGuest ? Set<String>.from(_used) : const <String>{};
    final carriedApplied = wasGuest ? _appliedCode : null;

    _scope = email;
    _used.clear();
    _appliedCode = null;
    await _readInto(storageKeyFor(email));

    if (email != null) {
      // Spent codes follow the shopper in. Signing up must not be a way to
      // claim a one-per-shopper offer a second time.
      if (carried.isNotEmpty) {
        _used.addAll(carried);
        unawaited(_clearStored(_guestKey));
      }
      // The basket comes with them, so what is on it should too -- unless the
      // account has already spent that code.
      if (carriedApplied != null && !_used.contains(carriedApplied)) {
        _appliedCode = carriedApplied;
      }
      unawaited(_persist());
    }

    _loaded = true;
    notifyListeners();
  }

  /// Tries a code against the basket and says what happened.
  ///
  /// Every refusal names its own reason. "Invalid code" for a basket that is
  /// Rs. 40 short is the message that makes people stop trying.
  CouponOutcome apply(String rawCode, List<CartLine> lines, {DateTime? now}) {
    final code = rawCode.trim().toUpperCase();
    final coupon = CouponContent.byCode(code);
    if (coupon == null) return CouponUnknown(rawCode.trim());

    final existing = applied;
    if (existing != null && existing.code != coupon.code) {
      // Checked before anything else about the new code: telling someone their
      // second coupon is expired, when it would have been refused anyway, sends
      // them hunting for a third.
      if (!existing.stackable || !coupon.stackable) {
        return CouponConflict(existing);
      }
    }

    if (coupon.hasExpired(now)) return CouponExpired(coupon);
    if (coupon.oncePerShopper && hasUsed(coupon.code)) {
      return CouponAlreadyUsed(coupon);
    }

    final eligible = coupon.eligibleLines(lines);
    if (eligible.isEmpty) return CouponNotApplicable(coupon);

    // The minimum is judged on the whole basket, which is what "spend Rs. 1,000"
    // means to a shopper, even when the discount itself only touches some of it.
    final subtotal = lines.fold<num>(0, (sum, line) => sum + line.lineTotal);
    if (subtotal < coupon.minOrder) {
      return CouponBelowMinimum(coupon, coupon.minOrder - subtotal);
    }

    final discount = coupon.discountFor(lines);
    if (discount <= 0) return CouponNotApplicable(coupon);

    _appliedCode = coupon.code;
    notifyListeners();
    unawaited(_persist());
    return CouponApplied(coupon, discount);
  }

  /// Re-checks the applied coupon against the basket as it stands now.
  ///
  /// The basket moves after a coupon goes on -- a line removed can drop it
  /// under the minimum. Returns the coupon that was dropped, so the caller can
  /// say why rather than leaving the total to change on its own.
  Coupon? revalidate(List<CartLine> lines, {DateTime? now}) {
    final coupon = applied;
    if (coupon == null) return null;

    final outcome = _check(coupon, lines, now);
    if (outcome) return null;

    _appliedCode = null;
    notifyListeners();
    unawaited(_persist());
    return coupon;
  }

  bool _check(Coupon coupon, List<CartLine> lines, DateTime? now) {
    if (lines.isEmpty) return false;
    if (coupon.hasExpired(now)) return false;
    final subtotal = lines.fold<num>(0, (sum, line) => sum + line.lineTotal);
    if (subtotal < coupon.minOrder) return false;
    return coupon.discountFor(lines) > 0;
  }

  /// What the applied coupon takes off this basket. Zero when none is on.
  num discountFor(List<CartLine> lines) => applied?.discountFor(lines) ?? 0;

  void remove() {
    if (_appliedCode == null) return;
    _appliedCode = null;
    notifyListeners();
    unawaited(_persist());
  }

  /// Called when an order is placed: the code is spent and comes off the
  /// basket, so the next order does not silently reuse it.
  void redeem(String code) {
    final normalised = code.trim().toUpperCase();
    if (normalised.isEmpty) return;
    _used.add(normalised);
    if (_appliedCode == normalised) _appliedCode = null;
    _loaded = true;
    notifyListeners();
    unawaited(_persist());
  }

  @visibleForTesting
  void resetForTest() {
    _appliedCode = null;
    _used.clear();
    _scope = null;
    _loaded = false;
    _bound = false;
    _loading = null;
  }

  Future<void> _readInto(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final applied = decoded['applied'];
      if (applied is String && CouponContent.byCode(applied) != null) {
        _appliedCode = applied.toUpperCase();
      }
      final used = decoded['used'];
      if (used is List) {
        _used.addAll(used.whereType<String>().map((c) => c.toUpperCase()));
      }
    } catch (_) {
      // Unreadable: no coupon on the basket, nothing spent. The shopper can
      // reapply, which is a better failure than a total nobody can explain.
    }
  }

  Future<void> _persist() {
    final key = storageKeyFor(_scope);
    final payload = jsonEncode({
      'applied': _appliedCode,
      'used': _used.toList(),
    });
    return _write(key, payload);
  }

  Future<void> _writes = Future<void>.value();

  Future<void> _write(String key, String payload) {
    return _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, payload);
      } catch (_) {
        // Best effort, like the other stores.
      }
    });
  }

  Future<void> _clearStored(String key) {
    return _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      } catch (_) {
        // See _write.
      }
    });
  }
}
