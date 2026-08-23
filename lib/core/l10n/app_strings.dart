import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The languages the storefront speaks.
///
/// Nepali as well as English because this shop sells in Nepal, and the
/// endonym is used in the picker -- someone looking for their own language
/// scans for "नेपाली", not for the English word "Nepali".
enum AppLanguage {
  english('en', 'English', 'English'),
  nepali('ne', 'Nepali', 'नेपाली');

  const AppLanguage(this.code, this.englishName, this.nativeName);

  final String code;
  final String englishName;
  final String nativeName;

  static AppLanguage fromCode(String? code) {
    for (final language in values) {
      if (language.code == code) return language;
    }
    return english;
  }
}

/// Every string the browse experience shows.
///
/// Named fields rather than a map keyed by string: a missing translation
/// should be a compile error, not a blank label discovered by a shopper.
/// Adding a language means adding one const below and the compiler lists what
/// is missing.
@immutable
class AppStrings {
  const AppStrings({
    required this.categories,
    required this.home,
    required this.saved,
    required this.signIn,
    required this.account,
    required this.search,
    required this.cart,
    required this.popularNow,
    required this.categoryCount,
    required this.endOfList,
    required this.language,
    required this.languageDetail,
    required this.jumpTo,
    required this.departmentNames,
    required this.groupNames,
  });

  final String categories;
  final String home;
  final String saved;
  final String signIn;
  final String account;
  final String search;
  final String cart;
  final String popularNow;

  /// Takes the count, because word order around a number is not the same in
  /// every language and gluing "12" to a translated noun would only work in
  /// the one it was written for.
  final String Function(int count) categoryCount;

  final String Function(String department) endOfList;

  final String language;
  final String languageDetail;
  final String jumpTo;

  /// Department and group names, keyed by their English name -- which is the
  /// identifier in [CatalogContent]. A name with no translation falls back to
  /// that key, so a new department shows up in English rather than blank.
  final Map<String, String> departmentNames;
  final Map<String, String> groupNames;

  String department(String key) => departmentNames[key] ?? key;
  String group(String key) => groupNames[key] ?? key;

  static AppStrings of(AppLanguage language) =>
      switch (language) { AppLanguage.english => en, AppLanguage.nepali => ne };

  static final en = AppStrings(
    categories: 'Categories',
    home: 'Home',
    saved: 'Saved',
    signIn: 'Sign in',
    account: 'Account',
    search: 'Search',
    cart: 'Cart',
    popularNow: 'Popular right now',
    categoryCount: (count) => '$count categories',
    endOfList: (department) => 'That is everything in $department.',
    language: 'Language',
    languageDetail: 'Choose the language this app speaks',
    jumpTo: 'Jump to a category',
    departmentNames: const {},
    groupNames: const {},
  );

  /// A first pass, and worth a native speaker's eye before it ships. Where a
  /// borrowed English term is what Nepali shoppers actually use -- कार्ट,
  /// इलेक्ट्रोनिक्स -- the loanword is kept rather than a literal translation
  /// nobody would search for.
  static final ne = AppStrings(
    categories: 'श्रेणीहरू',
    home: 'गृहपृष्ठ',
    saved: 'सुरक्षित',
    signIn: 'साइन इन',
    account: 'खाता',
    search: 'खोज्नुहोस्',
    cart: 'कार्ट',
    popularNow: 'अहिले लोकप्रिय',
    categoryCount: (count) => '$count श्रेणीहरू',
    endOfList: (department) => '$department मा यति नै हो।',
    language: 'भाषा',
    languageDetail: 'यो एपले बोल्ने भाषा छान्नुहोस्',
    jumpTo: 'श्रेणीमा जानुहोस्',
    departmentNames: const {
      'Electronics': 'इलेक्ट्रोनिक्स',
      'Home and kitchen': 'घर र भान्सा',
      'Fashion': 'फेसन',
      'Beauty': 'सौन्दर्य',
      'Sports and outdoors': 'खेलकुद',
      'Family and toys': 'परिवार र खेलौना',
      'Pet supplies': 'पाल्तु सामान',
    },
    groupNames: const {
      'Audio and devices': 'अडियो र उपकरण',
      'Computing': 'कम्प्युटिङ',
      'Gaming gear': 'गेमिङ सामान',
      'Living and dining': 'बैठक र भोजन',
      'Kitchen': 'भान्सा',
      'Storage': 'भण्डारण',
      'Footwear': 'जुत्ता',
      'Clothing': 'लुगा',
      'Skin and hair': 'छाला र कपाल',
      'Training and outdoors': 'व्यायाम र बाहिरी',
      'Toys and family': 'खेलौना र परिवार',
      'For your pets': 'तपाईंको पाल्तुका लागि',
    },
  );
}

/// The chosen language, shared across the app.
class LanguageStore extends ChangeNotifier {
  LanguageStore._();

  static final instance = LanguageStore._();

  static const _key = 'gtradea_language';

  AppLanguage _language = AppLanguage.english;
  bool _loaded = false;

  AppLanguage get language => _language;
  AppStrings get strings => AppStrings.of(_language);
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _language = AppLanguage.fromCode(prefs.getString(_key));
    } catch (_) {
      // Unreadable: English, which is the default anyway.
    }
    _loaded = true;
    notifyListeners();
  }

  void setLanguage(AppLanguage language) {
    if (language == _language) return;
    _language = language;
    _loaded = true;
    notifyListeners();
    unawaited(_persist());
  }

  @visibleForTesting
  void resetForTest() {
    _language = AppLanguage.english;
    _loaded = false;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _language.code);
    } catch (_) {
      // Best effort, like the other stores.
    }
  }
}
