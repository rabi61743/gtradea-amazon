import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/address/data/address_store.dart';
import 'package:gtradea_amazon/features/address/data/location_detector.dart';
import 'package:gtradea_amazon/features/address/presentation/address_picker_sheet.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void _useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// Stands in for the device, so every branch can be driven without one.
///
/// Takes a queue of results: the first attempt gets the first, a retry gets the
/// next. That is what makes "turn location on and it picks up by itself"
/// testable at all.
class _FakeDetector extends LocationDetector {
  _FakeDetector(this._results, {this.gate});

  final List<DetectResult> _results;

  /// Held open to keep a detection in flight, so the loading state can be
  /// observed. Without it the fake resolves in the same turn it was called and
  /// there is nothing to see.
  final Completer<void>? gate;

  int attempts = 0;
  int locationSettingsOpened = 0;
  int appSettingsOpened = 0;

  @override
  Future<DetectResult> detect() async {
    final result = _results[attempts.clamp(0, _results.length - 1)];
    attempts++;
    if (gate != null) await gate!.future;
    return result;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsOpened++;
    return true;
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpened++;
    return true;
  }
}

_FakeDetector _useDetector(List<DetectResult> results, {Completer<void>? gate}) {
  final fake = _FakeDetector(results, gate: gate);
  LocationDetector.instance = fake;
  addTearDown(() => LocationDetector.instance = const LocationDetector());
  return fake;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AddressStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
  });

  group('matching a position to a city', () {
    test('a fix in a served city resolves to it', () {
      // Thamel, central Kathmandu.
      final result = LocationDetector.matchPosition(27.7154, 85.3123);
      expect(result, isA<DetectResolved>());

      final resolved = result as DetectResolved;
      expect(resolved.city, 'Kathmandu');
      expect(resolved.province, 'Bagmati');
      expect(resolved.distanceKm, lessThan(5));
      expect(resolved.fromGeocoder, isFalse,
          reason: 'the offline table is the fallback, not a geocoder');
      expect(resolved.isApproximate, isFalse);
    });

    test('neighbouring cities are told apart', () {
      expect(
        (LocationDetector.matchPosition(27.6644, 85.3188) as DetectResolved)
            .city,
        'Lalitpur',
      );
      expect(
        (LocationDetector.matchPosition(27.6710, 85.4298) as DetectResolved)
            .city,
        'Bhaktapur',
      );
    });

    test('a fix well outside a city is flagged as approximate', () {
      final resolved =
          LocationDetector.matchPosition(28.21, 83.58) as DetectResolved;
      expect(resolved.city, 'Pokhara');
      expect(resolved.isApproximate, isTrue,
          reason: 'the wording should hedge rather than state');
    });

    test('a geocoded result is never approximate', () {
      // A real street address is an address, not a nearest-town guess, however
      // far the city centre happens to be.
      const resolved = DetectResolved(
        city: 'Pokhara',
        province: 'Gandaki',
        street: 'Lakeside Road',
        distanceKm: 40,
        fromGeocoder: true,
      );
      expect(resolved.isApproximate, isFalse);
    });

    test('somewhere this shop does not deliver is refused, not guessed', () {
      final result = LocationDetector.matchPosition(51.5072, -0.1276);
      expect(result, isA<DetectOutsideServedArea>());
      expect((result as DetectOutsideServedArea).distanceKm,
          greaterThan(kMaxMatchKm));
    });

    test('every served city resolves to itself', () {
      for (final city in kServedCities) {
        final resolved =
            LocationDetector.matchPosition(city.latitude, city.longitude);
        expect(resolved, isA<DetectResolved>(), reason: city.city);
        expect((resolved as DetectResolved).city, city.city, reason: city.city);
      }
    });

    test('distance is a real great-circle distance', () {
      final km =
          LocationDetector.distanceKm(27.7172, 85.3240, 28.2096, 83.9856);
      expect(km, greaterThan(120));
      expect(km, lessThan(160));
      expect(LocationDetector.distanceKm(27.7, 85.3, 27.7, 85.3), 0);
    });
  });

  group('the address line handed to the form', () {
    test('joins street and area when the geocoder gave both', () {
      const resolved = DetectResolved(
        city: 'Kathmandu',
        province: 'Bagmati',
        street: 'Tridevi Marg 12',
        area: 'Thamel',
        postalCode: '44600',
        distanceKm: 0,
        fromGeocoder: true,
      );
      expect(resolved.addressLine, 'Tridevi Marg 12, Thamel');
    });

    test('strips what already has its own field', () {
      // A real Android result from Lalitpur. Repeating the city, postcode and
      // country under "tole, street and house number" makes the form look
      // broken and leaves the shopper tidying up after it.
      const resolved = DetectResolved(
        city: 'Lalitpur',
        province: 'Bagmati',
        street: 'M8G5+6V8, 3 Bakhundole, Lalitpur 44600, Nepal',
        area: 'Jawalakhel',
        postalCode: '44600',
        distanceKm: 0,
        fromGeocoder: true,
      );

      expect(resolved.addressLine, '3 Bakhundole, Jawalakhel');
    });

    test('does not repeat a part that appears in both street and area', () {
      const resolved = DetectResolved(
        city: 'Kathmandu',
        province: 'Bagmati',
        street: 'Tridevi Marg, Thamel',
        area: 'Thamel',
        distanceKm: 0,
        fromGeocoder: true,
      );
      expect(resolved.addressLine, 'Tridevi Marg, Thamel');
    });

    test('a line that was only ever noise comes back null', () {
      const resolved = DetectResolved(
        city: 'Lalitpur',
        province: 'Bagmati',
        street: 'M8G5+6V8, Lalitpur, Nepal',
        postalCode: '44600',
        distanceKm: 0,
        fromGeocoder: true,
      );
      // Better an empty field the shopper fills than one full of things they
      // have to delete.
      expect(resolved.addressLine, isNull);
    });

    test('is null when the geocoder named neither', () {
      const resolved = DetectResolved(
        city: 'Kathmandu',
        province: 'Bagmati',
        distanceKm: 2,
        fromGeocoder: false,
      );
      // Nothing to prefill, so the street field stays empty and the shopper
      // writes it rather than being handed something that looks filled.
      expect(resolved.addressLine, isNull);
    });
  });

  group('using it from the picker', () {
    Future<void> pumpPicker(WidgetTester tester) async {
      _useTallWindow(tester);
      // Inside a Scaffold, as it is in the app.
      await tester.pumpWidget(_wrap(
        const Scaffold(body: AddressPickerSheet()),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> tapDetect(WidgetTester tester) async {
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
    }

    testWidgets('the row promises what it can actually fill', (tester) async {
      _useDetector([
        const DetectResolved(
          city: 'Kathmandu',
          province: 'Bagmati',
          distanceKm: 1,
          fromGeocoder: true,
        ),
      ]);
      await pumpPicker(tester);

      expect(find.text('Use my current location'), findsOneWidget);
      expect(
        find.text('Fills in what we can, you check the rest'),
        findsOneWidget,
      );
    });

    testWidgets('a geocoded result prefills street, city and postal code',
        (tester) async {
      _useDetector([
        const DetectResolved(
          city: 'Pokhara',
          province: 'Gandaki',
          street: 'Lakeside Road 21',
          area: 'Baidam',
          postalCode: '33700',
          distanceKm: 0,
          fromGeocoder: true,
        ),
      ]);
      await pumpPicker(tester);
      await tapDetect(tester);

      expect(find.text('New address'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Pokhara'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Lakeside Road 21, Baidam'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, '33700'), findsOneWidget);
    });

    testWidgets('the shopper can still change what was filled in',
        (tester) async {
      _useDetector([
        const DetectResolved(
          city: 'Pokhara',
          province: 'Gandaki',
          street: 'Lakeside Road 21',
          distanceKm: 0,
          fromGeocoder: true,
        ),
      ]);
      await pumpPicker(tester);
      await tapDetect(tester);

      // Detection is a starting point, never a verdict.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Pokhara'),
        'Kathmandu',
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Kathmandu'), findsOneWidget);
    });

    testWidgets('location switched off offers to open location settings',
        (tester) async {
      final fake = _useDetector([const DetectServiceDisabled()]);
      await pumpPicker(tester);
      await tapDetect(tester);

      expect(
        find.textContaining('switched off on this device'),
        findsOneWidget,
      );
      expect(find.text('Enable location'), findsOneWidget);

      await tester.tap(find.text('Enable location'));
      await tester.pumpAndSettle();
      expect(fake.locationSettingsOpened, 1);
      expect(fake.appSettingsOpened, 0,
          reason: 'the service is off, not the permission');
    });

    testWidgets('coming back from settings retries by itself', (tester) async {
      final fake = _useDetector([
        const DetectServiceDisabled(),
        const DetectResolved(
          city: 'Lalitpur',
          province: 'Bagmati',
          distanceKm: 1,
          fromGeocoder: true,
        ),
      ]);
      await pumpPicker(tester);
      await tapDetect(tester);
      expect(find.text('Enable location'), findsOneWidget);

      await tester.tap(find.text('Enable location'));
      await tester.pumpAndSettle();

      // The shopper turns location on and comes back. Making them hunt for the
      // button again would waste the trip.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(fake.attempts, 2, reason: 'it tried again on its own');
      expect(find.text('New address'), findsOneWidget);
      expect(find.text('Enable location'), findsNothing);
    });

    testWidgets('a resume that was not a settings trip does not retry',
        (tester) async {
      final fake = _useDetector([const DetectTimeout()]);
      await pumpPicker(tester);
      await tapDetect(tester);
      expect(fake.attempts, 1);

      // Any old resume -- a phone call, a notification -- must not quietly
      // start asking for location again.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(fake.attempts, 1);
    });

    testWidgets('a permanent refusal points at app settings', (tester) async {
      final fake = _useDetector([
        const DetectPermissionDenied(permanently: true),
      ]);
      await pumpPicker(tester);
      await tapDetect(tester);

      expect(find.textContaining('blocked for this app'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(fake.appSettingsOpened, 1);
      expect(fake.locationSettingsOpened, 0,
          reason: 'the permission is blocked, not the service');
    });

    testWidgets('a one-off refusal offers to ask again', (tester) async {
      final fake = _useDetector([
        const DetectPermissionDenied(permanently: false),
        const DetectResolved(
          city: 'Kathmandu',
          province: 'Bagmati',
          distanceKm: 1,
          fromGeocoder: true,
        ),
      ]);
      await pumpPicker(tester);
      await tapDetect(tester);

      expect(find.textContaining('need permission'), findsOneWidget);
      // Not a trip to settings: the OS will still show a prompt.
      expect(find.text('Allow location'), findsOneWidget);
      expect(find.text('Open settings'), findsNothing);

      await tester.tap(find.text('Allow location'));
      await tester.pumpAndSettle();
      expect(fake.attempts, 2);
    });

    testWidgets('a timeout suggests what actually helps', (tester) async {
      _useDetector([const DetectTimeout()]);
      await pumpPicker(tester);
      await tapDetect(tester);

      expect(find.textContaining('took too long'), findsOneWidget);
      expect(find.text('Try again'), findsWidgets);
    });

    testWidgets('an unavailable position offers typing instead',
        (tester) async {
      _useDetector([const DetectUnavailable()]);
      await pumpPicker(tester);
      await tapDetect(tester);

      expect(
        find.textContaining('could not work out where it is'),
        findsOneWidget,
      );
    });

    testWidgets('being outside the served area names the nearest city',
        (tester) async {
      _useDetector([const DetectOutsideServedArea(900, 'Dhangadhi')]);
      await pumpPicker(tester);
      await tapDetect(tester);

      expect(find.textContaining('nearest is Dhangadhi'), findsOneWidget);
      expect(find.text('New address'), findsNothing);
    });

    testWidgets('the problem clears once a retry succeeds', (tester) async {
      _useDetector([
        const DetectTimeout(),
        const DetectResolved(
          city: 'Kathmandu',
          province: 'Bagmati',
          distanceKm: 1,
          fromGeocoder: true,
        ),
      ]);
      await pumpPicker(tester);
      await tapDetect(tester);
      expect(find.textContaining('took too long'), findsOneWidget);

      await tester.tap(find.text('Try again').first);
      await tester.pumpAndSettle();

      // A stale error left sitting under a successful result would be worse
      // than no message at all.
      expect(find.textContaining('took too long'), findsNothing);
    });

    testWidgets('the tile shows it is working while it waits', (tester) async {
      final gate = Completer<void>();
      _useDetector([const DetectTimeout()], gate: gate);
      await pumpPicker(tester);

      await tester.tap(find.text('Use my current location'));
      await tester.pump();

      expect(find.text('Finding you...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Finding you...'), findsNothing);
    });
  });
}
