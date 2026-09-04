import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:gtradea_amazon/features/home/widgets/search_header.dart';
import 'package:gtradea_amazon/features/profile/data/profile_store.dart';

import 'support/api.dart';
import 'support/auth.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthStore.instance.resetForTest();
    ProfileStore.instance.resetForTest();
    ensureApiStub();
  });

  tearDown(clearApiStub);

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SearchHeader())),
    );
    await tester.pump();
  }

  group('the greeting', () {
    testWidgets('names the signed-in account', (tester) async {
      signInForTest(name: 'Pravakar Yadav');

      await pump(tester);

      // Two lines now: the greeting leads, the name follows it smaller.
      expect(find.text('Hi,'), findsOneWidget);
      expect(find.text('Pravakar'), findsOneWidget);
    });

    testWidgets('the name is smaller than the greeting', (tester) async {
      signInForTest(name: 'Pravakar Yadav');

      await pump(tester);

      final hi = tester.widget<Text>(find.text('Hi,')).style!.fontSize!;
      final name = tester.widget<Text>(find.text('Pravakar')).style!.fontSize!;
      expect(name, lessThan(hi));
    });

    testWidgets('uses the first name only', (tester) async {
      // A greeting uses a first name, and the header shares one row with the
      // search pill.
      signInForTest(name: 'Pravakar Yadav');

      await pump(tester);

      expect(find.text('Pravakar Yadav'), findsNothing);
    });

    testWidgets('falls back to the email when no name is set', (tester) async {
      // What Account.displayName already does: the part before the @ reads
      // better in a heading than the whole address.
      signInForTest(email: 'pravakar@example.com');

      await pump(tester);

      expect(find.text('pravakar'), findsOneWidget);
    });

    testWidgets('is not there at all when signed out', (tester) async {
      // There is no name to use, and "Hi, Guest" is a greeting to nobody.
      await pump(tester);

      expect(find.text('Hi,'), findsNothing);
    });

    testWidgets('and it is only the greeting -- no second line', (
      tester,
    ) async {
      signInForTest(name: 'Pravakar Yadav');

      await pump(tester);

      expect(find.textContaining('Welcome'), findsNothing);
    });
  });

  group('it does not crowd the search pill', () {
    testWidgets('the pill still reaches the right margin', (tester) async {
      signInForTest(name: 'Pravakar Yadav');

      await pump(tester);

      final pill = tester.getRect(find.byKey(SearchHeader.pillKey));
      final header = tester.getRect(find.byType(SearchHeader));
      expect(pill.right, closeTo(header.right - 16, 0.5));
    });

    testWidgets('and the greeting sits to its left', (tester) async {
      signInForTest(name: 'Pravakar Yadav');

      await pump(tester);

      final greeting = tester.getRect(find.text('Hi,'));
      final pill = tester.getRect(find.byKey(SearchHeader.pillKey));
      expect(greeting.right, lessThanOrEqualTo(pill.left));
    });

    testWidgets('signed out, the pill has the full width', (tester) async {
      await pump(tester);

      final pill = tester.getRect(find.byKey(SearchHeader.pillKey));
      final header = tester.getRect(find.byType(SearchHeader));
      expect(pill.left, closeTo(header.left + 16, 0.5));
    });
  });
}
