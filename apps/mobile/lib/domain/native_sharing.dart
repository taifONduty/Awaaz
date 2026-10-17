import 'account_models.dart';

class ShareDeviceGrant {
  ShareDeviceGrant.fromJson(Map<String, Object?> data)
    : shareId = jsonString(data, 'shareId'),
      expiresAt = jsonDate(data, 'expiresAt'),
      serverTime = jsonDate(data, 'serverTime'),
      sequence = data['sequence'] as int,
      status = jsonString(data, 'status') {
    if (sequence < 0 ||
        sequence > 2147483646 ||
        ![
          'unbound',
          'active',
          'revoked',
          'stopped',
          'expired',
        ].contains(status)) {
      throw const ApiFailure('invalid_response');
    }
  }
  final String shareId, status;
  final DateTime expiresAt, serverTime;
  final int sequence;
  Map<String, Object?> toJson() => {
    'shareId': shareId,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'serverTime': serverTime.toUtc().toIso8601String(),
    'sequence': sequence,
    'status': status,
  };
}

abstract interface class ShareDeviceRepository {
  Uri get sharingOrigin;
  Future<ShareDeviceGrant> bindShareDevice(
    String shareId,
    String credentialHash,
  );
  Future<ShareDeviceGrant> shareDevice(String shareId);
  Future<ShareDeviceGrant> revokeShareDevice(String shareId);
}

class NativeSharePreparation {
  NativeSharePreparation.fromJson(Map<String, Object?> data)
    : shareId = jsonString(data, 'shareId'),
      credentialHash = jsonString(data, 'credentialHash'),
      attempt = jsonString(data, 'attempt') {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(credentialHash)) {
      throw const ApiFailure('invalid_response');
    }
  }
  final String shareId, credentialHash, attempt;
}

class NativeShareState {
  NativeShareState.fromJson(Map<String, Object?> data)
    : active = jsonBool(data, 'active'),
      phase = jsonString(data, 'phase'),
      shareId = data['shareId'] as String?,
      lastUpload = switch (data['lastUpload']) {
        final String value when value.isNotEmpty => DateTime.parse(
          value,
        ).toUtc(),
        _ => null,
      },
      sequence = data['sequence'] as int? ?? 0 {
    if (![
          'idle',
          'prepared',
          'starting',
          'active',
          'paused',
          'stopping',
          'stop_unconfirmed',
          'stopped',
          'expired',
          'revoked',
          'unavailable',
          'cleanup_pending',
        ].contains(phase) ||
        sequence < 0 ||
        sequence > 2147483646 ||
        (active && (phase != 'active' || shareId == null))) {
      throw const ApiFailure('invalid_response');
    }
  }
  final bool active;
  final String phase;
  final String? shareId;
  final DateTime? lastUpload;
  final int sequence;
}

abstract interface class NativeSharingPlatform {
  bool get supported;
  Future<bool> requestNotifications();
  Future<bool> requestLocationPermission();
  Future<NativeShareState> bindOwner(String? owner);
  Future<NativeSharePreparation> prepare(
    String owner,
    String shareId,
    Uri origin, {
    String locale = 'en',
  });
  Future<NativeShareState> activate(
    NativeSharePreparation prepared,
    ShareDeviceGrant grant,
  );
  Future<NativeShareState> state();
  Future<NativeShareState> pause(String shareId);
  Future<NativeShareState> stop(String shareId);
}
