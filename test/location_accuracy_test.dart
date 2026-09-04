import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gtradea_amazon/features/address/data/location_detector.dart';

/// A fix as the platform reports one.
Position _fix({
  required double accuracy,
  required Duration age,
  double latitude = 27.6644,
  double longitude = 85.3188,
  DateTime? now,
}) {
  final moment = (now ?? DateTime(2026, 9, 4, 12)).subtract(age);
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: moment,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  final now = DateTime(2026, 9, 4, 12);

  group('which fix is used', () {
    test('the tightest one, not the first one', () {
      // The bug this button had: the fused provider answers instantly with a
      // network estimate, and the satellite fix lands seconds later.
      final network = _fix(accuracy: 1400, age: Duration.zero, now: now);
      final gps = _fix(accuracy: 12, age: const Duration(seconds: 4), now: now);

      final best = LocationDetector.pickBestFix([network, gps], now: now);

      expect(best?.accuracy, 12);
    });

    test('a stale fix loses to a fresh one, however tight it is', () {
      // The last known position: recorded in another town, perfectly accurate,
      // and completely wrong for "where am I now".
      final stale = _fix(
        accuracy: 5,
        age: const Duration(hours: 3),
        latitude: 28.2096,
        longitude: 83.9856,
        now: now,
      );
      final fresh = _fix(accuracy: 60, age: Duration.zero, now: now);

      final best = LocationDetector.pickBestFix([stale, fresh], now: now);

      expect(best?.accuracy, 60);
      expect(best?.latitude, 27.6644);
    });

    test('but a stale fix beats nothing at all', () {
      final stale = _fix(accuracy: 25, age: const Duration(hours: 3), now: now);

      expect(LocationDetector.pickBestFix([stale], now: now), isNotNull);
    });

    test('an unknown accuracy loses to any real figure', () {
      // Zero means "not reported", not "perfect".
      final unknown = _fix(accuracy: 0, age: Duration.zero, now: now);
      final known = _fix(accuracy: 800, age: Duration.zero, now: now);

      expect(
        LocationDetector.pickBestFix([unknown, known], now: now)?.accuracy,
        800,
      );
    });

    test('and nothing in means nothing out', () {
      expect(LocationDetector.pickBestFix(const [], now: now), isNull);
    });
  });

  group('the accuracy it holds out for', () {
    test('is a real GPS lock, not a cell-tower guess', () {
      expect(LocationDetector.targetAccuracyMetres, lessThanOrEqualTo(50));
      expect(LocationDetector.targetAccuracyMetres, greaterThan(0));
    });

    test('and it waits for one, without holding the shopper forever', () {
      expect(
        LocationDetector.settleWindow,
        greaterThanOrEqualTo(const Duration(seconds: 4)),
      );
      expect(
        LocationDetector.settleWindow,
        lessThan(LocationDetector.fixTimeout),
      );
    });
  });

  group('the coordinates it hands on', () {
    test('are the device\'s own, never a stand-in', () {
      // The detector has a table of city centres for naming a town offline.
      // Those coordinates must never come back as the shopper's position: the
      // offline path returns a city with no street, and says it is not from a
      // geocoder.
      final result = LocationDetector.matchPosition(27.6800, 85.3300);

      expect(result, isA<DetectResolved>());
      final resolved = result as DetectResolved;
      expect(resolved.fromGeocoder, isFalse);
      expect(resolved.street, isNull);
      expect(resolved.addressLine, isNull);
    });

    test(
      'and somewhere unserved is said to be unserved, not rounded to a city',
      () {
        final result = LocationDetector.matchPosition(48.8566, 2.3522);

        expect(result, isA<DetectOutsideServedArea>());
      },
    );
  });
}
