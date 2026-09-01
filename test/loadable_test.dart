import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/async/loadable.dart';
import 'package:gtradea_amazon/core/network/api_error.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lets a test hold a fetch open and decide when it answers.
class Gate {
  final _completers = <Completer<List<String>>>[];
  int calls = 0;

  Future<List<String>> fetch() {
    calls++;
    final completer = Completer<List<String>>();
    _completers.add(completer);
    return completer.future;
  }

  void answer(List<String> value) => _completers.removeAt(0).complete(value);
  void fail() => _completers
      .removeAt(0)
      .completeError(const ApiError(statusCode: 500, message: 'nope'));
}

Loadable<List<String>> cached(Future<List<String>> Function() fetch) =>
    Loadable<List<String>>(
      fetch,
      cacheKey: 'thing',
      encode: (value) => value,
      decode: (json) => (json as List).cast<String>(),
    );

/// Lets the unawaited cache reads and writes finish.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('revalidate', () {
    test('with nothing to show, it is just a load', () async {
      final gate = Gate();
      final loadable = cached(gate.fetch);

      final pending = loadable.revalidate();
      expect(gate.calls, 1);
      // Deferring the first one would blank the screen for a turn, and
      // whatever the empty state says would flash before the spinner.
      expect(loadable.isLoading, isTrue);

      gate.answer(const ['a']);
      await pending;
      expect(loadable.value, const ['a']);
    });

    test(
      'with something to show, it returns at once and checks behind',
      () async {
        final gate = Gate();
        final loadable = cached(gate.fetch);

        unawaited(loadable.load());
        gate.answer(const ['first']);
        await settle();
        expect(loadable.value, const ['first']);

        await loadable.revalidate();
        // Returned without waiting on the network.
        expect(loadable.value, const ['first']);

        await settle();
        expect(gate.calls, 2, reason: 'the check did happen');
        gate.answer(const ['second']);
        await settle();
        expect(loadable.value, const ['second']);
      },
    );

    test(
      'does not notify its listeners while the caller is still running',
      () async {
        // This is the whole reason the second fetch is deferred: revalidate is
        // called from build, and notifying there asks every other widget on the
        // same store to rebuild mid-build, which is an assertion rather than a
        // warning.
        final gate = Gate();
        final loadable = cached(gate.fetch);

        unawaited(loadable.load());
        gate.answer(const ['first']);
        await settle();

        var notified = false;
        loadable.addListener(() => notified = true);

        loadable.revalidate();
        expect(notified, isFalse);

        await settle();
        expect(notified, isTrue);
      },
    );

    test('a check already in flight is not started twice', () async {
      final gate = Gate();
      final loadable = cached(gate.fetch);

      unawaited(loadable.revalidate());
      unawaited(loadable.revalidate());
      await settle();

      expect(gate.calls, 1);
    });

    test('a failed check keeps what is already on screen', () async {
      // A background revalidate that cannot reach the server must not replace
      // a good catalogue with an error.
      final gate = Gate();
      final loadable = cached(gate.fetch);

      unawaited(loadable.load());
      gate.answer(const ['first']);
      await settle();

      await loadable.revalidate();
      await settle();
      gate.fail();
      await settle();

      expect(loadable.value, const ['first']);
    });
  });

  group('invalidate', () {
    test('takes the disk copy with it', () async {
      // Clearing memory alone left the next load reading the departed
      // account's data straight back off disk, which is the one thing
      // invalidate exists to prevent.
      final gate = Gate();
      final loadable = cached(gate.fetch);

      unawaited(loadable.load());
      gate.answer(const ['secret']);
      await settle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cache_thing'), isNotNull);

      loadable.invalidate();
      await settle();

      expect(prefs.getString('cache_thing'), isNull);
      expect(loadable.value, isNull);
    });
  });
}
