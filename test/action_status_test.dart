import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/audio/app_sound.dart';
import 'package:gtradea_amazon/core/audio/app_sounds.dart';
import 'package:gtradea_amazon/core/audio/sound_settings.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/core/ui/action_status.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/catalog/data/product.dart';
import 'package:gtradea_amazon/features/home/widgets/product_carousel.dart'
    show toggleSavedProduct;
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _product = Product(
  numIid: 'p-1',
  title: 'Ice silk jacket',
  displayPrice: 1130,
);

/// A page with a button that performs [action], so a status can be raised the
/// way the app raises one -- through the ScaffoldMessenger of a real route.
Widget _page(void Function(BuildContext context) action) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () => action(context),
          child: const Text('do it'),
        ),
      ),
    ),
  ),
);

Future<void> _tap(WidgetTester tester) async {
  await tester.tap(find.text('do it'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SoundSettings.instance.resetForTest();
    WishlistStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    for (final sound in [
      AppSounds.wishlist,
      AppSounds.addToCart,
      AppSounds.removed,
    ]) {
      await sound.resetForTest();
    }
    AppSound.enabled = true;
  });

  tearDown(() {
    AppSound.enabled = true;
    SoundSettings.instance.resetForTest();
  });

  group('the wishlist says what happened', () {
    testWidgets('saving one says Added to Wishlist, and sounds', (
      tester,
    ) async {
      await tester.pumpWidget(_page((c) => toggleSavedProduct(c, _product)));

      await _tap(tester);

      expect(find.text(ActionStatus.addedToWishlist), findsOneWidget);
      expect(find.text('Added to Wishlist'), findsOneWidget);
      expect(WishlistStore.instance.contains('p-1'), isTrue);
      expect(AppSounds.wishlist.plays, 1);
    });

    testWidgets('and taking it off says Removed from Wishlist', (tester) async {
      await tester.pumpWidget(_page((c) => toggleSavedProduct(c, _product)));
      await _tap(tester);
      await AppSounds.removed.resetForTest();

      await _tap(tester);

      expect(find.text('Removed from Wishlist'), findsOneWidget);
      expect(find.text('Added to Wishlist'), findsNothing);
      expect(WishlistStore.instance.contains('p-1'), isFalse);
      expect(AppSounds.removed.plays, 1);
    });

    testWidgets('a fast hand leaves one status, not a queue', (tester) async {
      // Each status replaces the one before it. Queued messages mean a shopper
      // reads "Added" three taps after they last added anything.
      await tester.pumpWidget(_page((c) => toggleSavedProduct(c, _product)));

      await tester.tap(find.text('do it'));
      await tester.tap(find.text('do it'));
      await tester.tap(find.text('do it'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('the status is one phrase per event', () {
    test('and they are the four the shopper sees', () {
      // Written six different ways across six screens before this.
      expect(ActionStatus.addedToCartLabel, 'Added to Cart');
      expect(ActionStatus.removedFromCart, 'Removed from Cart');
      expect(ActionStatus.addedToWishlist, 'Added to Wishlist');
      expect(ActionStatus.removedFromWishlist, 'Removed from Wishlist');
    });

    testWidgets('a detail is appended, not substituted', (tester) async {
      await tester.pumpWidget(
        _page(
          (c) => ActionStatus.show(
            c,
            ActionStatus.addedToCartLabel,
            detail: '3 in cart',
          ),
        ),
      );

      await _tap(tester);

      expect(find.text('Added to Cart · 3 in cart'), findsOneWidget);
    });

    testWidgets('an action rides along with it', (tester) async {
      await tester.pumpWidget(
        _page(
          (c) => ActionStatus.show(
            c,
            ActionStatus.removedFromCart,
            action: SnackBarAction(label: 'Undo', onPressed: () {}),
          ),
        ),
      );

      await _tap(tester);

      expect(find.text('Removed from Cart'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });
  });

  group('with sound off', () {
    testWidgets('the status still shows -- it is not a sound', (tester) async {
      await SoundSettings.instance.setEnabled(false);
      await tester.pumpWidget(_page((c) => toggleSavedProduct(c, _product)));

      await _tap(tester);

      expect(find.text('Added to Wishlist'), findsOneWidget);
      expect(AppSounds.wishlist.plays, 0);
      expect(WishlistStore.instance.contains('p-1'), isTrue);
    });
  });
}
