import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_store.dart';

/// What kind of place this is.
///
/// A label rather than free text, because the whole point is telling two
/// addresses apart at a glance in a list -- and "Home" recognised as an icon
/// beats reading two similar streets.
enum AddressLabel {
  home('Home', Icons.home_outlined),
  work('Work', Icons.business_center_outlined),
  other('Other', Icons.place_outlined);

  const AddressLabel(this.title, this.icon);
  final String title;
  final IconData icon;

  static AddressLabel fromName(String? name) {
    for (final label in values) {
      if (label.name == name) return label;
    }
    return other;
  }
}

/// Nepal's provinces, for the one field a shopper should not be typing.
const kProvinces = <String>[
  'Koshi',
  'Madhesh',
  'Bagmati',
  'Gandaki',
  'Lumbini',
  'Karnali',
  'Sudurpashchim',
];

@immutable
class Address {
  const Address({
    required this.id,
    required this.label,
    required this.fullName,
    required this.phone,
    required this.province,
    required this.city,
    required this.area,
    this.landmark,
    this.postalCode,
  });

  final String id;
  final AddressLabel label;
  final String fullName;
  final String phone;
  final String province;

  /// District or municipality -- what a courier would call the town.
  final String city;

  /// Tole, street and house number: the part that actually finds the door.
  final String area;

  /// Optional, and genuinely useful here: plenty of addresses in Nepal are
  /// found by landmark rather than by street number.
  final String? landmark;

  /// Filled by the geocoder when it knows one. Optional because plenty of
  /// Nepali addresses do not carry one, and demanding it would block the form
  /// for the shoppers who have none.
  final String? postalCode;

  /// One line, for a list row or an order record.
  String get oneLine =>
      [area, city, province].where((p) => p.isNotEmpty).join(', ');

  /// The whole thing, for a confirmation screen where being sure matters more
  /// than being brief.
  String get full {
    final tail = [
      province,
      if (postalCode != null && postalCode!.trim().isNotEmpty)
        postalCode!.trim(),
    ].where((part) => part.isNotEmpty).join(' ');

    return [
      area,
      if (landmark != null && landmark!.trim().isNotEmpty)
        'Near ${landmark!.trim()}',
      city,
      tail,
    ].where((part) => part.isNotEmpty).join(', ');
  }

  Address copyWith({
    AddressLabel? label,
    String? fullName,
    String? phone,
    String? province,
    String? city,
    String? area,
    String? landmark,
    String? postalCode,
  }) => Address(
    id: id,
    label: label ?? this.label,
    fullName: fullName ?? this.fullName,
    phone: phone ?? this.phone,
    province: province ?? this.province,
    city: city ?? this.city,
    area: area ?? this.area,
    landmark: landmark ?? this.landmark,
    postalCode: postalCode ?? this.postalCode,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label.name,
    'fullName': fullName,
    'phone': phone,
    'province': province,
    'city': city,
    'area': area,
    'landmark': landmark,
    'postalCode': postalCode,
  };

  /// An address missing the parts a courier needs is not an address. Dropped
  /// rather than shown as a row with blanks in it, which would look like a bug
  /// and would be undeliverable anyway.
  static Address? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final fullName = json['fullName'];
    final area = json['area'];
    final city = json['city'];
    if (id is! String || id.isEmpty) return null;
    if (fullName is! String || fullName.trim().isEmpty) return null;
    if (area is! String || area.trim().isEmpty) return null;
    if (city is! String || city.trim().isEmpty) return null;

    return Address(
      id: id,
      label: AddressLabel.fromName(json['label'] as String?),
      fullName: fullName,
      phone: json['phone'] is String ? json['phone'] as String : '',
      province: json['province'] is String ? json['province'] as String : '',
      city: city,
      area: area,
      landmark: json['landmark'] is String ? json['landmark'] as String : null,
      postalCode: json['postalCode'] is String
          ? json['postalCode'] as String
          : null,
    );
  }
}

/// The address book.
///
/// Scoped per shopper like the cart and the orders: a guest key and a key per
/// account, with a guest's addresses carried into their account on sign-in.
/// Guests are not blocked from saving one -- they can place an order, so
/// refusing to remember where it goes would be perverse.
class AddressStore extends ChangeNotifier {
  AddressStore._();

  static final instance = AddressStore._();

  static const _guestKey = 'gtradea_addresses';

  final List<Address> _addresses = [];
  String? _defaultId;
  String? _scope;
  bool _loaded = false;
  bool _bound = false;
  Future<void>? _loading;

  List<Address> get addresses => List.unmodifiable(_addresses);
  int get count => _addresses.length;
  bool get isEmpty => _addresses.isEmpty;
  bool get isLoaded => _loaded;

  static String storageKeyFor(String? email) =>
      (email == null || email.isEmpty) ? _guestKey : 'gtradea_addresses_$email';

  /// Where an order goes unless the shopper says otherwise.
  ///
  /// Falls back to the first saved address rather than returning null when the
  /// stored default has been deleted -- a shopper with an address in the book
  /// should never see "no address selected".
  Address? get defaultAddress {
    if (_addresses.isEmpty) return null;
    for (final address in _addresses) {
      if (address.id == _defaultId) return address;
    }
    return _addresses.first;
  }

  bool isDefault(String id) => defaultAddress?.id == id;

  Address? byId(String id) {
    for (final address in _addresses) {
      if (address.id == id) return address;
    }
    return null;
  }

  /// Matches on name, phone, or any part of the address, so a shopper with a
  /// long book can find one by whatever they happen to remember.
  List<Address> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return addresses;
    return _addresses.where((address) {
      final haystack = [
        address.label.title,
        address.fullName,
        address.phone,
        address.area,
        address.city,
        address.province,
        address.landmark ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(needle);
    }).toList();
  }

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
    final hadPending = _addresses.isNotEmpty;
    await _readInto(storageKeyFor(_scope));

    _loaded = true;
    _loading = null;
    notifyListeners();
    if (hadPending) unawaited(_persist());
  }

  void _onIdentityChanged() {
    unawaited(_switchTo(AuthStore.instance.account?.email));
  }

  Future<void> _switchTo(String? email) async {
    if (email == _scope) return;

    final wasGuest = _scope == null || _scope!.isEmpty;
    final carried = wasGuest
        ? List<Address>.from(_addresses)
        : const <Address>[];
    final carriedDefault = wasGuest ? _defaultId : null;

    _scope = email;
    _addresses.clear();
    _defaultId = null;
    await _readInto(storageKeyFor(email));

    if (email != null && carried.isNotEmpty) {
      final hadNone = _addresses.isEmpty;
      for (final address in carried) {
        if (_addresses.any((existing) => existing.id == address.id)) continue;
        _addresses.add(address);
      }
      // The account keeps its own default. A guest's only becomes the default
      // if the account had nothing to begin with.
      if (hadNone && carriedDefault != null) _defaultId = carriedDefault;
      unawaited(_clearStored(_guestKey));
      unawaited(_persist());
    }

    _loaded = true;
    notifyListeners();
  }

  /// Saves a new address and returns it.
  Address add({
    required AddressLabel label,
    required String fullName,
    required String phone,
    required String province,
    required String city,
    required String area,
    String? landmark,
    String? postalCode,
    bool makeDefault = false,
    String? id,
  }) {
    final address = Address(
      id: id ?? _nextId(),
      label: label,
      fullName: fullName.trim(),
      phone: phone.trim(),
      province: province.trim(),
      city: city.trim(),
      area: area.trim(),
      landmark: landmark?.trim().isEmpty ?? true ? null : landmark!.trim(),
      postalCode: postalCode?.trim().isEmpty ?? true
          ? null
          : postalCode!.trim(),
    );

    _addresses.add(address);
    // The first one is the default whether or not anybody asked: a book with
    // one address in it has an obvious answer.
    if (makeDefault || _addresses.length == 1) _defaultId = address.id;

    _loaded = true;
    notifyListeners();
    unawaited(_persist());
    return address;
  }

  void update(Address address) {
    final index = _addresses.indexWhere(
      (existing) => existing.id == address.id,
    );
    if (index == -1) return;
    _addresses[index] = address;
    notifyListeners();
    unawaited(_persist());
  }

  void setDefault(String id) {
    if (_defaultId == id || byId(id) == null) return;
    _defaultId = id;
    notifyListeners();
    unawaited(_persist());
  }

  void remove(String id) {
    final before = _addresses.length;
    _addresses.removeWhere((address) => address.id == id);
    if (_addresses.length == before) return;
    // Leave the dangling default to the getter, which already falls back to
    // the first address. Clearing it here would silently pick a new default
    // without the shopper being told either way.
    if (_defaultId == id) _defaultId = null;
    notifyListeners();
    unawaited(_persist());
  }

  void clear() {
    if (_addresses.isEmpty) return;
    _addresses.clear();
    _defaultId = null;
    notifyListeners();
    unawaited(_persist());
  }

  @visibleForTesting
  void resetForTest() {
    _addresses.clear();
    _defaultId = null;
    _scope = null;
    _loaded = false;
    _bound = false;
    _loading = null;
  }

  String _nextId() {
    var candidate =
        'ADDR${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    var suffix = 1;
    while (_addresses.any((address) => address.id == candidate)) {
      candidate = '$candidate$suffix';
      suffix++;
    }
    return candidate;
  }

  Future<void> _readInto(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final list = decoded['addresses'];
      if (list is List) {
        for (final entry in list.whereType<Map>()) {
          final address = Address.fromJson(entry.cast<String, dynamic>());
          if (address == null) continue;
          if (_addresses.any((existing) => existing.id == address.id)) continue;
          _addresses.add(address);
        }
      }
      final stored = decoded['default'];
      if (stored is String) _defaultId = stored;
    } catch (_) {
      // Unreadable book: start empty rather than blocking checkout behind it.
    }
  }

  /// Key and payload captured before the first await, and writes serialised,
  /// for the same reasons the cart and order stores do it.
  Future<void> _persist() {
    final key = storageKeyFor(_scope);
    final payload = jsonEncode({
      'addresses': _addresses.map((address) => address.toJson()).toList(),
      'default': _defaultId,
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
