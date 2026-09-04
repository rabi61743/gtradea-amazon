import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/audio/app_sound.dart';
import 'package:gtradea_amazon/core/audio/app_sounds.dart';
import 'package:gtradea_amazon/core/audio/sound_settings.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

CartLine _line({String id = 'p-1', int quantity = 1}) => CartLine(
  productId: id,
  title: 'Product $id',
  unitPrice: 100,
  quantity: quantity,
);

SavedProduct _saved({String id = 'a'}) =>
    SavedProduct(id: id, title: 'Saved $id', price: 100);

/// Every sound the app owns, so a test can prove the others stayed quiet.
final _all = <String, AppSound>{
  'wishlist': AppSounds.wishlist,
  'addToCart': AppSounds.addToCart,
  'removed': AppSounds.removed,
  'undo': AppSounds.undo,
  'orderConfirmed': AppSounds.orderConfirmed,
  'paymentSuccessful': AppSounds.paymentSuccessful,
  'paymentFailed': AppSounds.paymentFailed,
};

/// Which sounds played, by name.
Set<String> _played() => {
  for (final entry in _all.entries)
    if (entry.value.plays > 0) entry.key,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SoundSettings.instance.resetForTest();
    WishlistStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    for (final sound in _all.values) {
      await sound.resetForTest();
    }
    AppSound.enabled = true;
  });

  tearDown(() {
    AppSound.enabled = true;
    SoundSettings.instance.resetForTest();
  });

  group('the files that were supplied', () {
    test('each sound points at its own bundled asset', () async {
      expect(AppSounds.addToCart.asset, 'assets/sounds/add_to_cart.wav');
      expect(AppSounds.removed.asset, 'assets/sounds/delete_remove.wav');
      expect(
        AppSounds.orderConfirmed.asset,
        'assets/sounds/order_confirmed.wav',
      );
      expect(
        AppSounds.paymentSuccessful.asset,
        'assets/sounds/payment_successful.wav',
      );
      expect(AppSounds.paymentFailed.asset, 'assets/sounds/payment_failed.wav');
      expect(AppSounds.undo.asset, 'assets/sounds/undo.wav');
    });

    test('and every one of them is actually bundled', () async {
      for (final sound in _all.values) {
        final bytes = await rootBundle.load(sound.asset);
        expect(bytes.lengthInBytes, greaterThan(0), reason: sound.asset);
      }
    });

    test('every sound is its own file', () async {
      // A file copied under several names would make different actions sound
      // alike.
      final digests = <int>{};
      for (final sound in _all.values) {
        final bytes = await rootBundle.load(sound.asset);
        digests.add(Object.hashAll(bytes.buffer.asUint8List()));
      }
      expect(digests, hasLength(_all.length));
    });
  });

  group('adding to the cart', () {
    test('sounds, and nothing else does', () {
      CartStore.instance.add(_line());

      expect(_played(), {'addToCart'});
    });
  });

  group('removing', () {
    test('a cart line sounds the removal', () {
      CartStore.instance.add(_line());
      AppSounds.addToCart.plays = 0;

      CartStore.instance.remove(_line().key);

      expect(_played(), {'removed'});
    });

    test('a wishlist product sounds it too', () {
      WishlistStore.instance.toggle(_saved());
      AppSounds.wishlist.plays = 0;

      WishlistStore.instance.remove('a');

      expect(_played(), {'removed'});
    });

    test('and so does un-hearting one', () {
      WishlistStore.instance.toggle(_saved());
      AppSounds.wishlist.plays = 0;

      WishlistStore.instance.toggle(_saved());

      expect(_played(), {'removed'});
    });

    test('but removing what is not there is silent', () {
      // Nothing was deleted, so nothing happened.
      CartStore.instance.remove('missing');
      WishlistStore.instance.remove('missing');

      expect(_played(), isEmpty);
    });

    test('and a silenced removal makes no sound', () {
      // What checkout and undo use.
      CartStore.instance.add(_line());
      WishlistStore.instance.toggle(_saved());
      for (final sound in _all.values) {
        sound.plays = 0;
      }

      CartStore.instance.remove(_line().key, announce: false);
      WishlistStore.instance.remove('a', announce: false);

      expect(_played(), isEmpty);
    });

    test('putting something back is an undo, not a removal', () {
      WishlistStore.instance.toggle(_saved());
      WishlistStore.instance.remove('a');
      for (final sound in _all.values) {
        sound.plays = 0;
      }

      WishlistStore.instance.restore(_saved(), 0);

      expect(_played(), {'undo'});
    });

    test('and so is putting a cart line back', () {
      CartStore.instance.add(_line());
      final line = CartStore.instance.lines.single;
      CartStore.instance.remove(line.key);
      for (final sound in _all.values) {
        sound.plays = 0;
      }

      CartStore.instance.restore(line, 0);

      expect(_played(), {'undo'});
      expect(CartStore.instance.count, 1);
    });

    test('but restoring what is already there is silent', () {
      // Undoing twice undoes once.
      CartStore.instance.add(_line());
      final line = CartStore.instance.lines.single;
      for (final sound in _all.values) {
        sound.plays = 0;
      }

      CartStore.instance.restore(line, 0);
      WishlistStore.instance.toggle(_saved());
      for (final sound in _all.values) {
        sound.plays = 0;
      }
      WishlistStore.instance.restore(_saved(), 0);

      expect(_played(), isEmpty);
    });
  });

  group('the sound setting governs all of them', () {
    test('off: none of these actions make a sound', () async {
      await SoundSettings.instance.setEnabled(false);

      CartStore.instance.add(_line());
      CartStore.instance.remove(_line().key);
      WishlistStore.instance.toggle(_saved());

      expect(_played(), isEmpty);
    });

    test('and the actions themselves still happen', () async {
      await SoundSettings.instance.setEnabled(false);

      CartStore.instance.add(_line());

      expect(CartStore.instance.count, 1);
    });

    test('on again: they sound again', () async {
      await SoundSettings.instance.setEnabled(false);
      CartStore.instance.add(_line());
      expect(_played(), isEmpty);

      await SoundSettings.instance.setEnabled(true);
      CartStore.instance.add(_line(id: 'p-2'));

      expect(_played(), {'addToCart'});
    });
  });

  group('a repeated action is one sound', () {
    test('adding the same product twice in a moment', () {
      // A double tap, or a rebuild that fires the handler again.
      CartStore.instance.add(_line());
      CartStore.instance.add(_line());
      CartStore.instance.add(_line());

      expect(AppSounds.addToCart.plays, 1);
      expect(CartStore.instance.count, 3, reason: 'all three were added');
    });

    test('and clearing a whole cart is not a burst of removals', () {
      CartStore.instance
        ..add(_line(id: 'p-1'))
        ..add(_line(id: 'p-2'))
        ..add(_line(id: 'p-3'));
      for (final sound in _all.values) {
        sound.plays = 0;
      }

      CartStore.instance
        ..remove(_line(id: 'p-1').key)
        ..remove(_line(id: 'p-2').key)
        ..remove(_line(id: 'p-3').key);

      expect(AppSounds.removed.plays, 1);
      expect(CartStore.instance.isEmpty, isTrue);
    });
  });
}
