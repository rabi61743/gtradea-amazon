import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gtradea_amazon/core/theme/app_theme.dart';
import 'package:gtradea_amazon/features/address/data/address_store.dart';
import 'package:gtradea_amazon/features/address/data/location_detector.dart';
import 'package:gtradea_amazon/features/address/presentation/address_picker_sheet.dart';
import 'package:gtradea_amazon/features/auth/data/auth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fake extends LocationDetector {
  _Fake(this.result);
  final DetectResult result;
  @override
  Future<DetectResult> detect() async => result;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AddressStore.instance.resetForTest();
    AuthStore.instance.resetForTest();
  });

  test('PROBE 0: Simikot is outside the served area', () {
    final r = LocationDetector.matchPosition(29.9700, 81.8200);
    print('PROBE 0 matchPosition(Simikot) => $r');
    if (r is DetectOutsideServedArea) {
      print('PROBE 0 distance=${r.distanceKm} nearest=${r.nearest}');
    }
    expect(r, isA<DetectOutsideServedArea>());
  });

  testWidgets('PROBE A: decorated province from geocoder', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    LocationDetector.instance = _Fake(const DetectResolved(
      city: 'Simikot',
      province: 'Karnali Province',
      street: 'Simikot Bazaar',
      distanceKm: 0,
      fromGeocoder: true,
    ));
    addTearDown(() => LocationDetector.instance = const LocationDetector());

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: AddressPickerSheet()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use my current location'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    print('PROBE A snackbar "Found you in Simikot." => '
        '${find.text('Found you in Simikot.').evaluate().isNotEmpty}');
    print('PROBE A form opened => '
        '${find.text('New address').evaluate().isNotEmpty}');
    final ex = tester.takeException();
    print('PROBE A exception => $ex');
  });

  testWidgets('PROBE B: bare known province (control)', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    LocationDetector.instance = _Fake(const DetectResolved(
      city: 'Simikot',
      province: 'Karnali',
      distanceKm: 0,
      fromGeocoder: true,
    ));
    addTearDown(() => LocationDetector.instance = const LocationDetector());

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: AddressPickerSheet()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use my current location'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    print('PROBE B form opened => '
        '${find.text('New address').evaluate().isNotEmpty}');
    print('PROBE B exception => ${tester.takeException()}');
  });
}
