import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/account_models.dart';
import '../domain/trip_monitor.dart';

class AndroidTripPlatform implements TripPlatform {
  const AndroidTripPlatform();
  static const _methods = MethodChannel('awaaz/trip');
  static const _events = EventChannel('awaaz/trip_events');
  @override
  bool get supported => !kIsWeb && Platform.isAndroid;
  TripSnapshot _snapshot(Object? value) {
    // StandardMessageCodec decodes maps with Object keys, unlike JSON HTTP.
    if (value is! Map) throw const ApiFailure('invalid_response');
    return TripSnapshot.fromJson(Map<String, Object?>.from(value));
  }

  Future<TripSnapshot> _call(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (!supported) return const TripSnapshot(reason: 'monitor_unsupported');
    try {
      return _snapshot(
        await _methods
            .invokeMethod<Object?>(method, arguments)
            .timeout(const Duration(seconds: 8)),
      );
    } on PlatformException catch (failure) {
      throw ApiFailure(failure.code);
    } catch (_) {
      throw const ApiFailure('monitor_unavailable');
    }
  }

  @override
  Stream<TripSnapshot> get changes => supported
      ? _events.receiveBroadcastStream().map(_snapshot)
      : const Stream.empty();
  @override
  Future<TripSnapshot> bindOwner(String? owner) =>
      _call('bindOwner', {'ownerId': owner});
  @override
  Future<bool> requestNotifications() async {
    if (!supported) return false;
    try {
      return await _methods.invokeMethod<bool>('notifications') ?? false;
    } catch (_) {
      throw const ApiFailure('notifications_required');
    }
  }

  @override
  Future<TripSnapshot> start(Map<String, Object?> bundle) =>
      _call('start', {'bundle': jsonEncode(bundle)});
  @override
  Future<TripSnapshot> state() => _call('state');
  @override
  Future<TripSnapshot> stop() => _call('stop');
  @override
  Future<TripSnapshot> acknowledge(String sessionId) =>
      _call('acknowledge', {'sessionId': sessionId});
  @override
  Future<TripSnapshot> replace(Map<String, Object?> bundle) =>
      _call('replace', {'bundle': jsonEncode(bundle)});
}
