import 'package:uuid/uuid.dart';

import 'account_models.dart';
import 'device_location.dart';
import 'pending_write.dart';
import 'sharing.dart';

const sosResponses = ['seen', 'contacting', 'helping', 'unavailable'];
const sosStatuses = ['active', 'ended', 'cancelled', 'expired'];
int _version(Object? value, {int minimum = 0}) {
  if (value is! int || value < minimum || value > 2147483646) {
    throw const ApiFailure('invalid_response');
  }
  return value;
}

DateTime? _date(Map<String, Object?> data, String key) =>
    data[key] == null ? null : jsonDate(data, key);
List<String> _ids(Object? value) {
  if (value is! List<Object?>) throw const ApiFailure('storage_unavailable');
  final ids = value.map((id) => PendingWrite.checkedId(id as String)).toList()
    ..sort();
  return List.unmodifiable(ids);
}

String? _response(Object? value) {
  if (value == null || sosResponses.contains(value)) return value as String?;
  throw const ApiFailure('invalid_response');
}

class SosPreference {
  SosPreference.fromJson(Map<String, Object?> data)
    : allowed = jsonBool(data, 'allowed'),
      version = _version(data['version']);
  final bool allowed;
  final int version;
}

class SosCapability {
  SosCapability.fromJson(Map<String, Object?> data)
    : storage = jsonBool(data, 'requestStorage'),
      push = jsonBool(data, 'pushDelivery'),
      sms = jsonBool(data, 'smsDelivery');
  final bool storage, push, sms;
}

class SosContact {
  SosContact.fromJson(Map<String, Object?> data)
    : id = PendingWrite.checkedId(jsonString(data, 'userId')),
      name = jsonString(data, 'displayName');
  final String id, name;
}

class SosDelivery {
  SosDelivery.fromJson(Map<String, Object?> data)
    : kind = jsonString(data, 'kind'),
      status = jsonString(data, 'status'),
      acceptedAt = _date(data, 'providerAcceptedAt') {
    if (!['request', 'resolved', 'cancelled'].contains(kind) ||
        ![
          'queued',
          'sending',
          'provider_accepted',
          'failed',
          'cancelled',
          'expired',
          'unknown',
        ].contains(status)) {
      throw const ApiFailure('invalid_response');
    }
  }
  final String kind, status;
  final DateTime? acceptedAt;
}

class SosRecipient {
  SosRecipient.fromJson(Map<String, Object?> data)
    : id = PendingWrite.checkedId(jsonString(data, 'userId')),
      active = jsonBool(data, 'active'),
      response = _response(data['response']),
      responseVersion = _version(data['responseVersion']),
      respondedAt = _date(data, 'respondedAt'),
      delivery = jsonItems({'items': data['delivery']}, SosDelivery.fromJson);
  final String id;
  final bool active;
  final String? response;
  final int responseVersion;
  final DateTime? respondedAt;
  final List<SosDelivery> delivery;
}

class SosControl {
  SosControl.fromJson(Map<String, Object?> data)
    : id = PendingWrite.checkedId(jsonString(data, 'id')),
      circleId = data['circleId'] == null
          ? null
          : PendingWrite.checkedId(jsonString(data, 'circleId')),
      status = jsonString(data, 'status'),
      mode = jsonString(data, 'mode'),
      startedAt = jsonDate(data, 'startedAt'),
      expiresAt = jsonDate(data, 'expiresAt'),
      serverTime = jsonDate(data, 'serverTime'),
      version = _version(data['version'], minimum: 1),
      sequence = _version(data['sequence']),
      shareLocation = jsonBool(data, 'shareLocation'),
      recipients = jsonItems({
        'items': data['recipients'],
      }, SosRecipient.fromJson) {
    if (!sosStatuses.contains(status) ||
        !['silent', 'audible'].contains(mode) ||
        recipients.length > 10 ||
        recipients.map((r) => r.id).toSet().length != recipients.length) {
      throw const ApiFailure('invalid_response');
    }
  }
  final String id, status, mode;
  final String? circleId;
  final DateTime startedAt, expiresAt, serverTime;
  final int version, sequence;
  final bool shareLocation;
  final List<SosRecipient> recipients;
}

class SosIncoming {
  SosIncoming.fromJson(Map<String, Object?> data)
    : id = PendingWrite.checkedId(jsonString(data, 'id')),
      name = jsonString(data, 'ownerName'),
      status = jsonString(data, 'status'),
      expiresAt = jsonDate(data, 'expiresAt') {
    if (!sosStatuses.contains(status)) {
      throw const ApiFailure('invalid_response');
    }
  }
  final String id, name, status;
  final DateTime expiresAt;
}

class SosIncomingPage {
  SosIncomingPage.fromJson(Map<String, Object?> data)
    : items = jsonItems(data, SosIncoming.fromJson),
      nextCursor = data['nextCursor'] == null
          ? null
          : PendingWrite.checkedId(jsonString(data, 'nextCursor'));
  final List<SosIncoming> items;
  final String? nextCursor;
}

class SosView {
  SosView.fromJson(Map<String, Object?> data)
    : id = PendingWrite.checkedId(jsonString(data, 'id')),
      name = jsonString(data, 'ownerName'),
      status = jsonString(data, 'status'),
      serverTime = jsonDate(data, 'serverTime'),
      expiresAt = jsonDate(data, 'expiresAt'),
      response = _response(data['response']),
      responseVersion = _version(data['responseVersion']),
      respondedAt = _date(data, 'respondedAt'),
      position = data['location'] == null
          ? null
          : SharedPosition.fromJson(jsonObject(data['location'])) {
    if (!sosStatuses.contains(status) ||
        (status != 'active' && position != null)) {
      throw const ApiFailure('invalid_response');
    }
  }
  final String id, name, status;
  final DateTime serverTime, expiresAt;
  final String? response;
  final int responseVersion;
  final DateTime? respondedAt;
  final SharedPosition? position;
}

/// One explicitly approved activation, scoped by the journal's owner/backend.
/// Coordinates, recipient names and credentials are deliberately absent.
class SosIntent {
  SosIntent.fromJson(Map<String, Object?> data)
    : id = PendingWrite.checkedId(jsonString(data, 'id')),
      circleId = PendingWrite.checkedId(jsonString(data, 'circleId')),
      phase = jsonString(data, 'phase'),
      createdAt = jsonDate(data, 'createdAt'),
      shareLocation = jsonBool(data, 'shareLocation'),
      recipients = _ids(data['recipients']) {
    if (data.length != 6 ||
        !['activation', 'withdrawal'].contains(phase) ||
        recipients.isEmpty ||
        recipients.length > 10 ||
        recipients.toSet().length != recipients.length) {
      throw const ApiFailure('storage_unavailable');
    }
  }
  factory SosIntent.create(
    String circle,
    Iterable<String> recipients,
    bool location,
  ) => SosIntent.fromJson({
    'id': const Uuid().v4(),
    'circleId': circle,
    'phase': 'activation',
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'shareLocation': location,
    'recipients': recipients.toList()..sort(),
  });
  final String id, circleId, phase;
  final DateTime createdAt;
  final bool shareLocation;
  final List<String> recipients;
  Map<String, Object> toJson() => {
    'id': id,
    'circleId': circleId,
    'phase': phase,
    'createdAt': createdAt.toIso8601String(),
    'shareLocation': shareLocation,
    'recipients': recipients,
  };
  SosIntent withdrawing() =>
      SosIntent.fromJson({...toJson(), 'phase': 'withdrawal'});
}

abstract interface class SosRepository {
  Uri get sosOrigin;
  Future<SosCapability> sosCapability();
  Future<SosPreference> sosPreference();
  Future<SosPreference> setSosPreference(bool allowed, int expectedVersion);
  Future<List<SosContact>> sosContacts(String circleId);
  Future<SosControl?> currentSos();
  Future<SosControl> sosRequest(String requestId);
  Future<SosControl> createSos(SosIntent intent);
  Future<void> withdrawSos(String requestId);
  Future<SosControl> endSos(String id, String outcome);
  Future<SosIncomingPage> incomingSos({String? after});
  Future<SosView> viewSos(String id);
  Future<void> respondSos(String id, String response, int expectedVersion);
  Future<void> declineSos(String id);
  Future<DateTime> publishSosPosition(
    String id,
    int sequence,
    DeviceLocation fix,
  );
}
