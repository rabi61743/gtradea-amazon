import 'package:shared_preferences/shared_preferences.dart';

import '../../address/data/address_store.dart';
import '../../cart/data/cart_store.dart';
import '../../checkout/data/saved_payment_store.dart';
import '../../notifications/data/notification_store.dart';
import '../../orders/data/order_store.dart';
import '../../promo/data/coupon_store.dart';
import '../../wishlist/data/wishlist_store.dart';
import 'recently_viewed_store.dart';

/// Deletes what this device kept for an account that has been removed from
/// it: its cached cart, orders, saved list, notifications, addresses,
/// coupons, cards, history and alert choices.
///
/// Every key comes from the store that writes it, so this cannot drift from
/// where the data actually lives. Nothing on the server is touched -- the
/// account and everything in it are still there to sign back in to.
Future<void> purgeAccountData({
  required String email,
  required String accountId,
}) async {
  if (email.isEmpty && accountId.isEmpty) return;
  final keys = <String>{
    if (email.isNotEmpty) ...[
      CartStore.storageKeyFor(email),
      OrderStore.storageKeyFor(email),
      NotificationStore.storageKeyFor(email),
      AddressStore.storageKeyFor(email),
      CouponStore.storageKeyFor(email),
      SavedPaymentStore.storageKeyFor(email),
      WishlistStore.storageKeyFor(email),
    ],
    if (accountId.isNotEmpty) ...[
      RecentlyViewedStore.storageKeyFor(accountId),
      NotificationSettings.storageKeyFor(accountId),
    ],
  };
  try {
    final prefs = await SharedPreferences.getInstance();
    for (final key in keys) {
      await prefs.remove(key);
    }
  } catch (_) {
    // Best effort: an unreadable store has nothing to remove.
  }
}
