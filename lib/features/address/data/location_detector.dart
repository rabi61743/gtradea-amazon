import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// A city this shop delivers to, and where it is.
class ServedCity {
  const ServedCity(this.city, this.province, this.latitude, this.longitude);

  final String city;
  final String province;
  final double latitude;
  final double longitude;
}

/// The cities a detected position is matched against.
///
/// Coordinates are approximate city centres, which is all this needs: the
/// question being answered is "which town is the shopper in", not "which
/// building". Adding a city here is the whole cost of serving a new one.
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
sealed class DetectResult {
  const DetectResult();
}

/// Found, and near enough to a city to name it.
class DetectResolved extends DetectResult {
  const DetectResolved({
    required this.city,
    required this.province,
    required this.distanceKm,
  });

  final String city;
  final String province;
  final double distanceKm;

  /// True when the fix is far enough out that the city is a guess worth
  /// flagging rather than stating.
  bool get isApproximate => distanceKm > 25;
}

/// Located, but nowhere near anywhere this shop delivers to.
class DetectOutsideServedArea extends DetectResult {
  const DetectOutsideServedArea(this.distanceKm, this.nearest);

  final double distanceKm;
  final String nearest;
}

/// The shopper said no. [permanently] means the OS will not ask again and the
/// only way back is system settings, which the UI has to say rather than
/// looping on a prompt that never appears.
class DetectPermissionDenied extends DetectResult {
  const DetectPermissionDenied({required this.permanently});
  final bool permanently;
}

/// Location is switched off on the device, which no permission grant fixes.
class DetectServiceDisabled extends DetectResult {
  const DetectServiceDisabled();
}

/// Something else went wrong -- no fix in time, a hardware failure, a plugin
/// missing on this platform.
class DetectFailed extends DetectResult {
  const DetectFailed(this.reason);
  final String reason;
}

/// Turns a device position into a city this shop knows.
///
/// There is no reverse-geocoding service here, and rather than pretend
/// otherwise this matches the fix against [kServedCities]. That is honest
/// about what it can deliver: the city and province, filled in for the
/// shopper, with the street still theirs to write. It also works with no
/// network, which a geocoder would not.
///
/// [instance] is replaceable so the sheets can be tested without a device.
class LocationDetector {
  const LocationDetector();

  static LocationDetector instance = const LocationDetector();

  /// Asks the OS where we are, then names the nearest city.
  Future<DetectResult> detect() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const DetectServiceDisabled();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const DetectPermissionDenied(permanently: true);
      }
      if (permission == LocationPermission.denied) {
        return const DetectPermissionDenied(permanently: false);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // Coarse is the right accuracy for the question. A city-level answer
          // does not need a GPS lock, and asking for one costs the shopper a
          // long wait and a warm phone for no better answer.
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 12),
        ),
      );

      return matchPosition(position.latitude, position.longitude);
    } catch (error) {
      return DetectFailed(error.toString());
    }
  }

  /// The pure half: coordinates in, a result out.
  ///
  /// Separated from the plugin so the matching can be tested properly, which
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
