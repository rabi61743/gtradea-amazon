import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/catalog.dart';

import 'package:gtradea_amazon/core/network/api_error.dart';
import 'package:gtradea_amazon/core/network/session_store.dart';
import 'package:gtradea_amazon/features/auth/data/auth_repository.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/account/presentation/account_screen.dart';
import 'package:gtradea_amazon/features/account/data/recently_viewed_store.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';

import 'support/auth.dart';
import 'support/fake_api.dart';

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
    FlutterSecureStorage.setMockInitialValues({});
    SessionStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    WishlistStore.instance.resetForTest();
    RecentlyViewedStore.instance.resetForTest();
  });

  group('AuthStore', () {
    /// Two hours out, so a restored session is not treated as expired.
    Map<String, dynamic> sessionBody({
      String access = 'access-1',
      String refresh = 'refresh-1',
      Map<String, dynamic>? user,
    }) => {
      'access_token': access,
      'refresh_token': refresh,
      'expires_in': 7200,
      'user':
          user ??
          {
            'id': 'user-1',
            'email': 'rabi@example.com',
            'user_metadata': {'first_name': 'Rabi', 'last_name': 'Yadav'},
          },
    };

    AuthRepository repoOver(FakeApi api) => AuthRepository(
      sessions: SessionStore.instance,
      dio: api.dio(baseUrl: 'https://test.local/auth/v1'),
    );

    test(
      'signing in sends the password grant and adopts the session',
      () async {
        final api = FakeApi()..on('POST', '/token', body: sessionBody());
        AuthStore.instance.repositoryForTest = repoOver(api);

        await AuthStore.instance.signIn(
          email: '  rabi@example.com ',
          password: 'correct-horse',
        );

        expect(api.calls.single.query['grant_type'], 'password');
        // Trimmed: a keyboard's trailing space is not part of the address, and
        // the server would reject it as a different one.
        expect(api.calls.single.json['email'], 'rabi@example.com');
        expect(AuthStore.instance.isSignedIn, isTrue);
        expect(AuthStore.instance.account?.email, 'rabi@example.com');
        expect(AuthStore.instance.account?.id, 'user-1');
      },
    );

    test(
      'a refused sign-in keeps the server wording and stays signed out',
      () async {
        final api = FakeApi()
          ..on(
            'POST',
            '/token',
            status: 400,
            body: {'error': 'Invalid login credentials'},
          );
        AuthStore.instance.repositoryForTest = repoOver(api);

        await expectLater(
          AuthStore.instance.signIn(email: 'a@b.com', password: 'wrong-guess'),
          throwsA(
            isA<ApiError>().having(
              (e) => e.message,
              'message',
              'Invalid login credentials',
            ),
          ),
        );
        expect(AuthStore.instance.isSignedIn, isFalse);
      },
    );

    test('a sign-up needing confirmation does not sign anyone in', () async {
      // GoTrue answers a created-but-unconfirmed account with a user and no
      // tokens. Treating that as a failure would be wrong -- the account
      // exists -- and treating it as a session would be worse.
      final api = FakeApi()
        ..on('POST', '/signup', body: {'id': 'user-9', 'email': 'a@b.com'});
      AuthStore.instance.repositoryForTest = repoOver(api);

      final needsConfirmation = await AuthStore.instance.signUp(
        email: 'a@b.com',
        password: 'correct-horse',
        firstName: 'Rabi',
      );

      expect(needsConfirmation, isTrue);
      expect(AuthStore.instance.isSignedIn, isFalse);
      expect(api.calls.single.json['data'], {'first_name': 'Rabi'});
    });

    test('a sign-up that returns tokens signs in immediately', () async {
      final api = FakeApi()..on('POST', '/signup', body: sessionBody());
      AuthStore.instance.repositoryForTest = repoOver(api);

      expect(
        await AuthStore.instance.signUp(
          email: 'rabi@example.com',
          password: 'correct-horse',
        ),
        isFalse,
      );
      expect(AuthStore.instance.isSignedIn, isTrue);
    });

    test('the session survives a restart', () async {
      final api = FakeApi()..on('POST', '/token', body: sessionBody());
      AuthStore.instance.repositoryForTest = repoOver(api);
      await AuthStore.instance.signIn(
        email: 'rabi@example.com',
        password: 'correct-horse',
      );

      // What a cold start actually does: nothing in memory, everything read
      // back from the keystore.
      AuthStore.instance.resetForTest();
      SessionStore.instance.resetForTest();
      await AuthStore.instance.load();

      expect(AuthStore.instance.isSignedIn, isTrue);
      expect(AuthStore.instance.account?.displayName, 'Rabi Yadav');
    });

    test('signing out clears the keystore, not just the screen', () async {
      final api = FakeApi()
        ..on('POST', '/token', body: sessionBody())
        ..on('POST', '/logout', status: 204);
      AuthStore.instance.repositoryForTest = repoOver(api);
      await AuthStore.instance.signIn(
        email: 'rabi@example.com',
        password: 'correct-horse',
      );

      await AuthStore.instance.signOut();

      expect(AuthStore.instance.isSignedIn, isFalse);
      expect(api.calls.map((c) => c.path), contains('/logout'));
      SessionStore.instance.resetForTest();
      expect(await SessionStore.instance.read(), isNull);
    });

    test('a failed logout call still signs the shopper out', () async {
      // Otherwise a dropped connection traps them in an account they asked to
      // leave -- and the local tokens are what actually matter.
      final api = FakeApi()
        ..on('POST', '/token', body: sessionBody())
        ..on('POST', '/logout', status: 500, body: {'error': 'nope'});
      AuthStore.instance.repositoryForTest = repoOver(api);
      await AuthStore.instance.signIn(
        email: 'rabi@example.com',
        password: 'correct-horse',
      );

      await AuthStore.instance.signOut();
      expect(AuthStore.instance.isSignedIn, isFalse);
    });

    test('a dead refresh token signs the app out instead of wedging it', () async {
      final api = FakeApi()..on('POST', '/token', body: sessionBody());
      AuthStore.instance.repositoryForTest = repoOver(api);
      await AuthStore.instance.signIn(
        email: 'rabi@example.com',
        password: 'correct-horse',
      );
      expect(AuthStore.instance.isSignedIn, isTrue);

      // What the interceptor does when GoTrue refuses the refresh. Without the
      // broadcast the app keeps believing it is signed in and every screen 401s
      // forever.
      await SessionStore.instance.clear(notify: true);
      await Future<void>.delayed(Duration.zero);

      expect(AuthStore.instance.isSignedIn, isFalse);
      expect(AuthStore.instance.sessionExpired, isTrue);
    });

    test('a corrupt stored session degrades to signed out', () async {
      FlutterSecureStorage.setMockInitialValues({
        'gtradea-go-auth-session': 'not json',
      });
      SessionStore.instance.resetForTest();
      AuthStore.instance.resetForTest();

      await AuthStore.instance.load();
      expect(AuthStore.instance.isSignedIn, isFalse);
    });

    test('a stored session with no user is not an identity', () async {
      // Every user-scoped call keys on the id. A token with no user attached
      // cannot address anything, so it is not a signed-in state.
      FlutterSecureStorage.setMockInitialValues({
        'gtradea-go-auth-session':
            '{"access_token":"a","refresh_token":"b","expires_at":9999999999}',
      });
      SessionStore.instance.resetForTest();
      AuthStore.instance.resetForTest();

      await AuthStore.instance.load();
      expect(AuthStore.instance.isSignedIn, isFalse);
    });

    test('an expiry in the past is expired, a missing one is not', () {
      final past = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;
      expect(
        AuthSession(
          accessToken: 'a',
          refreshToken: 'b',
          expiresAt: past,
        ).isExpired,
        isTrue,
      );
      // No expiry means the server did not say, and guessing "expired" would
      // throw away a working session on every single request.
      expect(
        const AuthSession(accessToken: 'a', refreshToken: 'b').isExpired,
        isFalse,
      );
    });

    test('expires_in arrives as a string from the OAuth fragment', () {
      // A URL fragment has no numbers in it. A cast would throw and lose a
      // sign-in that had already succeeded.
      final session = AuthSession.fromJson({
        'access_token': 'a',
        'refresh_token': 'b',
        'expires_in': '3600',
      });
      expect(session.expiresAt, isNotNull);
      expect(session.isExpired, isFalse);
    });

    test('notifies listeners so the UI can react', () {
      var notifications = 0;
      void listener() => notifications++;
      AuthStore.instance.addListener(listener);
      addTearDown(() => AuthStore.instance.removeListener(listener));

      signInForTest(email: 'a@b.com');
      AuthStore.instance.signOut();
      expect(notifications, 2);
    });

    group('displayName', () {
      test('prefers the name the shopper gave', () {
        expect(
          const Account(
            id: 'u',
            email: 'rabi@example.com',
            firstName: 'Rabi',
            lastName: 'Yadav',
          ).displayName,
          'Rabi Yadav',
        );
      });

      test('falls back to the local part of the email', () {
        expect(
          const Account(id: 'u', email: 'rabi@example.com').displayName,
          'rabi',
        );
      });

      test('a blank name is not a name', () {
        expect(
          Account.fromUser({
            'id': 'u',
            'email': 'rabi@example.com',
            'user_metadata': {'first_name': '   '},
          })?.displayName,
          'rabi',
        );
      });
    });
  });

  group('bottom nav', () {
    testWidgets('reads "Sign in" when signed out', (tester) async {
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Account'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('flips to "Account" the moment the store changes', (
      tester,
    ) async {
      // The dynamic requirement: no navigation, no rebuild trigger other than
      // the store itself.
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);

      signInForTest(email: 'rabi@example.com', name: 'Rabi');
      await tester.pump();

      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);

      // And back again.
      AuthStore.instance.signOut();
      await tester.pump();
      expect(find.text('Sign in'), findsOneWidget);

      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('opens the account page without stealing the nav selection', (
      tester,
    ) async {
      await tester.pumpWidget(const GtradeaAmazonApp());
      await tester.pumpAndSettle();

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

    testWidgets('a guest tapping Orders is asked to sign in, not fobbed off', (
      tester,
    ) async {
      _useTallWindow(tester);
      await tester.pumpWidget(_wrap(const AccountScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();

      // A guest has no orders, so the tile leads somewhere useful rather than
      // promising a page that could never have anything in it for them.
      expect(find.byType(AuthScreen), findsOneWidget);
    });

    testWidgets('settings and information are grouped under headings', (
      tester,
    ) async {
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
      signInForTest(email: 'rabi@example.com', name: 'Rabi Yadav');
      await tester.pumpWidget(_wrap(const AccountScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Hello, Rabi Yadav'), findsOneWidget);
      expect(find.text('rabi@example.com'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Sign In / Sign Up'), findsNothing);
      expect(find.text('Welcome to GtradeA'), findsNothing);
    });

    testWidgets('signing out asks first, and backing out keeps the session', (
      tester,
    ) async {
      _useTallWindow(tester);
      signInForTest(email: 'rabi@example.com', name: 'Rabi');
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
      signInForTest(email: 'rabi@example.com', name: 'Rabi');
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
    const dress = SavedProduct(
      id: 'dress',
      title: 'Suspender dress',
      price: 1808,
    );

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
      expect(
        RecentlyViewedStore.instance.items.single.title,
        'Ice silk jacket',
      );
    });

    testWidgets('the rail is absent until something has been viewed', (
      tester,
    ) async {
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
      await tester.pumpWidget(
        _wrap(
          ProductDetailScreen(product: sampleProduct, detail: sampleDetail),
        ),
      );
      // Pumped rather than settled: the gallery rotates its photographs on a
      // timer now, so this page never comes to rest and pumpAndSettle would
      // wait out its ten minutes.
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        RecentlyViewedStore.instance.items.single.title,
        'Phosphorus Paper for Matches, Large Sheets, Wholesale',
      );
    });
  });

  group('AuthScreen', () {
    testWidgets('rejects a malformed email and a short password', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const AuthScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'not-an-email',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'short',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(AuthStore.instance.isSignedIn, isFalse);
    });

    /// The screen is the only place a password is typed, so these drive it the
    /// way a shopper does and check what actually left the device.
    FakeApi wireGoTrue({int status = 200, Object? body}) {
      final api = FakeApi()
        ..on(
          'POST',
          '/token',
          status: status,
          body:
              body ??
              {
                'access_token': 'access-1',
                'refresh_token': 'refresh-1',
                'expires_in': 7200,
                'user': {'id': 'user-1', 'email': 'rabi@example.com'},
              },
        )
        ..on(
          'POST',
          '/signup',
          status: status,
          body:
              body ??
              {
                'access_token': 'access-1',
                'refresh_token': 'refresh-1',
                'expires_in': 7200,
                'user': {
                  'id': 'user-1',
                  'email': 'rabi@example.com',
                  'user_metadata': {'first_name': 'Rabi', 'last_name': 'Yadav'},
                },
              },
        );
      AuthStore.instance.repositoryForTest = AuthRepository(
        sessions: SessionStore.instance,
        dio: api.dio(baseUrl: 'https://test.local/auth/v1'),
      );
      return api;
    }

    testWidgets('a valid sign-in sends the password and updates the store', (
      tester,
    ) async {
      final api = wireGoTrue();
      await tester.pumpWidget(_wrap(const AuthScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'rabi@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'correct-horse',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(api.calls.single.json['password'], 'correct-horse');
      expect(AuthStore.instance.isSignedIn, isTrue);
      expect(AuthStore.instance.account?.email, 'rabi@example.com');
    });

    testWidgets('a refusal is shown on the screen, not swallowed', (
      tester,
    ) async {
      wireGoTrue(status: 400, body: {'error': 'Invalid login credentials'});
      await tester.pumpWidget(_wrap(const AuthScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'rabi@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'wrong-guess-here',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      // Rephrased, because GoTrue's own wording does not tell a shopper which
      // of the two things to change.
      expect(
        find.text('That email and password do not match an account.'),
        findsOneWidget,
      );
      expect(AuthStore.instance.isSignedIn, isFalse);
    });

    testWidgets('sign-up splits the name into what the server stores', (
      tester,
    ) async {
      final api = wireGoTrue();
      await tester.pumpWidget(
        _wrap(const AuthScreen(initialMode: AuthMode.signUp)),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Full name'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full name'),
        'Rabi Yadav',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'rabi@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'correct-horse',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(api.calls.single.json['data'], {
        'first_name': 'Rabi',
        'last_name': 'Yadav',
      });
      expect(AuthStore.instance.account?.displayName, 'Rabi Yadav');
    });

    testWidgets('a sign-up that needs confirming says so instead of leaving', (
      tester,
    ) async {
      // The account was created. Popping back to a signed-out account page
      // would read as a failure, which is the opposite of what happened.
      wireGoTrue(body: {'id': 'user-9', 'email': 'rabi@example.com'});
      await tester.pumpWidget(
        _wrap(const AuthScreen(initialMode: AuthMode.signUp)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full name'),
        'Rabi',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'rabi@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'correct-horse',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Check rabi@example.com'), findsOneWidget);
      expect(AuthStore.instance.isSignedIn, isFalse);
      // Switched to sign-in, so the next step is the obvious one.
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    });

    testWidgets('switching modes keeps what was already typed', (tester) async {
      await tester.pumpWidget(_wrap(const AuthScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'rabi@example.com',
      );
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      // The name field appeared, and the email survived the switch.
      expect(find.widgetWithText(TextFormField, 'Full name'), findsOneWidget);
      expect(find.text('rabi@example.com'), findsOneWidget);
    });
  });
}
