import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding_platform_interface/geocoding_platform_interface.dart'
    as pi;
import 'package:gtradea_amazon/features/address/data/location_detector.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeGeocoding extends pi.Geocoding {
  _FakeGeocoding(super.params) : super.implementation();

  static late List<pi.Placemark> next;

  @override
  Future<List<pi.Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude, {
    Locale? locale,
  }) async =>
      next;
}

class _FakeFactory extends pi.GeocodingPlatformFactory
    with MockPlatformInterfaceMixin {
  @override
  pi.Geocoding createGeocoding(pi.GeocodingCreationParams params) =>
      _FakeGeocoding(params);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    pi.GeocodingPlatformFactory.instance = _FakeFactory();
  });

  test('PROBE C: geocoder province outside served area', () async {
    _FakeGeocoding.next = const [
      pi.Placemark(
        locality: 'Simikot',
        administrativeArea: 'Karnali Province',
        street: 'Simikot Bazaar',
        postalCode: '21000',
        country: 'Nepal',
      ),
    ];
    // Simikot, Humla.
    final r = await const LocationDetector().describe(29.9700, 81.8200);
    print('PROBE C => $r');
    if (r is DetectResolved) {
      print('PROBE C city=${r.city} province="${r.province}" '
          'inKProvinces=${_known(r.province)} fromGeocoder=${r.fromGeocoder}');
    }
  });

  test('PROBE D: same decorated name INSIDE served area (control)', () async {
    _FakeGeocoding.next = const [
      pi.Placemark(
        locality: 'Kathmandu',
        administrativeArea: 'Bagmati Province',
        street: 'Tridevi Marg',
      ),
    ];
    final r = await const LocationDetector().describe(27.7154, 85.3123);
    if (r is DetectResolved) {
      print('PROBE D city=${r.city} province="${r.province}" '
          'inKProvinces=${_known(r.province)}');
    }
  });

  test('PROBE E: across the border, far from any served city', () async {
    _FakeGeocoding.next = const [
      pi.Placemark(
        locality: 'Patna',
        administrativeArea: 'Bihar',
        country: 'India',
      ),
    ];
    final r = await const LocationDetector().describe(25.5941, 85.1376);
    if (r is DetectResolved) {
      print('PROBE E city=${r.city} province="${r.province}" '
          'inKProvinces=${_known(r.province)}');
    }
  });
}

bool _known(String p) => const [
      'Koshi',
      'Madhesh',
      'Bagmati',
      'Gandaki',
      'Lumbini',
      'Karnali',
      'Sudurpashchim',
    ].contains(p);
