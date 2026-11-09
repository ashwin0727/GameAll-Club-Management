import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Where the supported cities are (the centre of each), in the same wording as the city picker. The device position is matched
/// to the nearest one here, on the phone / in the browser: the coordinates are never sent to a server.
const cityCentres = <String, (double, double)>{
  'Bangalore, Karnataka': (12.9716, 77.5946),
  'Chennai, Tamil Nadu': (13.0827, 80.2707),
  'Hyderabad, Telangana': (17.3850, 78.4867),
  'Mumbai, Maharashtra': (19.0760, 72.8777),
  'Delhi NCR, Delhi': (28.6139, 77.2090),
  'Pune, Maharashtra': (18.5204, 73.8567),
  'Kolkata, West Bengal': (22.5726, 88.3639),
  'Kochi, Kerala': (9.9312, 76.2673),
  'Coimbatore, Tamil Nadu': (11.0168, 76.9558),
  'Ahmedabad, Gujarat': (23.0225, 72.5714),
};

/// How far from a city centre still counts as "in that city" (greater-city areas are wide).
const cityRadiusKm = 60.0;

/// Great-circle distance between two points, in kilometres.
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// The supported city nearest to a position, or null when none is within [cityRadiusKm].
String? nearestCity(
  double lat,
  double lon, {
  Map<String, (double, double)> cities = cityCentres,
  double radiusKm = cityRadiusKm,
}) {
  String? best;
  var bestKm = double.infinity;
  for (final e in cities.entries) {
    final d = distanceKm(lat, lon, e.value.$1, e.value.$2);
    if (d < bestKm) {
      bestKm = d;
      best = e.key;
    }
  }
  return bestKm <= radiusKm ? best : null;
}

/// What asking the device for its position led to.
sealed class LocationOutcome {
  const LocationOutcome();
}

/// The device is in (or next to) this supported city.
class LocationFound extends LocationOutcome {
  const LocationFound(this.city);
  final String city;
}

/// The position was read, but it is not near any city we serve yet.
class LocationOutsideService extends LocationOutcome {
  const LocationOutsideService();
}

/// The player said no to the permission (they can be asked again).
class LocationDenied extends LocationOutcome {
  const LocationDenied();
}

/// The permission is blocked: only the phone / browser settings can turn it on.
class LocationBlocked extends LocationOutcome {
  const LocationBlocked();
}

/// The phone's location switch is off.
class LocationServiceOff extends LocationOutcome {
  const LocationServiceOff();
}

/// No position could be read (no signal, timed out, unsupported browser).
class LocationFailed extends LocationOutcome {
  const LocationFailed();
}

/// Reads the device position. Tests replace this with a fake.
abstract class DeviceLocation {
  Future<LocationOutcome> detectCity();

  /// The device position (latitude, longitude), or null when it is not available or the player said no. Used to sort venues by
  /// distance. It never nags: it asks the system at most once for permission, and a refusal is just "no position".
  Future<(double, double)?> currentPosition();

  /// Opens the system settings page for this app (to turn a blocked permission on).
  Future<void> openSettings();
}

class GeolocatorDeviceLocation implements DeviceLocation {
  const GeolocatorDeviceLocation();

  /// Permission and switch checks shared by both calls: null when a fix may be read, otherwise why not.
  Future<LocationOutcome?> _gate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationServiceOff();
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationBlocked();
    }
    if (permission == LocationPermission.denied) {
      return const LocationDenied();
    }
    return null;
  }

  /// A position, trying the gentlest ways first: the phone's last known one (instant), then a fresh rough one, then (Android) the
  /// plain system location provider for phones without Google Play services, then a more accurate fix. Throws if every way fails.
  Future<Position> _fix() async {
    if (!kIsWeb) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return last;
      } catch (_) {}
    }
    Object? error;
    final attempts = <LocationSettings>[
      const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 15),
      ),
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        AndroidSettings(
          accuracy: LocationAccuracy.low,
          forceLocationManager: true,
          timeLimit: const Duration(seconds: 15),
        ),
      const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 20),
      ),
    ];
    for (final s in attempts) {
      try {
        return await Geolocator.getCurrentPosition(locationSettings: s);
      } catch (e) {
        error = e;
      }
    }
    throw error ?? StateError('no position');
  }

  @override
  Future<LocationOutcome> detectCity() async {
    try {
      final blocked = await _gate();
      if (blocked != null) return blocked;
      final pos = await _fix();
      final city = nearestCity(pos.latitude, pos.longitude);
      return city == null ? const LocationOutsideService() : LocationFound(city);
    } catch (e) {
      debugPrint('Location could not be read: $e');
      return const LocationFailed();
    }
  }

  @override
  Future<(double, double)?> currentPosition() async {
    try {
      if (await _gate() != null) return null;
      final pos = await _fix();
      return (pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }
}

final deviceLocationProvider = Provider<DeviceLocation>(
  (ref) => const GeolocatorDeviceLocation(),
);
