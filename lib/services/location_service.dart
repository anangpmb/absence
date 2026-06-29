import 'dart:math';
import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Checks if the user is within the allowed radius from the office.
  Future<LocationCheckResult> checkRadius({
    required double officeLat,
    required double officeLng,
    required double maxRadiusMeters,
  }) async {
    final position = await _getCurrentPosition();

    final distance = _haversineDistance(
      lat1: officeLat,
      lng1: officeLng,
      lat2: position.latitude,
      lng2: position.longitude,
    );

    return LocationCheckResult(
      isWithinRadius: distance <= maxRadiusMeters,
      currentLat: position.latitude,
      currentLng: position.longitude,
      distanceMeters: distance,
    );
  }

  Future<Position> _getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationPermissionDeniedException('GPS is disabled.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDeniedException('Location permission denied.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  double _haversineDistance({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    const earthRadius = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _rad(double deg) => deg * pi / 180;
}

class LocationCheckResult {
  final bool isWithinRadius;
  final double currentLat;
  final double currentLng;
  final double distanceMeters;

  const LocationCheckResult({
    required this.isWithinRadius,
    required this.currentLat,
    required this.currentLng,
    required this.distanceMeters,
  });
}

class LocationPermissionDeniedException implements Exception {
  final String reason;
  const LocationPermissionDeniedException(this.reason);

  @override
  String toString() => 'LocationPermissionDeniedException: $reason';
}
