import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/account_models.dart';

class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({
    required this.key,
    this.storage = const FlutterSecureStorage(),
  });
  final String key;
  final FlutterSecureStorage storage;
  Future<void> _pending = Future.value();
  Future<void> _serialize(Future<void> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.catchError((Object _) {});
    return result;
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => (await accessToken()) != null;
  @override
  Future<String?> accessToken() async {
    await _pending;
    return storage.read(key: key);
  }

  @override
  Future<void> persistSession(String value) =>
      _serialize(() => storage.write(key: key, value: value));
  @override
  Future<void> removePersistedSession() =>
      _serialize(() => storage.delete(key: key));
}

class SupabaseSessions implements SessionRepository {
  SupabaseSessions(this.client, this.storage);
  final SupabaseClient client;
  final LocalStorage storage;
  static const _timeout = Duration(seconds: 12);
  @override
  String? get userId => client.auth.currentUser?.id;
  @override
  Stream<String?> get userChanges => client.auth.onAuthStateChange
      .map((state) => state.session?.user.id)
      .distinct();

  @override
  Future<String?> accessToken({bool forceRefresh = false}) async {
    final session = client.auth.currentSession;
    if (session == null) return null;
    if (forceRefresh || session.isExpired) {
      try {
        await client.auth.refreshSession().timeout(_timeout);
      } catch (_) {
        throw const ApiFailure('auth_unavailable', retryable: true);
      }
    }
    return client.auth.currentSession?.accessToken;
  }

  Future<void> _auth(Future<void> Function() action) async {
    try {
      await action().timeout(_timeout);
    } on AuthException catch (error) {
      if (error.statusCode == '429') {
        throw const ApiFailure('rate_limited', retryable: true);
      }
      if ([
        'otp_expired',
        'otp_disabled',
        'validation_failed',
      ].contains(error.code)) {
        throw const ApiFailure('invalid_code');
      }
      throw const ApiFailure('auth_unavailable', retryable: true);
    } catch (_) {
      throw const ApiFailure('auth_unavailable', retryable: true);
    }
  }

  @override
  Future<void> requestCode(String phone) =>
      _auth(() => client.auth.signInWithOtp(phone: phone));
  @override
  Future<void> verifyCode(String phone, String code) => _auth(() async {
    await client.auth.verifyOTP(phone: phone, token: code, type: OtpType.sms);
  });
  @override
  Future<void> signOut() async {
    // SDK memory is cleared before server revocation. A failed network request
    // cannot restore the previous session; do not delete a newer session.
    try {
      await client.auth.signOut(scope: SignOutScope.local).timeout(_timeout);
    } catch (_) {
      throw const ApiFailure('signout_local_only');
    } finally {
      if (client.auth.currentSession == null) {
        await storage.removePersistedSession();
      }
    }
  }
}
