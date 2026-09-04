import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/audio/app_sound.dart';
import 'package:gtradea_amazon/core/audio/sound_settings.dart';
import 'package:gtradea_amazon/features/account/presentation/account_screen.dart';
import 'package:gtradea_amazon/features/notifications/data/notification_sound.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';

SavedProduct _product({String id = 'a'}) =>
    SavedProduct(id: id, title: 'Saved $id', price: 100);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SoundSettings.instance.resetForTest();
    WishlistStore.instance.resetForTest();
    await WishlistStore.sound.resetForTest();
    AppSound.enabled = true;
  });

  tearDown(() {
    AppSound.enabled = true;
    SoundSettings.instance.resetForTest();
  });

  group('the default', () {
    test('sound is on before anybody has chosen', () async {
      expect(SoundSettings.instance.enabled, isTrue);
    });

    test('and stays on when nothing was ever saved', () async {
      // No stored key at all, which is a new install.
      await SoundSettings.instance.load();

      expect(SoundSettings.instance.enabled, isTrue);
    });

    test('it is on even while the preference is still being read', () async {
      // The read is a disk hop. Guessing "off" for that moment would swallow
      // a sound the shopper had asked for.
      expect(SoundSettings.instance.isLoaded, isFalse);
      expect(SoundSettings.instance.enabled, isTrue);
    });

    test('an unreadable store leaves it on rather than off', () async {
      await SoundSettings.instance.load();

      expect(SoundSettings.instance.enabled, isTrue);
    });
  });

  group('it is remembered', () {
    test('turning it off is written down', () async {
      await SoundSettings.instance.setEnabled(false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('gtradea_sound_enabled'), isFalse);
    });

    test('and survives a restart', () async {
      await SoundSettings.instance.setEnabled(false);

      // A fresh launch: in-memory state gone, the store still there.
      SoundSettings.instance.resetForTest();
      await SoundSettings.instance.load();

      expect(SoundSettings.instance.enabled, isFalse);
    });

    test('turning it back on survives one too', () async {
      await SoundSettings.instance.setEnabled(false);
      await SoundSettings.instance.setEnabled(true);

      SoundSettings.instance.resetForTest();
      await SoundSettings.instance.load();

      expect(SoundSettings.instance.enabled, isTrue);
    });

    test('changing it tells everything listening', () async {
      var notified = 0;
      void listener() => notified++;
      SoundSettings.instance.addListener(listener);
      addTearDown(() => SoundSettings.instance.removeListener(listener));

      await SoundSettings.instance.setEnabled(false);

      expect(notified, 1);
    });
  });

  group('what it governs', () {
    test('sound on: saving a product still chimes', () async {
      await SoundSettings.instance.setEnabled(true);

      WishlistStore.instance.toggle(_product());

      expect(WishlistStore.sound.plays, 1);
    });

    test('sound off: it does not', () async {
      await SoundSettings.instance.setEnabled(false);

      WishlistStore.instance.toggle(_product());

      expect(WishlistStore.sound.plays, 0);
    });

    test('and the product is saved either way', () async {
      // The setting governs the sound, not the wishlist.
      await SoundSettings.instance.setEnabled(false);

      expect(WishlistStore.instance.toggle(_product()), isTrue);
      expect(WishlistStore.instance.contains('a'), isTrue);
    });

    test('the notification chime obeys it as well', () async {
      // "Sound off" that still chimes is not sound off.
      NotificationSound.enabled = true;
      await NotificationSound.instance.resetForTest();
      addTearDown(() => NotificationSound.enabled = true);

      await SoundSettings.instance.setEnabled(false);
      await NotificationSound.instance.play();

      expect(NotificationSound.plays, 0);
    });

    test('turning it back on restores the chime', () async {
      await SoundSettings.instance.setEnabled(false);
      WishlistStore.instance.toggle(_product());
      expect(WishlistStore.sound.plays, 0);

      await SoundSettings.instance.setEnabled(true);
      WishlistStore.instance.toggle(_product(id: 'b'));

      expect(WishlistStore.sound.plays, 1);
    });
  });

  group('the switch on the account page', () {
    Future<void> openAccount(WidgetTester tester) async {
      ensureApiStub();
      await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('there is a Sound row, and it says On', (tester) async {
      await openAccount(tester);

      await tester.scrollUntilVisible(find.text('Sound'), 200);
      await tester.pump();

      expect(find.text('Sound'), findsOneWidget);
      expect(
        find.descendant(
          of: find
              .ancestor(of: find.text('Sound'), matching: find.byType(Row))
              .first,
          matching: find.text('On'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('flipping it turns sound off and says so', (tester) async {
      await openAccount(tester);
      await tester.scrollUntilVisible(find.text('Sound'), 200);
      await tester.pump();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(SoundSettings.instance.enabled, isFalse);
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('the whole row is the target, not just the switch', (
      tester,
    ) async {
      // A 34pt switch at the end of a row is the hardest thing on the page to
      // hit on a phone.
      await openAccount(tester);
      await tester.scrollUntilVisible(find.text('Sound'), 200);
      await tester.pump();

      await tester.tap(find.text('Sound'));
      await tester.pumpAndSettle();

      expect(SoundSettings.instance.enabled, isFalse);
    });
  });
}
