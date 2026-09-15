import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/network/api_error.dart';
import 'package:gtradea_amazon/core/network/session_store.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/account/data/account_data_purge.dart';
import 'package:gtradea_amazon/features/account/presentation/accounts_sheet.dart';
import 'package:gtradea_amazon/features/auth/data/auth_repository.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/cart/data/cart_store.dart';
import 'package:gtradea_amazon/features/wishlist/data/wishlist_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/api.dart';
import 'support/fake_api.dart';

const _a = ('a', 'a@example.com', 'pw-for-a');
const _b = ('b', 'b@example.com', 'pw-for-b');

Map<String, dynamic> _user(String id, String email) => {
  'id': id,
  'email': email,
  'app_metadata': {'provider': 'email'},
  'user_metadata': <String, dynamic>{},
};

Map<String, dynamic> _tokens(String id, String email) => {
  'access_token': '$id-access',
  'refresh_token': '$id-refresh',
  'expires_in': 3600,
  'user': _user(id, email),
};

late FakeApi goTrue;
late FakeApi api;

/// Refused sessions, by user id: what GoTrue says once one is revoked.
final _revoked = <String>{};

/// Whose cart and list the gateway answers with: whoever is active when the
/// request is made, which is exactly the thing that must never mix.
String? get _active => AuthStore.instance.account?.id;

Future<void> _signIn((String, String, String) who) =>
    AuthStore.instance.signIn(email: who.$2, password: who.$3);

/// Lets the stores' own switches -- a disk read and a fetch each -- finish.
Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SessionStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    CartStore.instance.resetForTest();
    WishlistStore.instance.resetForTest();
    _revoked.clear();

    api = stubCatalog();
    api.onCall('GET', '/cart', (call) {
      if (_active == 'a') {
        return reply({
          'items': [
            {
              'id': 'c-a',
              'source_product_id': '111',
              'quantity': 1,
              'product_data': {'title': 'Only in A', 'price': 100},
            },
          ],
          'subtotal': 100,
        });
      }
      return reply(const {'items': [], 'subtotal': 0});
    });
    api.on('GET', '/wishlist', body: const {'items': []});
    api.on('POST', '/wishlist', body: const {'id': 'w-1'});

    goTrue = FakeApi();
    AuthStore.instance.repositoryForTest = AuthRepository(
      sessions: SessionStore.instance,
      dio: goTrue.dio(baseUrl: 'https://test.local/auth/v1'),
    );
    goTrue.onCall('POST', '/token', (call) {
      if (call.query['grant_type'] == 'password') {
        final email = call.json['email'];
        for (final who in [_a, _b]) {
          if (who.$2 == email && who.$3 == call.json['password']) {
            return reply(_tokens(who.$1, who.$2));
          }
        }
        return reply(const {'msg': 'Invalid login credentials'}, status: 400);
      }
      final token = call.json['refresh_token'] as String? ?? '';
      final id = token.split('-').first;
      if (_revoked.contains(id)) {
        return reply(const {'msg': 'Invalid Refresh Token'}, status: 400);
      }
      final who = id == 'a' ? _a : _b;
      return reply(_tokens(who.$1, who.$2));
    });
    goTrue.onCall('GET', '/user', (call) {
      for (final who in [_a, _b]) {
        if (call.authorization == 'Bearer ${who.$1}-access') {
          if (_revoked.contains(who.$1)) break;
          return reply(_user(who.$1, who.$2));
        }
      }
      return reply(const {'msg': 'invalid JWT'}, status: 401);
    });
    goTrue.on('POST', '/logout', status: 204);

    CartStore.instance.bindToAuth();
    WishlistStore.instance.bindToAuth();
  });

  tearDown(clearApiStub);

  group('accounts kept side by side', () {
    test('a second sign-in keeps the first, and no password is stored', () async {
      await _signIn(_a);
      await _signIn(_b);

      expect(AuthStore.instance.account?.id, 'b');
      await AuthStore.instance.refreshSavedAccounts();
      expect(
        AuthStore.instance.savedAccounts.map((s) => s.id),
        ['b', 'a'],
        reason: 'most recently used first',
      );

      // Sessions are token pairs in the keystore. The passwords never are.
      const storage = FlutterSecureStorage();
      final vault = await storage.read(key: 'gtradea-go-auth-accounts') ?? '';
      expect(vault, contains('a-refresh'));
      expect(vault, isNot(contains(_a.$3)));
      expect(vault, isNot(contains(_b.$3)));
    });

    test('a session stored before this feature joins the list', () async {
      FlutterSecureStorage.setMockInitialValues({
        'gtradea-go-auth-session':
            '{"access_token":"a-access","refresh_token":"a-refresh",'
            '"expires_at":9999999999,"user":{"id":"a","email":"a@example.com"}}',
      });
      SessionStore.instance.resetForTest();
      await AuthStore.instance.load();
      await AuthStore.instance.refreshSavedAccounts();

      expect(AuthStore.instance.account?.id, 'a');
      expect(AuthStore.instance.savedAccounts.single.id, 'a');
    });

    test('signing in to one already here says so, and adds nothing', () async {
      await _signIn(_a);
      AuthStore.instance.takeWasAlreadySaved();
      await _signIn(_a);

      expect(AuthStore.instance.takeWasAlreadySaved(), isTrue);
      await AuthStore.instance.refreshSavedAccounts();
      expect(AuthStore.instance.savedAccounts, hasLength(1));
    });

    test('a wrong password adds nothing and changes nothing', () async {
      await _signIn(_a);
      await expectLater(
        AuthStore.instance.signIn(email: _b.$2, password: 'wrong'),
        throwsA(isA<ApiError>()),
      );
      expect(AuthStore.instance.account?.id, 'a');
      await AuthStore.instance.refreshSavedAccounts();
      expect(AuthStore.instance.savedAccounts.map((s) => s.id), ['a']);
    });
  });

  group('switching', () {
    test('makes the other active, checked with the server, signing no one out', () async {
      await _signIn(_a);
      await _signIn(_b);
      goTrue.calls.clear();

      await AuthStore.instance.switchAccount('a');

      expect(AuthStore.instance.account?.id, 'a');
      expect(
        goTrue.calls.where((c) => c.path == '/user').single.authorization,
        'Bearer a-access',
      );
      expect(goTrue.calls.where((c) => c.path == '/logout'), isEmpty);
      expect((await SessionStore.instance.read())?.userId, 'a');
      expect(AuthStore.instance.savedAccounts.map((s) => s.id), ['a', 'b']);
    });

    test('a refused session is forgotten, and the current account stays', () async {
      await _signIn(_a);
      await _signIn(_b);
      _revoked.add('a');

      await expectLater(
        AuthStore.instance.switchAccount('a'),
        throwsA(isA<SavedSessionExpired>()),
      );
      expect(AuthStore.instance.account?.id, 'b');
      expect((await SessionStore.instance.read())?.userId, 'b');
      expect(AuthStore.instance.savedAccounts.map((s) => s.id), ['b']);
    });

    test('an unreachable server changes nothing', () async {
      await _signIn(_a);
      await _signIn(_b);
      goTrue.on('GET', '/user', status: 503, body: const {'msg': 'down'});

      await expectLater(
        AuthStore.instance.switchAccount('a'),
        throwsA(isA<ApiError>()),
      );
      expect(AuthStore.instance.account?.id, 'b');
      expect(AuthStore.instance.savedAccounts.map((s) => s.id), ['b', 'a']);
    });
  });

  group('signing out and removing', () {
    test('removing another account ends its session here, only here', () async {
      await _signIn(_a);
      await _signIn(_b);
      goTrue.calls.clear();

      final result = await AuthStore.instance.removeAccount('a');

      expect(result.revoked, isTrue);
      final logout = goTrue.calls.singleWhere((c) => c.path == '/logout');
      expect(logout.authorization, 'Bearer a-access');
      expect(logout.query, {'scope': 'local'});
      expect(AuthStore.instance.account?.id, 'b');
      expect(AuthStore.instance.savedAccounts.map((s) => s.id), ['b']);
    });

    test('signing out moves on to the next account on the device', () async {
      await _signIn(_a);
      await _signIn(_b);

      final result = await AuthStore.instance.signOut();

      expect(result.switchedTo?.id, 'a');
      expect(AuthStore.instance.account?.id, 'a');
      expect(AuthStore.instance.savedAccounts.map((s) => s.id), ['a']);
      expect(
        goTrue.calls.where((c) => c.path == '/logout').single.authorization,
        'Bearer b-access',
      );
    });

    test('the last account signs out to a signed-out app', () async {
      await _signIn(_a);
      final result = await AuthStore.instance.signOut();
      expect(result.switchedTo, isNull);
      expect(AuthStore.instance.isSignedIn, isFalse);
      expect(AuthStore.instance.savedAccounts, isEmpty);
    });

    test('removal clears what the device kept for that account only', () async {
      SharedPreferences.setMockInitialValues({
        CartStore.storageKeyFor(_a.$2): '[]',
        WishlistStore.storageKeyFor(_a.$2): '[]',
        CartStore.storageKeyFor(_b.$2): '[]',
      });
      await purgeAccountData(email: _a.$2, accountId: _a.$1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(CartStore.storageKeyFor(_a.$2)), isFalse);
      expect(prefs.containsKey(WishlistStore.storageKeyFor(_a.$2)), isFalse);
      expect(prefs.containsKey(CartStore.storageKeyFor(_b.$2)), isTrue);
    });
  });

  group('no account sees another one\'s data', () {
    test('the cart follows the active account, both ways', () async {
      await _signIn(_a);
      await CartStore.instance.load();
      await _settle();
      expect(CartStore.instance.lines.map((l) => l.title), ['Only in A']);

      await _signIn(_b);
      await _settle();
      expect(CartStore.instance.lines, isEmpty, reason: "B sees none of A's");

      await AuthStore.instance.switchAccount('a');
      await _settle();
      expect(CartStore.instance.lines.map((l) => l.title), ['Only in A']);
    });

    test('an answer for the last account that lands late is dropped', () async {
      await _signIn(_b);
      await CartStore.instance.load();
      await _settle();

      // A's cart is slow to arrive, and the shopper switches before it does.
      api.onCall('GET', '/cart', (call) {
        if (_active == 'a') {
          return FakeReply(
            status: 200,
            delay: const Duration(milliseconds: 150),
            body: const {
              'items': [
                {
                  'id': 'c-a',
                  'source_product_id': '111',
                  'quantity': 1,
                  'product_data': {'title': 'Only in A', 'price': 100},
                },
              ],
              'subtotal': 100,
            },
          );
        }
        return reply(const {'items': [], 'subtotal': 0});
      });
      await _signIn(_a);
      await AuthStore.instance.switchAccount('b');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _settle();

      expect(AuthStore.instance.account?.id, 'b');
      expect(
        CartStore.instance.lines,
        isEmpty,
        reason: "A's cart answered after the switch and must not show as B's",
      );
    });

    test("one account's saved list is never pushed into another's", () async {
      await _signIn(_a);
      await WishlistStore.instance.load();
      await _settle();
      WishlistStore.instance.toggle(
        const SavedProduct(id: 'p1', title: 'Saved by A', price: 10),
      );
      await _settle();

      await _signIn(_b);
      await _settle();
      final pushesBefore = api.calls
          .where((c) => c.method == 'POST' && c.path == '/wishlist')
          .length;
      expect(WishlistStore.instance.items, isEmpty);
      await WishlistStore.instance.sync();
      await _settle();
      expect(
        api.calls.where((c) => c.method == 'POST' && c.path == '/wishlist'),
        hasLength(pushesBefore),
        reason: "nothing of A's was sent while B was active",
      );

      await AuthStore.instance.switchAccount('a');
      await _settle();
      expect(WishlistStore.instance.contains('p1'), isTrue);
    });
  });

  group('the accounts sheet', () {
    Future<void> pumpSheet(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showAccountsSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists each account, marks the active one, and switches', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await _signIn(_a);
        await _signIn(_b);
        await AuthStore.instance.refreshSavedAccounts();
      });
      await pumpSheet(tester);

      expect(find.text(_a.$2), findsOneWidget);
      expect(find.text(_b.$2), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      // Nothing that could act as the account is on screen.
      expect(find.textContaining('access'), findsNothing);
      expect(find.textContaining('refresh'), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.text(_a.$2));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(AuthStore.instance.account?.id, 'a');
      expect(find.text('Switched to ${_a.$2}'), findsOneWidget);
    });

    testWidgets('removing asks first, and says the account is not deleted', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await _signIn(_a);
        await _signIn(_b);
        await AuthStore.instance.refreshSavedAccounts();
      });
      await pumpSheet(tester);

      await tester.tap(find.byTooltip('Options for ${_a.$2}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from this device'));
      await tester.pumpAndSettle();

      expect(find.text('Remove from this device?'), findsOneWidget);
      expect(
        find.textContaining('The account itself is not deleted'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(AuthStore.instance.savedAccounts, hasLength(2));
    });
  });
}
