import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/account/presentation/account_screen.dart';
import 'package:gtradea_amazon/features/account/data/recently_viewed_store.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/auth/presentation/auth_screen.dart';
import 'package:gtradea_amazon/features/product/presentation/product_detail_screen.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:gtradea_amazon/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

/// The default 600x800 test window hides anything below the fold, and the
/// account page is now several groups tall.
void _useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    WishlistStore.instance.resetForTest();
    RecentlyViewedStore.instance.resetForTest();
  });

  group('AuthStore', () {
    test('starts signed out, signs in, and signs back out', () {
      final store = AuthStore.instance;
      expect(store.isSignedIn, isFalse);
      expect(store.account, isNull);

      store.signIn(email: 'rabi@example.com', name: 'Rabi');
      expect(store.isSignedIn, isTrue);
      expect(store.account?.email, 'rabi@example.com');

      store.signOut();
      expect(store.isSignedIn, isFalse);
      expect(store.account, isNull);
    });

    test('notifies listeners so the UI can react', () {
      var notifications = 0;
      void listener() => notifications++;
      AuthStore.instance.addListener(listener);
      addTearDown(() => AuthStore.instance.removeListener(listener));

      AuthStore.instance.signIn(email: 'a@b.com');
      AuthStore.instance.signOut();
      expect(notifications, 2);
    });

    test('survives a reload from disk', () async {
      AuthStore.instance.signIn(email: 'rabi@example.com', name: 'Rabi');
      // Let the fire-and-forget write land before reading it back.
      await Future<void>.delayed(Duration.zero);

      AuthStore.instance.resetForTest();
      await AuthStore.instance.load();

      expect(AuthStore.instance.isSignedIn, isTrue);
      expect(AuthStore.instance.account?.name, 'Rabi');
    });

    test('signing out clears the stored session too', () async {
      AuthStore.instance.signIn(email: 'rabi@example.com');
      await Future<void>.delayed(Duration.zero);
      AuthStore.instance.signOut();
      await Future<void>.delayed(Duration.zero);

      AuthStore.instance.resetForTest();
      await AuthStore.instance.load();
      expect(AuthStore.instance.isSignedIn, isFalse);
    });

    test('a corrupt session degrades to signed out rather than throwing',
        () async {
      SharedPreferences.setMockInitialValues({'gtradea_account': 'not json'});
      AuthStore.instance.resetForTest();
      await AuthStore.instance.load();
      expect(AuthStore.instance.isSignedIn, isFalse);
    });

    test('a stored session with no email is not a session', () async {
      SharedPreferences.setMockInitialValues({
        'gtradea_account': '{"name":"Rabi"}',
      });
      AuthStore.instance.resetForTest();
      await AuthStore.instance.load();
      expect(AuthStore.instance.isSignedIn, isFalse);
    });

    test('an explicit sign-in beats a load still in flight', () async {
      SharedPreferences.setMockInitialValues({
        'gtradea_account': '{"email":"old@example.com"}',
      });
      AuthStore.instance.resetForTest();

      final pending = AuthStore.instance.load();
      AuthStore.instance.signIn(email: 'new@example.com');
      await pending;

      expect(AuthStore.instance.account?.email, 'new@example.com');
    });

    group('displayName', () {
      test('prefers the name', () {
        expect(
          const Account(email: 'rabi@example.com', name: 'Rabi Yadav')
              .displayName,
          'Rabi Yadav',
        );
      });

      test('falls back to the local part of the email', () {
        expect(const Account(email: 'rabi@example.com').displayName, 'rabi');
      });

      test('an empty name is not a name', () {
        expect(
          const Account(email: 'rabi@example.com', name: '   ').displayName,
          'rabi',
        );
      });
    });
  });

  group('bottom nav', () {
    testWidgets('reads "Sign in" when signed out', (tester) async {
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Account'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('flips to "Account" the moment the store changes',
        (tester) async {
      // The dynamic requirement: no navigation, no rebuild trigger other than
      // the store itself.
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Sign in'), findsOneWidget);

      AuthStore.instance.signIn(email: 'rabi@example.com', name: 'Rabi');
      await tester.pump();

      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);

      // And back again.
      AuthStore.instance.signOut();
      await tester.pump();
      expect(find.text('Sign in'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('opens the account page without stealing the nav selection',
        (tester) async {
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Sign In / Sign Up'), findsOneWidget);
    });
  });

  group('AccountScreen', () {
    testWidgets('offers both ways in when signed out', (tester) async {
      await tester.pumpWidget(_wrap(const AccountScreen()));
      await tester.pumpAndSettle();

      // The app bar carries the full wording the nav has no room for; the
      // buttons carry it again as actions.
      expect(find.text('Sign In / Sign Up'), findsOneWidget);
      expect(find.text('Welcome to GtradeA'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign In'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Sign Up'), findsOneWidget);

      // The quick actions are reachable whether or not there is an account.
      for (final action in ['Orders', 'Saved', 'Cart', 'Support']) {
        expect(find.text(action), findsOneWidget, reason: action);
      }
      expect(find.text('Sign out'), findsNothing);
    });

    testWidgets('a guest tapping Orders is asked to sign in, not fobbed off',
        (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const AccountScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();

      // A guest has no orders, so the tile leads somewhere useful rather than
      // promising a page that could never have anything in it for them.
      expect(find.byType(AuthScreen), findsOneWidget);
    });

    testWidgets('settings and information are grouped under headings',
        (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const AccountScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Account settings'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Delivery addresses'), findsOneWidget);
      expect(find.text('Help and information'), findsOneWidget);
      expect(find.text('Terms and policies'), findsOneWidget);

      // This is the customer's page: nothing here is about selling.
      expect(find.textContaining('Sell'), findsNothing);
    });

    testWidgets('shows who is signed in', (tester) async {
      _useTallWindow(tester);
      AuthStore.instance.signIn(email: 'rabi@example.com', name: 'Rabi Yadav');
      await tester.pumpWidget(_wrap(const AccountScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Hello, Rabi Yadav'), findsOneWidget);
      expect(find.text('rabi@example.com'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Sign In / Sign Up'), findsNothing);
      expect(find.text('Welcome to GtradeA'), findsNothing);
    });

    testWidgets('signing out asks first, and backing out keeps the session',
        (tester) async {
      _useTallWindow(tester);
      AuthStore.instance.signIn(email: 'rabi@example.com', name: 'Rabi');
      await tester.pumpWidget(_wrap(const AccountScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsOneWidget);

      await tester.tap(find.text('Stay signed in'));
      await tester.pumpAndSettle();
      expect(AuthStore.instance.isSignedIn, isTrue);
    });

    testWidgets('confirming sign-out flips the page in place', (tester) async {
      _useTallWindow(tester);
      AuthStore.instance.signIn(email: 'rabi@example.com', name: 'Rabi');
      await tester.pumpWidget(_wrap(const AccountScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(AuthStore.instance.isSignedIn, isFalse);
      // Same route, guest state -- nothing was popped.
      expect(find.text('Sign In / Sign Up'), findsOneWidget);
      expect(find.text('Welcome to GtradeA'), findsOneWidget);
    });
  });

  group('recently viewed', () {
    const jacket = SavedProduct(
      id: 'jacket',
      title: 'Ice silk jacket',
      price: 1130,
    );
    const dress = SavedProduct(id: 'dress', title: 'Suspender dress', price: 1808);

    test('records newest first and does not duplicate a repeat visit', () {
      final store = RecentlyViewedStore.instance
        ..record(jacket)
        ..record(dress);
      expect(store.items.map((e) => e.id), ['dress', 'jacket']);

      // Re-opening the jacket moves it back to the front rather than adding it
      // twice: a second visit is a stronger signal, not a new product.
      store.record(jacket);
      expect(store.items.map((e) => e.id), ['jacket', 'dress']);
      expect(store.count, 2);
    });

    test('re-recording what is already at the front changes nothing', () {
      final store = RecentlyViewedStore.instance..record(jacket);
      var notifications = 0;
      void listener() => notifications++;
      store.addListener(listener);
      addTearDown(() => store.removeListener(listener));

      store.record(jacket);
      expect(notifications, 0);
    });

    test('the list is capped', () {
      final store = RecentlyViewedStore.instance;
      for (var i = 0; i < RecentlyViewedStore.maxEntries + 5; i++) {
        store.record(SavedProduct(id: 'p$i', title: 'Product $i', price: 10));
      }
      expect(store.count, RecentlyViewedStore.maxEntries);
      expect(store.items.first.id, 'p16', reason: 'newest survives');
    });

    test('survives a reload from disk', () async {
      RecentlyViewedStore.instance.record(jacket);
      await Future<void>.delayed(Duration.zero);

      RecentlyViewedStore.instance.resetForTest();
      await RecentlyViewedStore.instance.load();
      expect(RecentlyViewedStore.instance.items.single.title, 'Ice silk jacket');
    });

    testWidgets('the rail is absent until something has been viewed',
        (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const AccountScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Recently viewed'), findsNothing);

      RecentlyViewedStore.instance.record(jacket);
      await tester.pumpAndSettle();

      expect(find.text('Recently viewed'), findsOneWidget);
      expect(find.text('Ice silk jacket'), findsOneWidget);
      expect(find.text('Rs. 1,130'), findsOneWidget);
    });

    testWidgets('opening a product records the visit', (tester) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const ProductDetailScreen()));
      await tester.pumpAndSettle();

      expect(RecentlyViewedStore.instance.items.single.title,
          'Ice Silk Sun Protection Clothing for Women, summer 2026');
    });
  });

  group('AuthScreen', () {
    testWidgets('rejects a malformed email and a short password',
        (tester) async {
      await tester.pumpWidget(_wrap(const AuthScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'not-an-email');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(AuthStore.instance.isSignedIn, isFalse);
    });

    testWidgets('a valid sign-in updates the store', (tester) async {
      await tester.pumpWidget(_wrap(const AuthScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'rabi@example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'correct-horse');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(AuthStore.instance.isSignedIn, isTrue);
      expect(AuthStore.instance.account?.email, 'rabi@example.com');
    });

    testWidgets('sign-up asks for a name and keeps it', (tester) async {
      await tester
          .pumpWidget(_wrap(const AuthScreen(initialMode: AuthMode.signUp)));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Full name'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Full name'), 'Rabi Yadav');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'rabi@example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'correct-horse');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(AuthStore.instance.account?.name, 'Rabi Yadav');
    });

    testWidgets('switching modes keeps what was already typed', (tester) async {
      await tester.pumpWidget(_wrap(const AuthScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'rabi@example.com');
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      // The name field appeared, and the email survived the switch.
      expect(find.widgetWithText(TextFormField, 'Full name'), findsOneWidget);
      expect(find.text('rabi@example.com'), findsOneWidget);
    });
  });
}
