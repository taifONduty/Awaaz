import 'account_models.dart';
import 'device_location.dart';

class ShareRecipient {
  const ShareRecipient(this.userId, this.active);
  final String userId;
  final bool active;
}

class TripShare {
  TripShare.fromJson(Map<String, Object?> data)
    : id = jsonString(data, 'id'),
      circleId = data['circleId'] as String?,
      expiresAt = jsonDate(data, 'expiresAt'),
      status = jsonString(data, 'status'),
      sequence = data['sequence'] as int,
      recipients = jsonItems(
        {'items': data['recipients']},
        (item) => ShareRecipient(
          jsonString(item, 'userId'),
          jsonBool(item, 'active'),
        ),
      ) {
    if (!['active', 'stopped', 'expired'].contains(status) || sequence < 0) {
      throw const ApiFailure('invalid_response');
    }
  }
  final String id, status;
  final String? circleId;
  final DateTime expiresAt;
  final int sequence;
  final List<ShareRecipient> recipients;
}

class IncomingTrip {
  IncomingTrip.fromJson(Map<String, Object?> data)
    : id = jsonString(data, 'id'),
      ownerName = jsonString(data, 'ownerName'),
      expiresAt = jsonDate(data, 'expiresAt');
  final String id, ownerName;
  final DateTime expiresAt;
}

class SharedPosition {
  SharedPosition.fromJson(Map<String, Object?> data)
    : latitude = jsonNumber(data, 'latitude'),
      longitude = jsonNumber(data, 'longitude'),
      accuracy = jsonNumber(data, 'accuracyMetres'),
      capturedAt = jsonDate(data, 'capturedAt'),
      expiresAt = jsonDate(data, 'expiresAt') {
    if (latitude < 23.62 ||
        latitude > 24.02 ||
        longitude < 90.2 ||
        longitude > 90.58 ||
        accuracy < 1 ||
        accuracy > 100) {
      throw const ApiFailure('invalid_response');
    }
  }
  final double latitude, longitude, accuracy;
  final DateTime capturedAt, expiresAt;
}

class SharedTrip {
  SharedTrip.fromJson(Map<String, Object?> data)
    : id = jsonString(data, 'id'),
      ownerName = jsonString(data, 'ownerName'),
      serverTime = jsonDate(data, 'serverTime'),
      expiresAt = jsonDate(data, 'expiresAt'),
      freshness = jsonString(data, 'freshness'),
      position = data['location'] == null
          ? null
          : SharedPosition.fromJson(jsonObject(data['location'])) {
    if (!['waiting', 'fresh', 'stale'].contains(freshness) ||
        (position != null && freshness != 'fresh')) {
      throw const ApiFailure('invalid_response');
    }
  }
  final String id, ownerName, freshness;
  final DateTime serverTime, expiresAt;
  final SharedPosition? position;
}

class IncomingTripsPage {
  IncomingTripsPage.fromJson(Map<String, Object?> data)
    : items = jsonItems(data, IncomingTrip.fromJson),
      nextCursor = data['nextCursor'] as String?;
  final List<IncomingTrip> items;
  final String? nextCursor;
}

abstract interface class SharingRepository {
  Future<TripShare?> currentShare();
  Future<TripShare> shareRequest(String requestId);
  Future<TripShare> createShare(
    String requestId,
    String circleId,
    List<String> recipientIds,
    int durationSeconds,
  );
  Future<TripShare> stopShare(String id);
  Future<void> revokeShareRecipient(String id, String userId);
  Future<IncomingTripsPage> incomingShares({String? after});
  Future<SharedTrip> sharedTrip(String id);
  Future<void> publishSharePosition(
    String id,
    int sequence,
    DeviceLocation position,
  );
}
