import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class GoogleMapsConfig {
  /// Reports configuration only, not SDK authorization or network readiness.
  /// The credential is never returned through this channel.
  static Future<bool> isConfigured() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    // The supported build script derives this non-secret flag from the same
    // local SDK configuration. It avoids a cold-start native-channel timeout.
    if (const bool.hasEnvironment('AWAAZ_GOOGLE_MAPS')) {
      return const bool.fromEnvironment('AWAAZ_GOOGLE_MAPS');
    }
    try {
      return await const MethodChannel('awaaz/maps')
              .invokeMethod<bool>('isConfigured')
              .timeout(const Duration(seconds: 3)) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
