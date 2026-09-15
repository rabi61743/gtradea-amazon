import 'package:flutter/foundation.dart';

import '../../../core/network/api_error.dart';
import '../../cart/data/cart_store.dart';
import '../../checkout/data/checkout_repository.dart';
import '../../product/data/storefront_config.dart';

/// What each way of carrying this order would cost, for this shopper.
///
/// One request per mode against `POST /checkout/delivery-charge` -- the same
/// endpoint the cart and the checkout price freight with, so a figure shown on
/// a product page is the figure the order is charged. Nothing is estimated
/// here: the server is given the product, the variant, the quantity and the
/// destination district, and what it answers is what is drawn.
///
/// A quote is worth asking for only when there is a destination. Freight is
/// priced to a district, so with no address saved this holds no figures and
/// says as much, rather than quoting a delivery to nowhere.
class LogisticsQuotes extends ChangeNotifier {
  /// Keyed by mode, for one basket and one district at a time.
  Map<String, DeliveryQuote?> _quotes = const {};

  /// What the answers above were for. A change of quantity, variant, product
  /// or address makes them stale, and stale freight is worse than none.
  String? _quotedFor;

  bool _loading = false;
  ApiError? _error;

  bool get isLoading => _loading;
  ApiError? get error => _error;

  /// True once an answer -- figures, or a considered absence of them -- is in.
  bool get hasQuotes => _quotedFor != null;

  /// What the server charges for this mode, or null where it published no
  /// figure. Null is not zero: the cart says freight is worked out at
  /// checkout, and so does the card.
  DeliveryQuote? forMode(String key) => _quotes[key];

  String _keyFor(List<CartLine> lines, String district, List<String> modes) => [
    district.trim().toLowerCase(),
    modes.join('|'),
    for (final line in lines)
      '${line.productId}:${line.variantLabel ?? ''}:${line.quantity}',
  ].join('/');

  /// Prices every mode for this basket and destination.
  ///
  /// Cheap to call repeatedly: an unchanged basket, district and mode list is
  /// answered from what is already held.
  Future<void> load({
    required List<CartLine> lines,
    required String? district,
    required List<LogisticsMode> modes,
    bool force = false,
  }) async {
    // Two ways there is no honest figure to fetch:
    //
    //  * No lines. The endpoint falls back to the shopper's saved cart when it
    //    is sent none, so a page with nothing chosen would show the freight
    //    for whatever is already in their basket.
    //
    //  * No district. Freight is priced to a destination.
    //
    // Being signed in used to be a third. `guestCartItems` is honoured **only
    // for an anonymous request** -- measured against the live endpoint, and
    // then against the app: a product page quoted Rs. 5,237 for two pieces and
    // the cart's own delivery fee for that account was Rs. 5,237 to the rupee.
    // The server was pricing the account's basket and ignoring what it was
    // handed, so a signed-in shopper was shown nothing at all here.
    //
    // The ask is made anonymously instead -- see [CheckoutRepository
    // .deliveryCharge]'s `asGuest` -- which is the same public quote, for the
    // lines actually in front of the shopper. The cart and the checkout still
    // ask as the account, because the account's basket is what they are about.
    if (lines.isEmpty ||
        district == null ||
        district.trim().isEmpty ||
        modes.isEmpty) {
      if (_quotes.isNotEmpty || _quotedFor != null || _error != null) {
        _quotes = const {};
        _quotedFor = null;
        _error = null;
        notifyListeners();
      }
      return;
    }

    final key = _keyFor(lines, district, [for (final m in modes) m.key]);
    if (_loading) return;
    if (key == _quotedFor && !force && _error == null) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // In parallel: three modes asked one after another is three round trips
      // a shopper watches, and they do not depend on each other.
      final answers = await Future.wait([
        for (final mode in modes)
          CheckoutRepository.instance.deliveryCharge(
            district: district,
            shippingMode: mode.key,
            guestLines: lines,
            rethrowFailures: true,
            asGuest: true,
          ),
      ]);

      _quotes = {
        for (var i = 0; i < modes.length; i++) modes[i].key: answers[i],
      };
      _quotedFor = key;
    } on ApiError catch (error) {
      // Held rather than swallowed: this is the one place with somewhere to
      // say so, and a retry beside it.
      _error = error;
      _quotes = const {};
      _quotedFor = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
