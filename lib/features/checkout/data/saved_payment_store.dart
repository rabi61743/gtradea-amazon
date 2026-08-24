import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_store.dart';
import 'card_details.dart';

/// A card the shopper asked us to remember.
///
/// What is kept here is the whole of what may be kept: the brand, the last four
/// digits, the expiry and the name. That is enough to recognise a card in a
/// list and nothing like enough to use one.
///
/// What is deliberately absent, and must stay absent:
///
///   * the card number. Storing a full PAN puts this app inside the payment
///     card industry's scope, and there is no reason to -- the gateway holds
///     the card and hands back a token.
///   * the security code. Keeping a CVV after a transaction is forbidden by
///     every card scheme, without exception, even encrypted.
///
/// [gatewayToken] is what actually lets a saved card be charged again, and it
/// comes from the gateway. Null until a gateway that issues one is wired up,
/// which is why a saved card here is a convenience for re-entering details
/// rather than a way to charge without them.
@immutable
class SavedPaymentMethod {
  const SavedPaymentMethod({
    required this.id,
    required this.brand,
    required this.last4,
    required this.holder,
    required this.expiryMonth,
    required this.expiryYear,
    this.gatewayToken,
  });

  final String id;
  final CardBrand brand;

  /// Four digits. The most of a card number anyone may store or display.
  final String last4;

  final String holder;
  final int expiryMonth;
  final int expiryYear;

  /// The gateway's handle for this card, when there is one.
  final String? gatewayToken;

  String get maskedNumber => '•••• •••• •••• $last4';

  String get expiryLabel =>
      '${expiryMonth.toString().padLeft(2, '0')}/${expiryYear % 100}';

  /// True once the card can no longer be used. Shown rather than hidden: a
  /// shopper looking for a card they saved should find it, marked expired.
  bool isExpired([DateTime? now]) {
    final today = now ?? DateTime.now();
    return !DateTime(expiryYear, expiryMonth + 1)
        .isAfter(DateTime(today.year, today.month, today.day));
  }

  /// Built from details that have just been used.
  ///
  /// Takes a [CardDetails] and keeps almost none of it, which is the point.
  factory SavedPaymentMethod.fromCard(CardDetails card, {String? token}) =>
      SavedPaymentMethod(
        // Derived from what is stored anyway, so no new identifier has to be
        // invented and the same card saved twice does not appear twice.
        id: '${card.brand.name}:${card.last4}:${card.expiryMonth}'
            '${card.expiryYear}',
        brand: card.brand,
        last4: card.last4,
        holder: card.holder.trim(),
        expiryMonth: card.expiryMonth,
        expiryYear: card.expiryYear,
        gatewayToken: token,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'brand': brand.name,
        'last4': last4,
        'holder': holder,
        'expiryMonth': expiryMonth,
        'expiryYear': expiryYear,
        'gatewayToken': gatewayToken,
      };

  static SavedPaymentMethod? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final last4 = json['last4'];
    final month = json['expiryMonth'];
    final year = json['expiryYear'];
    if (id is! String || id.isEmpty) return null;
    if (last4 is! String || last4.length != 4) return null;
    if (month is! int || year is! int) return null;

    return SavedPaymentMethod(
      id: id,
      brand: CardBrand.values.firstWhere(
        (b) => b.name == json['brand'],
        orElse: () => CardBrand.unknown,
      ),
      last4: last4,
      holder: json['holder'] is String ? json['holder'] as String : '',
      expiryMonth: month,
      expiryYear: year,
      gatewayToken: json['gatewayToken'] is String
          ? json['gatewayToken'] as String
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedPaymentMethod && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// The cards this shopper has asked us to remember.
///
/// Scoped to the signed-in account like the cart and the address book, so one
/// person's saved cards never appear under another's on a shared phone.
///
/// SharedPreferences rather than the keystore, and that is a deliberate
/// judgement rather than an oversight: what is stored is a brand, four digits
/// and an expiry -- the same information printed on a receipt. Putting it
/// behind the keystore would suggest it were a credential, which it is not,
/// and the things that would be credentials are never stored at all.
class SavedPaymentStore extends ChangeNotifier {
  SavedPaymentStore._();

  static final instance = SavedPaymentStore._();

  static const _guestKey = 'gtradea_saved_cards';

  final List<SavedPaymentMethod> _cards = [];
  String? _scope;
  bool _loaded = false;
  bool _bound = false;
  Future<void> _writes = Future.value();

  List<SavedPaymentMethod> get cards => List.unmodifiable(_cards);
  bool get isEmpty => _cards.isEmpty;
  int get count => _cards.length;

  static String storageKeyFor(String? email) =>
      (email == null || email.isEmpty) ? _guestKey : '${_guestKey}_$email';

  /// Follows the signed-in account for the rest of the app's life.
  void bindToAuth([AuthStore? auth]) {
    if (_bound) return;
    _bound = true;
    (auth ?? AuthStore.instance).addListener(_onIdentityChanged);
  }

  Future<void> load() async {
    if (_loaded) return;
    _scope = AuthStore.instance.account?.email;
    await _readInto(_cards, storageKeyFor(_scope));
    _loaded = true;
    notifyListeners();
  }

  void _onIdentityChanged() {
    unawaited(_switchTo(AuthStore.instance.account?.email));
  }

  /// Swaps to another account's cards.
  ///
  /// Nothing is carried across. A card is tied to a person, not a device, and
  /// merging a guest's saved card into an account would attach it to the wrong
  /// one -- which for payment details is the worst kind of wrong.
  Future<void> _switchTo(String? email) async {
    if (email == _scope) return;
    _scope = email;
    _cards.clear();
    await _readInto(_cards, storageKeyFor(email));
    _loaded = true;
    notifyListeners();
  }

  @visibleForTesting
  Future<void> switchIdentity(String? email) => _switchTo(email);

  /// Remembers a card. Returns false when it was already saved.
  bool save(SavedPaymentMethod card) {
    if (_cards.any((existing) => existing.id == card.id)) return false;
    // Newest first: the card just used is the one most likely to be used again.
    _cards.insert(0, card);
    _loaded = true;
    notifyListeners();
    unawaited(_persist());
    return true;
  }

  void remove(String id) {
    final before = _cards.length;
    _cards.removeWhere((card) => card.id == id);
    if (_cards.length == before) return;
    notifyListeners();
    unawaited(_persist());
  }

  void clear() {
    if (_cards.isEmpty) return;
    _cards.clear();
    notifyListeners();
    unawaited(_persist());
  }

  @visibleForTesting
  void resetForTest() {
    _cards.clear();
    _scope = null;
    _loaded = false;
    _bound = false;
  }

  Future<void> _readInto(
    List<SavedPaymentMethod> target,
    String key,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      target.addAll(
        decoded
            .whereType<Map>()
            .map((e) => SavedPaymentMethod.fromJson(e.cast<String, dynamic>()))
            .whereType<SavedPaymentMethod>(),
      );
    } catch (_) {
      // Unreadable: start with none rather than blocking checkout.
    }
  }

  /// Writes under the current shopper's key.
  ///
  /// Key and payload captured before the first await, and the writes chained,
  /// for the same reason as the cart: a write scheduled for one account must
  /// not land under another's after a fast sign-in.
  Future<void> _persist() {
    final key = storageKeyFor(_scope);
    final payload =
        jsonEncode(_cards.map((card) => card.toJson()).toList(growable: false));

    return _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, payload);
      } catch (_) {
        // Best effort. A failed write costs persistence, never the action.
      }
    });
  }
}
