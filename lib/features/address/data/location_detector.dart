import 'dart:async';
import 'dart:math' as math;

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'address_store.dart' show kProvinces;

/// A city this shop delivers to, and where it is.
class ServedCity {
  const ServedCity(this.city, this.province, this.latitude, this.longitude);

  final String city;
  final String province;
  final double latitude;
  final double longitude;
}

/// The cities a position falls back to when the platform geocoder cannot
/// answer -- offline, or somewhere it has no data for.
///
/// Coordinates are approximate city centres, which is all the fallback needs:
/// it is answering "which town", not "which building". Adding a city here is
/// the whole cost of serving a new one.
const kServedCities = <ServedCity>[
  ServedCity('Kathmandu', 'Bagmati', 27.7172, 85.3240),
  ServedCity('Lalitpur', 'Bagmati', 27.6644, 85.3188),
  ServedCity('Bhaktapur', 'Bagmati', 27.6710, 85.4298),
  ServedCity('Hetauda', 'Bagmati', 27.4287, 85.0324),
  ServedCity('Bharatpur', 'Bagmati', 27.6768, 84.4360),
  ServedCity('Pokhara', 'Gandaki', 28.2096, 83.9856),
  ServedCity('Butwal', 'Lumbini', 27.7000, 83.4500),
  ServedCity('Nepalgunj', 'Lumbini', 28.0500, 81.6167),
  ServedCity('Biratnagar', 'Koshi', 26.4525, 87.2718),
  ServedCity('Dharan', 'Koshi', 26.8065, 87.2846),
  ServedCity('Itahari', 'Koshi', 26.6646, 87.2718),
  ServedCity('Birgunj', 'Madhesh', 27.0104, 84.8770),
  ServedCity('Janakpur', 'Madhesh', 26.7271, 85.9407),
  ServedCity('Birendranagar', 'Karnali', 28.6000, 81.6333),
  ServedCity('Dhangadhi', 'Sudurpashchim', 28.7000, 80.6000),
];

/// Past this, the nearest city is not a useful guess -- the shopper is
/// somewhere this shop does not have a name for, and filling in a town 300 km
/// away would be worse than filling in nothing.
const kMaxMatchKm = 120.0;

/// What came back from a detection attempt.
///
/// One case per thing that can actually happen, because each needs the shopper
/// told something different and offered a different way out. A single "failed"
/// would leave them with nothing to do next.
sealed class DetectResult {
  const DetectResult();
}

/// Found, and turned into something a courier could read.
class DetectResolved extends DetectResult {
  const DetectResolved({
    required this.city,
    required this.province,
    this.street,
    this.area,
    this.postalCode,
    required this.distanceKm,
    required this.fromGeocoder,
  });

  final String city;

  /// Always one of kProvinces, or empty when nothing recognisable was found.
  /// Never raw geocoder text: this becomes the form dropdown's value, and a
  /// value outside its items makes it assert.
  final String province;

  /// Street and house, when the platform geocoder could name one.
  final String? street;

  /// Neighbourhood or tole.
  final String? area;

  final String? postalCode;

  /// How far the fix was from the matched city centre. Only meaningful for the
  /// offline fallback.
  final double distanceKm;

  /// True when a real geocoder named this, false when it came from the offline
  /// city table. The difference is worth showing: one is an address, the other
  /// is a nearest town.
  final bool fromGeocoder;

  /// The line to prefill the street field with.
  ///
  /// Platform geocoders hand back a whole formatted address in [street] --
  /// "M8G5+6V8, 3 Bakhundole, Lalitpur 44600, Nepal" is a real one. Repeating
  /// the city, the postcode and the country in a field labelled "tole, street
  /// and house number" makes the form look wrong and gives the shopper a line
  /// to clean up. Anything that already has its own field is dropped, and so
  /// is the plus code, which no courier reads.
  String? get addressLine {
    final seen = <String>{};
    final kept = <String>[];

    for (final part in [
      ...?street?.split(','),
      ...?area?.split(','),
    ]) {
      final piece = part.trim();
      if (piece.isEmpty) continue;
      if (_isPlusCode(piece)) continue;

      final lower = piece.toLowerCase();
      if (lower == city.toLowerCase()) continue;
      if (lower == province.toLowerCase()) continue;
      if (lower == 'nepal') continue;
      if (postalCode != null && piece == postalCode) continue;
      // "Lalitpur 44600" -- the city and postcode glued together.
      if (postalCode != null &&
          lower == '${city.toLowerCase()} ${postalCode!.toLowerCase()}') {
        continue;
      }
      if (!seen.add(lower)) continue;

      kept.add(piece);
    }

    return kept.isEmpty ? null : kept.join(', ');
  }

  /// An Open Location Code, like "M8G5+6V8". Precise, and useless to a person.
  static bool _isPlusCode(String value) =>
      RegExp(r'^[23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3}$')
          .hasMatch(value.toUpperCase());

  /// True when this is a guess worth hedging about rather than stating.
  bool get isApproximate => !fromGeocoder && distanceKm > 25;
}

/// Located, but nowhere near anywhere this shop delivers to.
class DetectOutsideServedArea extends DetectResult {
  const DetectOutsideServedArea(this.distanceKm, this.nearest);

  final double distanceKm;
  final String nearest;
}

/// The shopper said no. [permanently] means the OS will not ask again and the
/// only way back is app settings.
class DetectPermissionDenied extends DetectResult {
  const DetectPermissionDenied({required this.permanently});
  final bool permanently;
}

/// Location is switched off on the device, which no permission grant fixes.
/// The way out is the system location settings.
class DetectServiceDisabled extends DetectResult {
  const DetectServiceDisabled();
}

/// A fix was asked for and never arrived in time. Usually indoors.
class DetectTimeout extends DetectResult {
  const DetectTimeout();
}

/// The device could not produce a position at all -- no provider, airplane
/// mode, hardware refusing. Different from a timeout: waiting longer will not
/// help.
class DetectUnavailable extends DetectResult {
  const DetectUnavailable();
}

/// Anything else, kept so an unexpected platform error is still reported
/// rather than swallowed.
class DetectFailed extends DetectResult {
  const DetectFailed(this.reason);
  final String reason;
}

/// Turns "where am I" into something the address form can use.
///
/// The platform's own geocoder is asked first -- Android's Geocoder, iOS's
/// CLGeocoder -- which is what can give a street and a postal code. When it
/// has nothing, which happens offline and in places it has no data for, the
/// fix falls back to the nearest served city so the shopper still gets the
/// town filled in rather than an error.
///
/// [instance] is replaceable so the UI can be tested without a device.
class LocationDetector {
  const LocationDetector();

  static LocationDetector instance = const LocationDetector();

  /// How long to wait for a fix before giving up and saying so.
  static const fixTimeout = Duration(seconds: 15);

  /// How long to wait on the permission dialog. Generous, because a shopper
  /// reads it, but bounded, because it can never come back at all.
  static const permissionTimeout = Duration(seconds: 60);

  /// A ceiling on the whole attempt, so no single step can hang the UI.
  static const overallTimeout = Duration(seconds: 90);

  /// Built once. In geocoding 5 the reverse lookup hangs off an instance
  /// rather than a top-level function.
  static final _geocoding = Geocoding();

  /// Whether the device's location service is on.
  ///
  /// Exposed separately so the UI can re-check after sending the shopper to
  /// settings, without asking for a position and triggering a prompt.
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  /// Opens the system location settings, for when the service is off.
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Opens this app's settings page, for a permission refused for good.
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Bounded end to end. Every individual step already has its own limit, but
  /// a plugin that never replies would otherwise leave the caller with a
  /// spinner and no way out, so the whole attempt is capped too.
  Future<DetectResult> detect() =>
      _detect().timeout(overallTimeout, onTimeout: () => const DetectTimeout());

  Future<DetectResult> _detect() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const DetectServiceDisabled();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Bounded, because the permission request is not guaranteed to come
        // back. On Android a dialog dismissed with Back -- or interrupted by a
        // call -- delivers an empty grantResults, which the plugin drops
        // without completing its reply. The future then never resolves and the
        // caller is left spinning with nothing to tap.
        permission = await Geolocator.requestPermission()
            .timeout(permissionTimeout, onTimeout: () {
          return LocationPermission.denied;
        });
      }
      if (permission == LocationPermission.deniedForever) {
        return const DetectPermissionDenied(permanently: true);
      }
      if (permission == LocationPermission.denied) {
        return const DetectPermissionDenied(permanently: false);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // Coarse: a delivery address needs the street, and the geocoder
          // supplies that from a rough fix. A GPS lock would cost the shopper
          // a long wait and a warm phone for the same answer.
          accuracy: LocationAccuracy.low,
          timeLimit: fixTimeout,
        ),
      );

      return await describe(position.latitude, position.longitude);
    } on TimeoutException {
      return const DetectTimeout();
    } on LocationServiceDisabledException {
      // The service can be switched off between the check above and the fix.
      return const DetectServiceDisabled();
    } on PermissionDeniedException {
      return const DetectPermissionDenied(permanently: false);
    } catch (error) {
      final text = error.toString().toLowerCase();
      if (text.contains('timeout') || text.contains('timed out')) {
        return const DetectTimeout();
      }
      if (text.contains('unavailable') || text.contains('position update')) {
        return const DetectUnavailable();
      }
      return DetectFailed(error.toString());
    }
  }

  /// Coordinates to an address, geocoder first and the city table second.
  Future<DetectResult> describe(double latitude, double longitude) async {
    try {
      final places = await _geocoding.placemarkFromCoordinates(
        latitude,
        longitude,
      );
      final place = places.isEmpty ? null : places.first;

      final city = _firstNonEmpty([
        place?.locality,
        place?.subAdministrativeArea,
        place?.administrativeArea,
      ]);

      if (place != null && city != null) {
        return DetectResolved(
          city: city,
          province: _province(place, latitude, longitude) ?? '',
          street: _firstNonEmpty([place.street, place.thoroughfare]),
          // subLocality only. subThoroughfare is the house NUMBER, not a
          // neighbourhood, and putting a bare "12" in the area reads as
          // nonsense next to a street that already carries it.
          area: _firstNonEmpty([place.subLocality]),
          postalCode: _firstNonEmpty([place.postalCode]),
          distanceKm: 0,
          fromGeocoder: true,
        );
      }
    } catch (_) {
      // No geocoder, no network, or nothing known about here. Falling through
      // to the offline match is better than telling the shopper it failed --
      // the town is still worth filling in.
    }

    return matchPosition(latitude, longitude);
  }

  /// Province, as one of the names the form's dropdown actually offers.
  ///
  /// Whatever comes back here ends up as the dropdown's selected value, and a
  /// value that is not among its items makes it assert -- so the form would
  /// never open at all. Everything below therefore resolves to a member of
  /// [kProvinces] or to null, and never to raw geocoder text.
  ///
  /// Geocoders decorate the name in ways a bare comparison misses: "Bagmati
  /// Province", "Province No. 3", or a district like "Kaski" that is not a
  /// province at all. A decorated match is accepted and canonicalised; a
  /// district falls through to the nearest served city, which is the right
  /// answer for it.
  static String? _province(
    Placemark place,
    double latitude,
    double longitude,
  ) {
    final given = _firstNonEmpty([place.administrativeArea]);
    if (given != null) {
      final lower = given.toLowerCase();
      for (final province in kProvinces) {
        final name = province.toLowerCase();
        if (lower == name || lower.contains(name)) return province;
      }
    }

    final nearest = matchPosition(latitude, longitude);
    if (nearest is DetectResolved) return nearest.province;

    // Outside the served area and the geocoder gave something unrecognised.
    // Null leaves the form on its own default rather than on a province that
    // is not in the list.
    return null;
  }

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final candidate in candidates) {
      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return null;
  }

  /// The offline half: coordinates in, nearest served city out.
  ///
  /// Separated from the plugins so the matching can be tested properly, which
  /// is where the logic worth testing actually lives.
  static DetectResult matchPosition(double latitude, double longitude) {
    if (kServedCities.isEmpty) {
      return const DetectFailed('No served cities configured');
    }

    var nearest = kServedCities.first;
    var best = double.infinity;
    for (final city in kServedCities) {
      final distance =
          distanceKm(latitude, longitude, city.latitude, city.longitude);
      if (distance < best) {
        best = distance;
        nearest = city;
      }
    }

    if (best > kMaxMatchKm) {
      return DetectOutsideServedArea(best, nearest.city);
    }
    return DetectResolved(
      city: nearest.city,
      province: nearest.province,
      distanceKm: best,
      fromGeocoder: false,
    );
  }

  /// Great-circle distance in kilometres.
  static double distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
