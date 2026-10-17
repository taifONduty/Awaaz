import 'package:flutter/foundation.dart';

class BackendConfig {
  const BackendConfig({
    required this.apiUrl,
    required this.supabaseUrl,
    required this.publishableKey,
  });
  final Uri apiUrl;
  final Uri supabaseUrl;
  final String publishableKey;

  static BackendConfig? fromEnvironment() => parse(
    api: const String.fromEnvironment('AWAAZ_API_URL'),
    supabase: const String.fromEnvironment('SUPABASE_URL'),
    key: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    release: kReleaseMode,
  );

  static BackendConfig? parse({
    required String api,
    required String supabase,
    required String key,
    bool release = true,
  }) {
    if (api.isEmpty && supabase.isEmpty && key.isEmpty) return null;
    if (api.isEmpty || supabase.isEmpty || key.isEmpty) {
      throw const FormatException('Incomplete backend configuration');
    }
    Uri checked(String value) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.path.isNotEmpty && uri.path != '/') ||
          (uri.scheme != 'https' &&
              !(uri.scheme == 'http' &&
                  !release &&
                  ['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host)))) {
        throw const FormatException(
          'Backend URLs require HTTPS; debug loopback is allowed',
        );
      }
      return uri;
    }

    if (!RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(key)) {
      throw const FormatException(
        'Use a fresh project publishable key, never a secret key',
      );
    }
    return BackendConfig(
      apiUrl: checked(api),
      supabaseUrl: checked(supabase),
      publishableKey: key,
    );
  }
}
