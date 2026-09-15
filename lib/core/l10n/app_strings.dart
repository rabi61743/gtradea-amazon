import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'payment_strings.dart';

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
    required this.newForYou,
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
    required this.browseIn,
    required this.payment,
  });

  final String categories;
  final String home;

  /// The personalised feed's tab and heading.
  final String newForYou;
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

  /// Department names, keyed by the exact name the server sends.
  ///
  /// The catalogue is the server's, and it sends English and Chinese but no
  /// Nepali -- so most of the forty-eight departments have nothing to
  /// translate them from and render in English. This map is the override for
  /// the ones worth hand-translating; anything missing falls back to the
  /// server's own name rather than to blank.
  ///
  /// It used to be keyed by the names of a hardcoded department list that no
  /// longer exists, so none of its keys matched anything and every department
  /// rendered untranslated while looking as though it should not.
  final Map<String, String> departmentNames;

  /// The heading over a department's subcategory tiles.
  ///
  /// Takes the already-translated department name. This replaced a lookup
  /// table of group names that had been dead since group titles started being
  /// derived from server data -- none of its twelve keys could ever match, so
  /// the heading stayed English in Nepali while appearing to be translated.
  final String Function(String department) browseIn;

  /// Everything the payment flow says.
  final PaymentStrings payment;

  String department(String key) => departmentNames[key] ?? key;

  static AppStrings of(AppLanguage language) => switch (language) {
    AppLanguage.english => en,
    AppLanguage.nepali => ne,
  };

  static final en = AppStrings(
    categories: 'Categories',
    home: 'Home',
    newForYou: 'New for You',
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
    browseIn: (department) => 'Browse $department',
    payment: PaymentStrings.en,
  );

  /// A first pass, and worth a native speaker's eye before it ships. Where a
  /// borrowed English term is what Nepali shoppers actually use -- कार्ट,
  /// इलेक्ट्रोनिक्स -- the loanword is kept rather than a literal translation
  /// nobody would search for.
  static final ne = AppStrings(
    categories: 'श्रेणीहरू',
    home: 'गृहपृष्ठ',
    newForYou: 'तपाईंका लागि नयाँ',
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
    // Keyed by the exact strings `/alibaba-categories` returns for the
    // top-level departments -- "Sports Outdoors", not "Sports and outdoors".
    // The busiest departments are covered; the long tail of industrial ones
    // falls back to the server's English, which is what a shopper looking for
    // them would search for anyway.
    departmentNames: const {
      'Women': 'महिला',
      'Men': 'पुरुष',
      'Kidswear': 'बालबालिकाको लुगा',
      'Toys': 'खेलौना',
      'Beauty Skincare/Makeup': 'सौन्दर्य र मेकअप',
      'Footwear': 'जुत्ता',
      'Sports Outdoors': 'खेलकुद र बाहिरी',
      'Home Textile Furniture': 'घरायसी कपडा र फर्निचर',
      'Food & Beverage': 'खाद्य र पेय',
      'Home appliance': 'घरायसी उपकरण',
      'Bags & Leather': 'झोला र छाला',
      'Digital, Computer': 'डिजिटल र कम्प्युटर',
      'Pets & Gardening': 'पाल्तु र बगैंचा',
      'Underwear': 'भित्री वस्त्र',
      'Bedding': 'ओछ्यान सामग्री',
      'Sportswear': 'खेल पोशाक',
      'Lighting': 'बत्ती',
      'Household essentials': 'घरायसी आवश्यक सामान',
    },
    browseIn: (department) => '$department हेर्नुहोस्',
    payment: PaymentStrings.ne,
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
