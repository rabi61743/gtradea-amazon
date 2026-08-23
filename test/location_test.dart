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
class _FakeDetector extends LocationDetector {
  const _FakeDetector(this.result);

  final DetectResult result;

  @override
  Future<DetectResult> detect() async => result;
}

void _useDetector(DetectResult result) {
  LocationDetector.instance = _FakeDetector(result);
  addTearDown(() => LocationDetector.instance = const LocationDetector());
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
      expect(resolved.isApproximate, isFalse);
    });

    test('neighbouring cities are told apart', () {
      // Lalitpur and Kathmandu are about five kilometres apart, which is
      // exactly the case a coarse fix has to get right.
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
      expect(
        (LocationDetector.matchPosition(28.2096, 83.9856) as DetectResolved)
            .city,
        'Pokhara',
      );
    });

    test('a fix well outside a city is flagged as approximate', () {
      // Roughly 40 km west of Pokhara: still the nearest, but a guess.
      final resolved =
          LocationDetector.matchPosition(28.21, 83.58) as DetectResolved;
      expect(resolved.city, 'Pokhara');
      expect(resolved.isApproximate, isTrue,
          reason: 'the wording should hedge rather than state');
    });

    test('somewhere this shop does not deliver is refused, not guessed', () {
      // London.
      final result = LocationDetector.matchPosition(51.5072, -0.1276);
      expect(result, isA<DetectOutsideServedArea>());
      expect((result as DetectOutsideServedArea).distanceKm,
          greaterThan(kMaxMatchKm));
    });

    test('every served city resolves to itself', () {
      // Guards the table: a typo in a coordinate would show up as a city
      // matching one of its neighbours instead of itself.
      for (final city in kServedCities) {
        final resolved = LocationDetector.matchPosition(
          city.latitude,
          city.longitude,
        );
        expect(resolved, isA<DetectResolved>(), reason: city.city);
        expect((resolved as DetectResolved).city, city.city,
            reason: city.city);
      }
    });

    test('distance is a real great-circle distance', () {
      // Kathmandu to Pokhara is about 140 km as the crow flies.
      final km = LocationDetector.distanceKm(27.7172, 85.3240, 28.2096, 83.9856);
      expect(km, greaterThan(120));
      expect(km, lessThan(160));
      expect(LocationDetector.distanceKm(27.7, 85.3, 27.7, 85.3), 0);
    });
  });

  group('using it from the picker', () {
    Future<void> pumpPicker(WidgetTester tester) async {
      _useTallWindow(tester);
      // Inside a Scaffold, as it is in the app: the sheet reports outcomes
      // through a snack bar, which needs one to present to.
      await tester.pumpWidget(_wrap(
        const Scaffold(body: AddressPickerSheet()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the row says it fills the city, not the whole address',
        (tester) async {
      _useDetector(const DetectResolved(
        city: 'Kathmandu',
        province: 'Bagmati',
        distanceKm: 1,
      ));
      await pumpPicker(tester);

      expect(find.text('Use my current location'), findsOneWidget);
      // Promising the doorstep would be promising what it cannot do.
      expect(find.text('Fills in your city, you add the street'),
          findsOneWidget);
    });

    testWidgets('a successful detection opens the form with the city filled',
        (tester) async {
      _useDetector(const DetectResolved(
        city: 'Pokhara',
        province: 'Gandaki',
        distanceKm: 2,
      ));
      await pumpPicker(tester);

      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();

      expect(find.text('New address'), findsOneWidget);
      // The field, not the quick-city chip of the same name behind the sheet.
      expect(find.widgetWithText(TextFormField, 'Pokhara'), findsOneWidget);
      expect(find.text('Gandaki'), findsWidgets);
    });

    testWidgets('a far-off fix hedges instead of stating', (tester) async {
      _useDetector(const DetectResolved(
        city: 'Pokhara',
        province: 'Gandaki',
        distanceKm: 40,
      ));
      await pumpPicker(tester);

      await tester.tap(find.text('Use my current location'));
      await tester.pump();
      expect(find.textContaining('Looks like you are near Pokhara'),
          findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('location switched off is told apart from permission refused',
        (tester) async {
      _useDetector(const DetectServiceDisabled());
      await pumpPicker(tester);

      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();

      // Asking for permission here would never raise a prompt, so the message
      // points at the thing that actually needs changing.
      expect(find.textContaining('switched off on this phone'), findsOneWidget);
      expect(find.text('New address'), findsNothing);
    });

    testWidgets('a permanent refusal points at settings, not at another ask',
        (tester) async {
      _useDetector(const DetectPermissionDenied(permanently: true));
      await pumpPicker(tester);

      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();

      expect(find.textContaining('phone settings'), findsOneWidget);
    });

    testWidgets('a one-off refusal just says what it needed', (tester) async {
      _useDetector(const DetectPermissionDenied(permanently: false));
      await pumpPicker(tester);

      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();

      expect(find.textContaining('need location permission'), findsOneWidget);
      expect(find.textContaining('phone settings'), findsNothing);
    });

    testWidgets('being outside the served area names the nearest city',
        (tester) async {
      _useDetector(const DetectOutsideServedArea(900, 'Dhangadhi'));
      await pumpPicker(tester);

      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();

      expect(find.textContaining('nearest is Dhangadhi'), findsOneWidget);
      expect(find.text('New address'), findsNothing);
    });

    testWidgets('a failure offers the way round it', (tester) async {
      _useDetector(const DetectFailed('timeout'));
      await pumpPicker(tester);

      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();

      // Not "something went wrong": a shopper needs to know what to do next.
      expect(find.textContaining('type the address instead'), findsOneWidget);
    });
  });
}
