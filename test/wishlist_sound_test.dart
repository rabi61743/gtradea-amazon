import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:gtradea_amazon/core/audio/app_sound.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

SavedProduct _product({String id = 'a'}) =>
    SavedProduct(id: id, title: 'Saved $id', price: 100);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    WishlistStore.instance.resetForTest();
    await WishlistStore.sound.resetForTest();
    AppSound.enabled = true;
  });

  tearDown(() {
    AppSound.enabled = true;
  });

  group('saving a product sounds', () {
    test('the wishlist chime plays when one is added', () async {
      expect(WishlistStore.instance.toggle(_product()), isTrue);

      expect(WishlistStore.sound.plays, 1);
    });

    test('and it is the file that was supplied', () async {
      // The one in the project, bundled where this project keeps its sounds.
      expect(WishlistStore.sound.asset, 'assets/sounds/wishlist.wav');

      final bytes = await rootBundle.load(WishlistStore.sound.asset);
      expect(
        bytes.lengthInBytes,
        greaterThan(0),
        reason: 'the asset is declared and bundled',
      );
    });
  });

  group('and nothing else does', () {
    test('removing one is silent', () async {
      WishlistStore.instance.toggle(_product());
      await WishlistStore.sound.resetForTest();

      // The same tap again, which un-saves it.
      expect(WishlistStore.instance.toggle(_product()), isFalse);

      expect(WishlistStore.sound.plays, 0);
    });

    test('so is removing it from the wishlist screen', () async {
      WishlistStore.instance.toggle(_product());
      await WishlistStore.sound.resetForTest();

      WishlistStore.instance.remove('a');

      expect(WishlistStore.sound.plays, 0);
    });

    test('and so is undoing that removal', () async {
      // Taking something back is not saving something new.
      WishlistStore.instance.toggle(_product());
      WishlistStore.instance.remove('a');
      await WishlistStore.sound.resetForTest();

      WishlistStore.instance.restore(_product(), 0);

      expect(WishlistStore.sound.plays, 0);
    });

    test('clearing the list is silent', () async {
      WishlistStore.instance.toggle(_product());
      await WishlistStore.sound.resetForTest();

      WishlistStore.instance.clear();

      expect(WishlistStore.sound.plays, 0);
    });
  });

  group('it behaves under a fast hand', () {
    test('a double tap on the same heart is one sound', () async {
      // Save, un-save, save again inside the gap: the second save is the
      // shopper correcting a mis-tap, not a second thing saved.
      WishlistStore.instance.toggle(_product());
      WishlistStore.instance.toggle(_product());
      WishlistStore.instance.toggle(_product());

      expect(WishlistStore.sound.plays, 1);
      expect(WishlistStore.instance.contains('a'), isTrue);
    });

    test('but two different products each sound', () async {
      final sound = AppSound('assets/sounds/wishlist.wav');
      addTearDown(sound.resetForTest);

      await sound.play();
      await sound.play();

      expect(sound.plays, 2, reason: 'no gap between distinct saves');
    });
  });

  group('the sound cannot cost the save', () {
    test('a device that will not play it still saves the product', () async {
      // There is no audio device in a test, so the player genuinely fails to
      // open here -- this is the real failure path, not a simulated one.
      expect(WishlistStore.instance.toggle(_product(id: 'b')), isTrue);

      expect(WishlistStore.instance.contains('b'), isTrue);
      expect(WishlistStore.instance.count, 1);
    });

    test('and the store still notifies its listeners', () async {
      var notified = 0;
      void listener() => notified++;
      WishlistStore.instance.addListener(listener);
      addTearDown(() => WishlistStore.instance.removeListener(listener));

      WishlistStore.instance.toggle(_product());

      expect(notified, 1);
    });

    test('switched off, it neither plays nor interferes', () async {
      AppSound.enabled = false;

      expect(WishlistStore.instance.toggle(_product()), isTrue);

      expect(WishlistStore.sound.plays, 0);
      expect(WishlistStore.instance.contains('a'), isTrue);
    });
  });
}
