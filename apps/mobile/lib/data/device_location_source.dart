import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/device_location.dart';

class GeolocatorLocationSource implements LocationSource {
  GeolocatorLocationSource({this.forceAndroidLocationManager = false});
  final bool forceAndroidLocationManager;
  StreamSubscription<Position>? _subscription;
  Completer<DeviceLocation>? _pending;
  int _version = 0;
  void _current(int version) {
    if (version != _version) throw const LocationFailure('location_canceled');
  }

  @override
  Future<DeviceLocation> acquire() async {
    await cancel();
    final version = ++_version;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const LocationFailure('location_disabled');
      }
      _current(version);
      var permission = await Geolocator.checkPermission();
      _current(version);
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      _current(version);
      if (permission == LocationPermission.deniedForever) {
        throw const LocationFailure('location_denied_forever');
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const LocationFailure('location_denied');
      }
      final precise =
          await Geolocator.getLocationAccuracy() ==
          LocationAccuracyStatus.precise;
      _current(version);
      final pending = Completer<DeviceLocation>();
      _pending = pending;
      final settings =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
              forceLocationManager: forceAndroidLocationManager,
              // Awaaz uses horizontal fixes; supplementary GNSS data is opt-in.
              useMSLAltitude: false,
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
            );
      final subscription =
          Geolocator.getPositionStream(locationSettings: settings).listen(
            (position) {
              if (!pending.isCompleted) {
                pending.complete(
                  DeviceLocation(
                    latitude: position.latitude,
                    longitude: position.longitude,
                    accuracy: position.accuracy,
                    capturedAt: position.timestamp.toUtc(),
                    precise: precise,
                    mocked: position.isMocked,
                    hasAccuracy: position.hasAccuracy,
                  ),
                );
              }
            },
            onError: (Object _) {
              if (!pending.isCompleted) {
                pending.completeError(
                  const LocationFailure('location_unavailable'),
                );
              }
            },
          );
      _subscription = subscription;
      try {
        return await pending.future.timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw const LocationFailure('location_timeout'),
        );
      } finally {
        await subscription.cancel();
        if (identical(_pending, pending)) {
          _pending = null;
          _subscription = null;
        }
      }
    } on LocationFailure {
      rethrow;
    } catch (_) {
      throw const LocationFailure('location_unavailable');
    }
  }

  @override
  Future<void> cancel() async {
    _version++;
    final pending = _pending, subscription = _subscription;
    _pending = null;
    _subscription = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const LocationFailure('location_canceled'));
    }
    await subscription?.cancel();
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
