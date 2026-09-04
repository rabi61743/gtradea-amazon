import 'app_sound.dart';

/// Every sound this app plays, in one place.
///
/// Declared together rather than as statics scattered over the stores that
/// trigger them, so that what the app can make a noise about is answerable by
/// reading one file -- and so a new sound is added beside the others rather
/// than wherever happened to be convenient.
///
/// All of them go through [AppSound], which means all of them obey the
/// shopper's Sound setting without each one having to remember to check.
///
/// Each carries a short gap. It is not there to space sounds out; it is there
/// because a re-render, a retried request or a double tap can drive the same
/// action twice within a few hundred milliseconds, and the second one should
/// not be audible.
abstract final class AppSounds {
  /// A product saved to the wishlist.
  static final wishlist = AppSound(
    'assets/sounds/wishlist.wav',
    gap: const Duration(milliseconds: 300),
  );

  /// A product added to the cart.
  static final addToCart = AppSound(
    'assets/sounds/add_to_cart.wav',
    gap: const Duration(milliseconds: 300),
  );

  /// A line taken out of the cart, or a product taken off the wishlist.
  ///
  /// A longer gap than the rest: removing several rows in a row is a normal
  /// thing to do, and one sound per tap in a burst is noise.
  static final removed = AppSound(
    'assets/sounds/delete_remove.wav',
    gap: const Duration(milliseconds: 600),
  );

  /// Something put back after being removed.
  ///
  /// The same gap as the removal it undoes: "Undo all" on the wishlist puts
  /// several products back at once, and that is one act of undoing, not one
  /// per row.
  static final undo = AppSound(
    'assets/sounds/undo.wav',
    gap: const Duration(milliseconds: 600),
  );

  /// An order the server has accepted and given a number.
  static final orderConfirmed = AppSound(
    'assets/sounds/order_confirmed.wav',
    gap: const Duration(seconds: 2),
  );

  /// A payment the provider has confirmed as taken.
  static final paymentSuccessful = AppSound(
    'assets/sounds/payment_successful.wav',
    gap: const Duration(seconds: 2),
  );

  /// A payment the provider has confirmed as refused.
  ///
  /// Not for a payment that is merely unfinished: a shopper who backed out of
  /// the gateway, or one whose money is still being checked, has not been
  /// told no.
  static final paymentFailed = AppSound(
    'assets/sounds/payment_failed.wav',
    gap: const Duration(seconds: 2),
  );
}
