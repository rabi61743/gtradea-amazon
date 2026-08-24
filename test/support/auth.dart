import 'package:gtradea_amazon/core/network/session_store.dart';
import 'package:gtradea_amazon/features/auth/data/auth_repository.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';

import 'api.dart';
import 'fake_api.dart';

/// Puts the app in a signed-in state without a server.
///
/// Sign-in is a network call now, so tests that merely need "someone is signed
/// in" -- the per-account scoping in the cart, orders, coupons and addresses --
/// set the account directly rather than standing up a fake GoTrue.
///
/// It also parks a stub repository on the store, so a later signOut() in the
/// same test cannot reach the real auth server.
void signInForTest({
  String email = 'rabi@example.com',
  String? name,
  String id = 'user-1',
}) {
  ensureApiStub();

  final api = FakeApi()..on('POST', '/logout', status: 204);
  AuthStore.instance.repositoryForTest = AuthRepository(
    sessions: SessionStore.instance,
    dio: api.dio(baseUrl: 'https://test.local/auth/v1'),
  );

  final parts = (name ?? '').trim().split(RegExp(r'\s+'));
  AuthStore.instance.adoptForTest(Account(
    id: id,
    email: email,
    firstName: parts.first.isEmpty ? null : parts.first,
    lastName: parts.length > 1 ? parts.sublist(1).join(' ') : null,
  ));
}
