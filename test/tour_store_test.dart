import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
// The steps themselves, for the version-replay rules below: which of them a
// shopper is offered is a fact about the list, not only about the store.
import 'package:gtradea_amazon/features/tour/data/tour_step.dart';
import 'package:gtradea_amazon/features/tour/data/tour_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/auth.dart';

/// What the app remembers about the guided tour.
///
/// The rules worth pinning are all about *not* showing it: not before the disk
/// has answered, not again after it was finished or skipped, and never one
/// shopper's record standing in for another's.

/// A stored record, as the store writes it.
String _record({
  int version = 1,
  String outcome = 'completed',
  int? at = 1700000000000,
}) => jsonEncode({'version': version, 'outcome': outcome, 'at': at});

/// Lets an async read off the preference store land.
///
/// Real delays rather than `pumpEventQueue`, which is what the other migration
/// suite uses -- the read is a platform-channel hop, and draining the
/// microtask queue does not wait for one.
Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TourStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    TourStore.enabled = true;
  });

  tearDown(() {
    TourStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
    TourStore.enabled = true;
  });

  group('a first install', () {
    test('has seen nothing, so the whole tour is unseen', () async {
      await TourStore.instance.load();

      expect(TourStore.instance.progress, isNull);
      expect(TourStore.instance.unseenFrom, 1);
      expect(TourStore.instance.shouldStart, isTrue);
    });

    test('nothing starts before the disk has answered', () {
      // The first frame of a cold start has no answer yet. Guessing "show"
      // for that moment is an overlay flashing over the storefront on every
      // single launch.
      expect(TourStore.instance.isLoaded, isFalse);
      expect(TourStore.instance.shouldStart, isFalse);
    });

    test('an unreadable store is treated as never seen', () async {
      await TourStore.instance.load();

      expect(TourStore.instance.shouldStart, isTrue);
    });
  });

  group('once it has been finished', () {
    test('completing it is written down, with when', () async {
      await TourStore.instance.load();
      final when = DateTime.fromMillisecondsSinceEpoch(1700000000000);

      await TourStore.instance.finish(TourOutcome.completed, at: when);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('gtradea_tour');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['version'], TourStore.currentVersion);
      expect(decoded['outcome'], 'completed');
      expect(decoded['at'], when.millisecondsSinceEpoch);
    });

    test('skipping is recorded as skipped, not as completed', () async {
      // The two are different facts. A later version may reasonably treat
      // somebody who skipped differently from somebody who watched it through.
      await TourStore.instance.load();

      await TourStore.instance.finish(TourOutcome.skipped);

      expect(TourStore.instance.progress!.outcome, TourOutcome.skipped);
      expect(TourStore.instance.progress!.isCompleted, isFalse);
    });

    test('it does not start again on the next launch', () async {
      await TourStore.instance.load();
      await TourStore.instance.finish(TourOutcome.completed);

      // A fresh launch: in-memory state gone, the store still there.
      TourStore.instance.resetForTest();
      await TourStore.instance.load();

      expect(TourStore.instance.shouldStart, isFalse);
      expect(TourStore.instance.progress!.isCompleted, isTrue);
    });

    test('nor after skipping it', () async {
      await TourStore.instance.load();
      await TourStore.instance.finish(TourOutcome.skipped);

      TourStore.instance.resetForTest();
      await TourStore.instance.load();

      expect(TourStore.instance.shouldStart, isFalse);
    });
  });

  group('a new version', () {
    test('asks only for the steps above what was seen', () async {
      // The bare key, which is what the preference mock actually stores --
      // `prefs.getKeys()` returns it unprefixed. Seeded under 'flutter.'
      // it is never read, and this test would pass as a first install
      // rather than proving anything about versions.
      SharedPreferences.setMockInitialValues({
        'gtradea_tour': _record(version: 1),
      });
      TourStore.instance.resetForTest();
      await TourStore.instance.load();

      expect(
        TourStore.instance.progress,
        isNotNull,
        reason: 'the seeded record was actually read',
      );

      // Version 1 is behind them; a version 2 release starts at its own steps
      // rather than replaying the welcome.
      expect(TourStore.instance.unseenFrom, 2);
    });

    test('and nothing is unseen while the current version is the seen one',
        () async {
      SharedPreferences.setMockInitialValues({
        'gtradea_tour': _record(version: TourStore.currentVersion),
      });
      TourStore.instance.resetForTest();
      await TourStore.instance.load();

      expect(TourStore.instance.progress, isNotNull, reason: 'record read');

      expect(TourStore.instance.unseenFrom, TourStore.currentVersion + 1);
      expect(TourStore.instance.shouldStart, isFalse);
    });
  });

  group('what a new version actually offers', () {
    test('somebody who finished version 1 is offered only what is new', () {
      // The point of versioning the steps, and the thing nothing asserted
      // until now: the store said "unseen from 2" correctly while no test
      // checked what that produced. A shopper who walked the original five
      // should get the step that joined afterwards, not the walkthrough again.
      final offered = stepsFrom(2);

      expect(offered, hasLength(1));
      expect(offered.single.anchor, TourAnchor.coins);
      expect(offered.single.version, 2);
    });

    test('a first install is offered the whole tour', () {
      final offered = stepsFrom(1);

      expect(offered.length, tourSteps.length);
      expect(
        offered.map((s) => s.anchor),
        containsAll([TourAnchor.search, TourAnchor.coins, TourAnchor.orders]),
      );
    });

    test('no step claims a version the store has not reached', () {
      // A step numbered above currentVersion would never be shown to anybody,
      // which is a step that exists and does nothing.
      for (final step in tourSteps) {
        expect(
          step.version,
          lessThanOrEqualTo(TourStore.currentVersion),
          reason: '"${step.title}" is numbered past the current tour',
        );
      }
    });

    test('and the current version is offered to somebody at it', () {
      // The boundary the replay rule turns on.
      expect(stepsFrom(TourStore.currentVersion), isNotEmpty);
      expect(stepsFrom(TourStore.currentVersion + 1), isEmpty);
    });
  });

  group('two shoppers on one device', () {
    test('a guest run carries into the account they sign into', () async {
      // Bound before the identity changes, as the app does it in
      // HomeScreen.initState and as the other migration suite does. Bound
      // afterwards the listener misses the change it exists to hear.
      TourStore.instance.bindToAuth();

      // The guest finished it.
      await TourStore.instance.load();
      await TourStore.instance.finish(TourOutcome.completed);

      signInForTest(id: 'user-b');
      await _settle();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('gtradea_tour_user-b'),
        isNotNull,
        reason: 'what the guest saw on this device is now the account\'s',
      );
      // And so it does not open again for them.
      expect(TourStore.instance.shouldStart, isFalse);
    });

    test('an account with its own record is not given the guest\'s', () async {
      // The one that matters for "do not show another user's state": this
      // account has never seen the tour, and the guest's completed run must
      // not silence their first run.
      SharedPreferences.setMockInitialValues({
        'gtradea_tour': _record(version: TourStore.currentVersion),
        'gtradea_tour_user-d': jsonEncode({
          'version': 0,
          'outcome': 'skipped',
          'at': null,
        }),
      });
      TourStore.instance.resetForTest();
      TourStore.instance.bindToAuth();
      await TourStore.instance.load();

      signInForTest(id: 'user-d');
      await _settle();

      // Their own record, which is version 0 -- so the current version is
      // still ahead of them and the tour is theirs to see.
      expect(TourStore.instance.progress?.version, 0);
      expect(TourStore.instance.unseenFrom, 1);
      expect(TourStore.instance.shouldStart, isTrue);
    });

    test('the key is per account', () {
      expect(TourStore.storageKeyFor(null), 'gtradea_tour');
      expect(TourStore.storageKeyFor(''), 'gtradea_tour');
      expect(TourStore.storageKeyFor('user-a'), 'gtradea_tour_user-a');
    });

    test('a switch clears what was held until the new record is read', () {
      // The moment of the switch: the last account's progress must not stand
      // in for this one's, even for the length of a disk read.
      TourStore.instance.bindToAuth();
      signInForTest(id: 'user-c');

      expect(TourStore.instance.isLoaded, isFalse);
      expect(TourStore.instance.shouldStart, isFalse);
    });
  });

  group('the test seam', () {
    test('switched off, it never asks to start', () async {
      // Every widget test seeds an empty SharedPreferences, which is a first
      // install. Without this the tour opens over suites that measure the
      // widgets it covers.
      TourStore.enabled = false;
      await TourStore.instance.load();

      expect(TourStore.instance.shouldStart, isFalse);
    });
  });
}
