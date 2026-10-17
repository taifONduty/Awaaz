import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/account_models.dart';
import '../domain/native_sharing.dart';

class AndroidSharingPlatform implements NativeSharingPlatform {
  const AndroidSharingPlatform();
  static const _methods = MethodChannel('awaaz/sharing');
  @override
  bool get supported => !kIsWeb && Platform.isAndroid;
  @override
  Future<bool> requestLocationPermission() async {
    if (!supported) return false;
    try {
      return await _methods.invokeMethod<bool>('locationPermission') ?? false;
    } catch (_) {
      throw const ApiFailure('location_permission');
    }
  }

  @override
  Future<bool> requestNotifications() async {
    if (!supported) return false;
    try {
      return await _methods.invokeMethod<bool>('notifications') ?? false;
    } catch (_) {
      throw const ApiFailure('notifications_required');
    }
  }

  Future<Map<String, Object?>> _call(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (!supported) throw const ApiFailure('sharing_unsupported');
    try {
      final value = await _methods
          .invokeMethod<Object?>(method, arguments)
          .timeout(const Duration(seconds: 8));
      if (value is! Map) throw const ApiFailure('invalid_response');
      return Map<String, Object?>.from(value);
    } on ApiFailure {
      rethrow;
    } on PlatformException catch (failure) {
      throw ApiFailure(failure.code);
    } catch (_) {
      throw const ApiFailure('sharing_unavailable');
    }
  }

  @override
  Future<NativeShareState> bindOwner(String? owner) async =>
      NativeShareState.fromJson(await _call('bindOwner', {'ownerId': owner}));
  @override
  Future<NativeSharePreparation> prepare(
    String owner,
    String shareId,
    Uri origin, {
    String locale = 'en',
  }) async => NativeSharePreparation.fromJson(
    await _call('prepare', {
      'ownerId': owner,
      'shareId': shareId,
      'baseUrl': origin.toString(),
      'locale': locale == 'bn' ? 'bn' : 'en',
    }),
  );
  @override
  Future<NativeShareState> activate(
    NativeSharePreparation prepared,
    ShareDeviceGrant grant,
  ) async {
    if (prepared.shareId != grant.shareId || grant.status != 'active') {
      throw const ApiFailure('share_unavailable');
    }
    return NativeShareState.fromJson(
      await _call('activate', {
        'attempt': prepared.attempt,
        'grant': jsonEncode(grant.toJson()),
      }),
    );
  }

  @override
  Future<NativeShareState> state() async =>
      NativeShareState.fromJson(await _call('state'));
  @override
  Future<NativeShareState> pause(String shareId) async =>
      NativeShareState.fromJson(await _call('pause', {'shareId': shareId}));
  @override
  Future<NativeShareState> stop(String shareId) async =>
      NativeShareState.fromJson(await _call('stop', {'shareId': shareId}));
}
