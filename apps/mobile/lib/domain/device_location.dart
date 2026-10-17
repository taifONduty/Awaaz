import 'package:flutter/foundation.dart';

class LocationFailure implements Exception {
  const LocationFailure(this.code);
  final String code;
  @override
  String toString() => 'LocationFailure($code)';
}

@immutable
class DeviceLocation {
  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.capturedAt,
    required this.precise,
    required this.mocked,
    this.hasAccuracy = true,
  });
  final double latitude, longitude, accuracy;
  final DateTime capturedAt;
  final bool precise, mocked, hasAccuracy;

  /// Browsing a map accepts approximate fixes. Road reporting and monitoring
  /// retain their stricter precision, coverage and accuracy rules below.
  String? mapProblemAt(DateTime now, {bool allowMocked = false}) {
    if (mocked && !allowMocked) return 'location_mocked';
    if (!hasAccuracy ||
        !accuracy.isFinite ||
        accuracy <= 0 ||
        accuracy > 50000) {
      return 'location_inaccurate';
    }
    final age = now.difference(capturedAt);
    if (age > const Duration(minutes: 2) || age < const Duration(seconds: -5)) {
      return 'location_stale';
    }
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return 'location_inaccurate';
    }
    return null;
  }

  String? problemAt(DateTime now, {bool allowMocked = false}) {
    if (!precise) return 'location_approximate';
    if (mocked && !allowMocked) return 'location_mocked';
    if (!hasAccuracy || !accuracy.isFinite || accuracy < 0 || accuracy > 50) {
      return 'location_inaccurate';
    }
    final age = now.difference(capturedAt);
    if (age > const Duration(minutes: 2) || age < const Duration(seconds: -5)) {
      return 'location_stale';
    }
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < 23.62 ||
        latitude > 24.02 ||
        longitude < 90.20 ||
        longitude > 90.58) {
      return 'outside_pilot';
    }
    return null;
  }
}

abstract interface class LocationSource {
  Future<DeviceLocation> acquire();
  Future<void> cancel();
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}
