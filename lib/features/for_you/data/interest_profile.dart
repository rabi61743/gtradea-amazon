import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/network/api_error.dart';
import '../../account/data/product_views_repository.dart';
import '../../account/data/recently_viewed_store.dart';
import '../../auth/data/auth_store.dart';
import '../../cart/data/cart_store.dart';
import '../../orders/data/order_store.dart';
import '../../search/data/recent_search_store.dart';
import '../../wishlist/data/wishlist_store.dart';

/// What this shopper has shown interest in, read from what they actually did.
///
/// Nothing here is guessed or seeded. Every weight comes from a signal the app
/// or the server already holds for this account: what was bought and how
/// many, what is in the cart, what was saved, what was searched for, and what
/// was opened -- on this device and, for a signed-in shopper, on the server's
/// own view history.
@immutable
class InterestProfile {
  const InterestProfile({
    this.departments = const [],
    this.phrases = const [],
    this.known = const {},
  });

  /// Department names, strongest interest first.
  final List<String> departments;

  /// What to search for on the shopper's behalf, strongest first: their own
  /// searches, and short names of what they bought, carried and opened.
  final List<String> phrases;

  /// Products this shopper has already met -- in the cart, saved, bought or
  /// opened. The feed does not offer them again as something new.
  final Set<String> known;

  bool get isEmpty => departments.isEmpty && phrases.isEmpty;

  /// A fingerprint of the interests. A feed built for one set is reused while
  /// it holds and rebuilt the moment it changes.
  String get signature =>
      '${departments.take(6).join('|')}#${phrases.take(6).join('|')}';
}

/// Reads the signals and weighs them.
class InterestSignals {
  InterestSignals._();

  /// How much each kind of signal says about what someone wants. A purchase
  /// is the strongest statement there is; a product merely opened, the
  /// weakest.
  static const _bought = 4.0;
  static const _inCart = 3.0;
  static const _searched = 3.0;
  static const _saved = 2.5;
  static const _viewed = 1.5;

  static Future<InterestProfile> read({
    ProductViewsRepository? views,
  }) async {
    await Future.wait([
      RecentSearchStore.instance.load(),
      RecentlyViewedStore.instance.load(),
      WishlistStore.instance.load(),
      CartStore.instance.load(),
      OrderStore.instance.load(),
    ]);

    // The server's own view history, for a signed-in shopper. A failure costs
    // this one signal, never the feed.
    var serverViews = const <ProductView>[];
    if (AuthStore.instance.isSignedIn) {
      try {
        serverViews = await (views ?? ProductViewsRepository.instance).list(
          limit: 50,
        );
      } on ApiError {
        // See above.
      }
    }

    final departments = <String, double>{};
    final phrases = <String, double>{};
    final known = <String>{};

    void department(String? name, double weight) {
      final value = name?.trim();
      if (value == null || value.isEmpty) return;
      departments[value] = (departments[value] ?? 0) + weight;
    }

    void phrase(String text, double weight) {
      final value = phraseOf(text);
      if (value.isEmpty) return;
      phrases[value] = (phrases[value] ?? 0) + weight;
    }

    // Quantity says something too -- fifty of a thing is a stronger interest
    // than one -- but with diminishing returns, so one bulk order does not
    // drown everything else out.
    double byQuantity(int quantity) => 1 + math.log(math.max(quantity, 1));

    // Newest first in every list, and older entries count for less.
    double recency(int index) => math.pow(0.85, index).toDouble();

    final searches = RecentSearchStore.instance.queries;
    for (var i = 0; i < searches.length; i++) {
      phrase(searches[i], _searched * recency(i));
    }

    final orders = OrderStore.instance.orders;
    for (var i = 0; i < orders.length && i < 20; i++) {
      for (final line in orders[i].lines) {
        known.add(line.productId);
        phrase(line.title, _bought * byQuantity(line.quantity) * recency(i));
      }
    }

    final cart = CartStore.instance.lines;
    for (var i = 0; i < cart.length; i++) {
      final line = cart[i];
      known.add(line.productId);
      final weight = _inCart * byQuantity(line.quantity) * recency(i);
      department(line.category, weight);
      phrase(line.title, weight * 0.7);
    }

    final saved = WishlistStore.instance.items;
    for (var i = 0; i < saved.length; i++) {
      final item = saved[i];
      known.add(item.id);
      department(item.category, _saved * recency(i));
      phrase(item.title, _saved * 0.6 * recency(i));
    }

    final opened = RecentlyViewedStore.instance.items;
    for (var i = 0; i < opened.length; i++) {
      final item = opened[i];
      known.add(item.id);
      department(item.category, _viewed * recency(i));
      if (i < 4) phrase(item.title, _viewed * 0.5 * recency(i));
    }

    for (var i = 0; i < serverViews.length; i++) {
      final view = serverViews[i];
      known.add(view.productId);
      // The server's history overlaps this device's; it is counted at half
      // weight so the same visit is not weighed twice at full strength.
      department(view.category, _viewed * 0.5 * recency(i));
    }

    List<String> ranked(Map<String, double> weights) {
      final entries = weights.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return [for (final entry in entries) entry.key];
    }

    return InterestProfile(
      departments: ranked(departments),
      phrases: ranked(phrases),
      known: known,
    );
  }

  /// A short, searchable name for [text].
  ///
  /// Catalogue titles run to twenty words of keywords. The first few words
  /// that are words carry the product -- "Summer Men's Polo Shirt" -- and
  /// searching on the whole title finds only the one listing it came from.
  @visibleForTesting
  static String phraseOf(String text) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s'-]"), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2 && !RegExp(r'^\d+$').hasMatch(word))
        .take(4)
        .toList();
    return words.length < 2 ? words.join(' ') : words.join(' ');
  }
}
