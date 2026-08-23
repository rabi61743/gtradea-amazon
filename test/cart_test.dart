import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/cart/presentation/cart_screen.dart';
import 'package:gtradea_amazon/features/checkout/presentation/checkout_screen.dart';
import 'package:gtradea_amazon/features/product/data/product_detail_content.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _jacketPink = CartLine(
  productId: 'jacket',
  variantLabel: 'Blush pink',
  title: 'Ice silk jacket',
  unitPrice: 1130,
  listPrice: 1568,
  freeDelivery: true,
);

const _jacketIvory = CartLine(
  productId: 'jacket',
  variantLabel: 'Ivory',
  title: 'Ice silk jacket',
  unitPrice: 1130,
  listPrice: 1568,
  freeDelivery: true,
);

/// No free delivery and no list price, so it exercises the other branch of
/// both the delivery rule and the savings rule.
const _dress = CartLine(
  productId: 'dress',
  title: 'Suspender dress',
  unitPrice: 1808,
);

/// A product whose first colourway is gone, to prove the page does not open on
/// an option the picker refuses to select.
const _firstVariantSoldOut = ProductDetail(
  title: 'Test jacket',
  price: 1000,
  rating: 4,
  reviewCount: 1,
  images: ['https://example.invalid/1.jpg'],
  variants: [
    ProductVariant(
      label: 'Blush pink',
      imageUrl: 'https://example.invalid/p.jpg',
      inStock: false,
    ),
    ProductVariant(label: 'Ivory', imageUrl: 'https://example.invalid/i.jpg'),
  ],
  specs: [],
  description: 'x',
);

/// Nothing left at all, so there is no in-stock option to fall back to.
const _allSoldOut = ProductDetail(
  title: 'Test jacket',
  price: 1000,
  rating: 4,
  reviewCount: 1,
  images: ['https://example.invalid/1.jpg'],
  variants: [
    ProductVariant(
      label: 'Blush pink',
      imageUrl: 'https://example.invalid/p.jpg',
      inStock: false,
    ),
  ],
  specs: [],
  description: 'x',
);

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

/// The default 600x800 test window hides anything below the fold, so widget
/// tests that need the summary and the checkout bar get a taller surface.
void _useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
  });

  group('CartLine', () {
    test('variant is part of the identity', () {
      expect(_jacketPink.key, isNot(_jacketIvory.key));
      expect(_dress.key, 'dress', reason: 'no variant still has a stable key');
    });

    test('a delimiter in the title cannot collide two products onto one line',
        () {
      // The product id here is the title, so it can contain anything a visible
      // separator would have used.
      const a = CartLine(productId: 'Shirt|Red', title: 'x', unitPrice: 1);
      const b = CartLine(
        productId: 'Shirt',
        variantLabel: 'Red',
        title: 'x',
        unitPrice: 1,
      );
      expect(a.key, isNot(b.key));
    });

    test('line total multiplies by quantity', () {
      expect(_jacketPink.copyWith(quantity: 3).lineTotal, 3390);
    });

    test('saving is only claimed when the list price is above the price', () {
      expect(_jacketPink.lineSaving, 438);
      expect(_dress.lineSaving, isNull);
      // A "was" price at or below the price is not a saving.
      const fake = CartLine(
        productId: 'x',
        title: 'x',
        unitPrice: 100,
        listPrice: 100,
      );
      expect(fake.lineSaving, isNull);
    });

    test('VAT is back-solved out of the price, not added to it', () {
      // 1130 includes 13% VAT: 1130 * 13/113 = 130.
      expect(_jacketPink.vatIncluded.round(), 130);
    });
  });

  group('CartStore', () {
    test('adding twice bumps the quantity instead of duplicating the line', () {
      final store = CartStore.instance;
      expect(store.add(_jacketPink), 1);
      expect(store.add(_jacketPink), 2);
      expect(store.lineCount, 1);
      expect(store.count, 2, reason: 'the badge counts units');
    });

    test('two variants of one product are two lines', () {
      final store = CartStore.instance
        ..add(_jacketPink)
        ..add(_jacketIvory);
      expect(store.lineCount, 2);
      expect(store.count, 2);
    });

    test('newest line comes first', () {
      final store = CartStore.instance
        ..add(_jacketPink)
        ..add(_dress);
      expect(store.lines.map((l) => l.productId), ['dress', 'jacket']);
    });

    test('quantity is clamped to the line floor and the ceiling', () {
      final store = CartStore.instance..add(_jacketPink);
      final key = _jacketPink.key;

      store.decrement(key);
      expect(store.lineFor('jacket', 'Blush pink')?.quantity, 1,
          reason: 'decrementing at the floor does not remove the line');

      store.setQuantity(key, 500);
      expect(store.lineFor('jacket', 'Blush pink')?.quantity,
          CartStore.maxPerLine);
    });

    test('a minimum order is a real floor', () {
      const bulk = CartLine(
        productId: 'bulk',
        title: 'Bulk pack',
        unitPrice: 50,
        minOrder: 5,
        quantity: 5,
      );
      final store = CartStore.instance..add(bulk);
      store.decrement(bulk.key);
      expect(store.lineFor('bulk')?.quantity, 5);
    });

    test('remove takes the line out and restore puts it back in place', () {
      final store = CartStore.instance
        ..add(_jacketPink)
        ..add(_dress);
      // dress is at 0, jacket at 1.
      final index = store.indexOf(_dress.key);
      store.remove(_dress.key);
      expect(store.lineCount, 1);

      store.restore(_dress, index);
      expect(store.lines.map((l) => l.productId), ['dress', 'jacket']);
    });

    test('restoring a line that is already there is a no-op', () {
      final store = CartStore.instance..add(_jacketPink);
      store.restore(_jacketPink, 0);
      expect(store.lineCount, 1);
    });

    test('notifies on every mutation so the badge cannot go stale', () {
      var notifications = 0;
      void listener() => notifications++;
      CartStore.instance.addListener(listener);
      addTearDown(() => CartStore.instance.removeListener(listener));

      CartStore.instance.add(_jacketPink);
      CartStore.instance.increment(_jacketPink.key);
      CartStore.instance.decrement(_jacketPink.key);
      CartStore.instance.remove(_jacketPink.key);
      expect(notifications, 4);
    });

    test('a no-op quantity change does not notify', () {
      CartStore.instance.add(_jacketPink);
      var notifications = 0;
      void listener() => notifications++;
      CartStore.instance.addListener(listener);
      addTearDown(() => CartStore.instance.removeListener(listener));

      CartStore.instance.setQuantity(_jacketPink.key, 1);
      expect(notifications, 0);
    });
  });

  group('totals', () {
    test('an empty cart owes nothing', () {
      expect(CartStore.instance.totals.isEmpty, isTrue);
      expect(CartStore.instance.totals.total, 0);
    });

    test('subtotal, savings and item count add up across lines', () {
      CartStore.instance
        ..add(_jacketPink.copyWith(quantity: 2))
        ..add(_dress);
      final totals = CartStore.instance.totals;

      expect(totals.subtotal, 1130 * 2 + 1808);
      expect(totals.savings, 438 * 2);
      expect(totals.itemCount, 3);
      expect(totals.lineCount, 2);
    });

    test('delivery is free only when every line is free-delivery', () {
      CartStore.instance.add(_jacketPink);
      expect(CartStore.instance.totals.delivery, 0);

      // The dress is not free-delivery, so the order is charged.
      CartStore.instance.add(_dress);
      expect(CartStore.instance.totals.delivery, CartStore.deliveryFee);
    });

    test('total is subtotal plus delivery, with VAT inside not added on top',
        () {
      CartStore.instance.add(_jacketPink);
      final totals = CartStore.instance.totals;

      expect(totals.total, 1130, reason: 'free delivery on this line');
      expect(totals.vatIncluded.round(), 130);
      // The VAT figure must not appear in the total. 1130 + 130 would be the
      // double-charge this guards against.
      expect(totals.total, isNot(1260));
    });
  });

  group('persistence', () {
    test('a cart survives a reload from disk', () async {
      CartStore.instance.add(_jacketPink.copyWith(quantity: 3));
      await Future<void>.delayed(Duration.zero);

      CartStore.instance.resetForTest();
      await CartStore.instance.load();

      expect(CartStore.instance.count, 3);
      expect(CartStore.instance.lineFor('jacket', 'Blush pink')?.title,
          'Ice silk jacket');
    });

    test('a corrupt cart degrades to empty rather than throwing', () async {
      SharedPreferences.setMockInitialValues({'gtradea_cart': 'not json'});
      CartStore.instance.resetForTest();
      await CartStore.instance.load();
      expect(CartStore.instance.isEmpty, isTrue);
    });

    test('a line with no product id is skipped, not fatal', () async {
      SharedPreferences.setMockInitialValues({
        'gtradea_cart':
            '[{"title":"no id","unitPrice":1},'
                '{"productId":"ok","title":"Fine","unitPrice":2}]',
      });
      CartStore.instance.resetForTest();
      await CartStore.instance.load();
      expect(CartStore.instance.lines.map((l) => l.productId), ['ok']);
    });

    test('a line with no usable price is dropped, not shown as free', () async {
      SharedPreferences.setMockInitialValues({
        'gtradea_cart':
            '[{"productId":"bad","title":"No price"},'
                '{"productId":"zero","title":"Free?","unitPrice":0},'
                '{"productId":"ok","title":"Fine","unitPrice":2}]',
      });
      CartStore.instance.resetForTest();
      await CartStore.instance.load();
      // Rs. 0 is what the shopper would be asked to pay.
      expect(CartStore.instance.lines.map((l) => l.productId), ['ok']);
    });

    test('a stored quantity of zero is repaired to the floor', () async {
      SharedPreferences.setMockInitialValues({
        'gtradea_cart':
            '[{"productId":"ok","title":"Fine","unitPrice":2,"quantity":0}]',
      });
      CartStore.instance.resetForTest();
      await CartStore.instance.load();
      expect(CartStore.instance.lines.single.quantity, 1,
          reason: 'a zero-quantity line would be invisible but still counted');
    });
  });

  group('guest and signed-in carts', () {
    test('signing in merges the guest cart into the account cart', () async {
      CartStore.instance.add(_jacketPink);
      await CartStore.instance.switchIdentity('rabi@example.com');

      expect(CartStore.instance.count, 1);
      expect(CartStore.instance.lineFor('jacket', 'Blush pink'), isNotNull);
    });

    test('merging adds quantities for a line the account already had',
        () async {
      // Seed an account cart on disk with 2, then sign in holding 1 as a guest.
      SharedPreferences.setMockInitialValues({
        'gtradea_cart_rabi@example.com':
            '[{"productId":"jacket","variantLabel":"Blush pink",'
                '"title":"Ice silk jacket","unitPrice":1130,"quantity":2}]',
      });
      CartStore.instance.resetForTest();
      await CartStore.instance.load();
      CartStore.instance.add(_jacketPink);

      await CartStore.instance.switchIdentity('rabi@example.com');
      expect(CartStore.instance.lineCount, 1);
      expect(CartStore.instance.count, 3);
    });

    test('the guest cart is emptied once it has been merged', () async {
      CartStore.instance.add(_jacketPink);
      await CartStore.instance.switchIdentity('rabi@example.com');
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('gtradea_cart'), isNull);
    });

    test('signing out leaves the account cart on disk under its own key',
        () async {
      await CartStore.instance.switchIdentity('rabi@example.com');
      CartStore.instance.add(_dress);
      await Future<void>.delayed(Duration.zero);

      await CartStore.instance.switchIdentity(null);
      expect(CartStore.instance.isEmpty, isTrue,
          reason: 'the guest cart was empty');

      // Signing back in brings it back.
      await CartStore.instance.switchIdentity('rabi@example.com');
      expect(CartStore.instance.lineFor('dress'), isNotNull);
    });

    test('two accounts do not see each other carts', () async {
      await CartStore.instance.switchIdentity('a@example.com');
      CartStore.instance.add(_jacketPink);
      await Future<void>.delayed(Duration.zero);

      await CartStore.instance.switchIdentity('b@example.com');
      expect(CartStore.instance.isEmpty, isTrue);
    });

    test('the store follows AuthStore once bound', () async {
      CartStore.instance.bindToAuth();
      CartStore.instance.add(_jacketPink);

      AuthStore.instance.signIn(email: 'rabi@example.com');
      // The switch is async off the notification.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(CartStore.instance.count, 1,
          reason: 'the guest cart followed the shopper into their account');
    });
  });

  group('CartScreen', () {
    testWidgets('explains itself when empty', (tester) async {
      await tester.pumpWidget(_wrap(const CartScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Your cart is empty'), findsOneWidget);
      expect(find.text('Checkout'), findsNothing,
          reason: 'nothing to check out');
      expect(find.text('Empty'), findsNothing);
    });

    testWidgets('lists lines with variant, unit price and line total',
        (tester) async {
      _useTallWindow(tester);
      CartStore.instance.add(_jacketPink.copyWith(quantity: 2));
      await tester.pumpWidget(_wrap(const CartScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Ice silk jacket'), findsOneWidget);
      expect(find.text('Blush pink'), findsOneWidget);
      expect(find.text('Rs. 1,130'), findsOneWidget, reason: 'unit price');
      expect(find.text('Rs. 2,260'), findsWidgets, reason: 'line total');
      expect(find.text('Cart (2 items)'), findsOneWidget);
    });

    testWidgets('the stepper changes the quantity and the totals', (tester) async {
      _useTallWindow(tester);
      CartStore.instance.add(_jacketPink);
      await tester.pumpWidget(_wrap(const CartScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(CartStore.instance.count, 2);
      expect(find.text('Cart (2 items)'), findsOneWidget);

      await tester.tap(find.byTooltip('Fewer'));
      await tester.pumpAndSettle();
      expect(CartStore.instance.count, 1);
    });

    testWidgets('Fewer is disabled at the floor rather than deleting the line',
        (tester) async {
      _useTallWindow(tester);
      CartStore.instance.add(_jacketPink);
      await tester.pumpWidget(_wrap(const CartScreen()));
      await tester.pumpAndSettle();

      // byTooltip finds the Tooltip the IconButton builds, so the button is
      // its ancestor rather than its descendant.
      final fewer = tester.widget<IconButton>(
        find
            .ancestor(
              of: find.byTooltip('Fewer'),
              matching: find.byType(IconButton),
            )
            .first,
      );
      expect(fewer.onPressed, isNull);
    });

    testWidgets('removing a line offers an undo that really restores it',
        (tester) async {
      _useTallWindow(tester);
      CartStore.instance.add(_jacketPink);
      await tester.pumpWidget(_wrap(const CartScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove'));
      await tester.pump();
      expect(CartStore.instance.isEmpty, isTrue);

      // Let the snack bar finish animating in; tapping mid-slide misses it.
      await tester.pump(const Duration(milliseconds: 750));
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(CartStore.instance.contains('jacket', 'Blush pink'), isTrue);
    });

    testWidgets('emptying the whole cart asks first', (tester) async {
      _useTallWindow(tester);
      CartStore.instance.add(_jacketPink);
      await tester.pumpWidget(_wrap(const CartScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Empty'));
      await tester.pumpAndSettle();
      expect(find.text('Empty your cart?'), findsOneWidget);

      await tester.tap(find.text('Keep them'));
      await tester.pumpAndSettle();
      expect(CartStore.instance.isEmpty, isFalse);
    });

    testWidgets('the summary shows savings, free delivery and the total',
        (tester) async {
      _useTallWindow(tester);
      CartStore.instance.add(_jacketPink);
      await tester.pumpWidget(_wrap(const CartScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Subtotal (1 item)'), findsOneWidget);
      expect(find.text('-Rs. 438'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Includes Rs. 130 VAT'), findsOneWidget);
    });

    testWidgets('a charged delivery is shown as a figure, not as free',
        (tester) async {
      _useTallWindow(tester);
      CartStore.instance.add(_dress);
      await tester.pumpWidget(_wrap(const CartScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Free'), findsNothing);
      expect(find.text('Rs. 100'), findsOneWidget);
      // 1808 + 100 delivery.
      expect(find.text('Rs. 1,908'), findsWidgets);
    });
  });

  group('checkout', () {
    testWidgets('Checkout opens with the cart data it was given',
        (tester) async {
      _useTallWindow(tester);
      CartStore.instance.add(_jacketPink.copyWith(quantity: 2));
      await tester.pumpWidget(_wrap(const CartScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();

      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(find.text('Order summary'), findsOneWidget);
      expect(find.text('Blush pink · Qty 2'), findsOneWidget);
      expect(find.text('Place order · Rs. 2,260'), findsOneWidget);
    });

    testWidgets('placing the order empties the cart and confirms',
        (tester) async {
      _useTallWindow(tester);
      CartStore.instance.add(_jacketPink);
      await tester.pumpWidget(_wrap(const CartScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Place order'));
      await tester.pumpAndSettle();

      expect(find.text('Order placed'), findsOneWidget);
      expect(CartStore.instance.isEmpty, isTrue);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Back on the cart, which is now empty.
      expect(find.text('Your cart is empty'), findsOneWidget);
    });

    testWidgets('an item added after checkout opened survives the order',
        (tester) async {
      _useTallWindow(tester);
      CartStore.instance.add(_jacketPink);
      await tester.pumpWidget(_wrap(const CartScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();

      // Something lands in the cart while checkout is open. It is not part of
      // this order and must not be cleared by it.
      CartStore.instance.add(_dress);

      await tester.tap(find.textContaining('Place order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(CartStore.instance.lineFor('dress'), isNotNull);
      expect(CartStore.instance.contains('jacket', 'Blush pink'), isFalse);
    });
  });

  group('add to cart from the product page', () {
    testWidgets('Add to cart puts the selected variant in the cart',
        (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const ProductDetailScreen()));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Add to cart'));
      await tester.pump();

      final line = CartStore.instance.lines.single;
      expect(line.variantLabel, 'Blush pink', reason: 'the default variant');
      expect(line.quantity, 1);
      expect(line.freeDelivery, isTrue);
      expect(find.textContaining('Added Blush pink to your cart'),
          findsOneWidget);
    });

    testWidgets('the app-bar badge counts what was added', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const ProductDetailScreen()));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Add to cart'));
      await tester.pump();
      await tester.pump();

      expect(
        find.descendant(of: find.byType(Badge), matching: find.text('1')),
        findsWidgets,
      );
    });

    testWidgets('the quantity chosen on the page is the quantity added',
        (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const ProductDetailScreen()));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      await tester.tap(find.text('Add to cart'));
      await tester.pump();

      expect(CartStore.instance.count, 2);
    });

    testWidgets('the page opens on a buyable colour, not a sold-out one',
        (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(
        const ProductDetailScreen(product: _firstVariantSoldOut),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      // Index 0 is sold out and the picker refuses to select it, so opening
      // there would strand the page on an option that cannot be bought.
      expect(find.text('Ivory'), findsWidgets);
      await tester.tap(find.text('Add to cart'));
      await tester.pump();
      expect(CartStore.instance.lines.single.variantLabel, 'Ivory');
    });

    testWidgets('a sold-out selection is refused by the page, not just hidden',
        (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(
        const ProductDetailScreen(product: _allSoldOut),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Add to cart'));
      await tester.pump();

      expect(CartStore.instance.isEmpty, isTrue);
      expect(find.textContaining('is sold out'), findsOneWidget);
    });

    testWidgets('Buy now adds the line and goes straight to the cart',
        (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const ProductDetailScreen()));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.textContaining('Buy · '));
      await tester.pumpAndSettle();

      expect(find.byType(CartScreen), findsOneWidget);
      expect(CartStore.instance.count, 1);
    });
  });
}
