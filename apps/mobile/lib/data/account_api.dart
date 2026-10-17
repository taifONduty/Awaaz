import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/account_models.dart';
import '../domain/models.dart';
import '../domain/sharing.dart';
import '../domain/device_location.dart';
import '../domain/native_sharing.dart';
import '../domain/sos.dart';

class AccountApi
    implements
        AccountRepository,
        SharingRepository,
        ShareDeviceRepository,
        SosRepository {
  AccountApi({
    required this.baseUrl,
    required this.sessions,
    required this.client,
    this.timeout = const Duration(seconds: 12),
  });
  final Uri baseUrl;
  final SessionRepository sessions;
  final http.Client client;
  final Duration timeout;
  static const _maxResponseBytes = 256 * 1024;
  static const _codes = {
    'unauthenticated',
    'verification_required',
    'profile_required',
    'invalid_request',
    'invalid_report',
    'outside_pilot',
    'idempotency_conflict',
    'not_found',
    'invite_pending',
    'already_member',
    'invite_unavailable',
    'invite_reissue_required',
    'owner_cannot_leave',
    'members_limit_reached',
    'circles_limit_reached',
    'circle_closed',
    'rate_limited',
    'auth_unavailable',
    'storage_unavailable',
    'block_changed',
    'blocks_limit_reached',
    'block_version_exhausted',
    'share_recipient_unavailable',
    'share_already_active',
    'share_unavailable',
    'stale_position',
    'device_revoked',
    'device_already_bound',
    'native_publisher_active',
    'sos_preference_changed',
    'sos_response_changed',
    'sos_recipient_unavailable',
    'incident_already_active',
    'incident_unavailable',
  };

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final identity = sessions.userId;
    if (identity == null) throw const ApiFailure('unauthenticated');
    final token = await sessions.accessToken();
    if (token == null) throw const ApiFailure('unauthenticated');
    if (sessions.userId != identity) throw const ApiFailure('session_changed');
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(
            method,
            baseUrl.resolve(path).replace(queryParameters: query),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    Future<Map<String, Object?>> send() async {
      final response = await client.send(request);
      final bytes = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.stream) {
        total += chunk.length;
        if (total > _maxResponseBytes) {
          throw const ApiFailure('invalid_response');
        }
        bytes.add(chunk);
      }
      if (sessions.userId != identity) {
        throw const ApiFailure('session_changed');
      }
      Map<String, Object?> data;
      try {
        data = jsonObject(jsonDecode(utf8.decode(bytes.takeBytes())));
      } on FormatException {
        throw const ApiFailure('invalid_response');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = data['code'];
        throw ApiFailure(
          code is String && _codes.contains(code) ? code : 'request_failed',
          retryable: response.statusCode == 429 || response.statusCode >= 500,
        );
      }
      return data;
    }

    try {
      return await send().timeout(
        timeout,
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw const ApiFailure('network_unavailable', retryable: true);
        },
      );
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure('network_unavailable', retryable: true);
    }
  }

  String _id(String id) {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(id)) {
      throw const ApiFailure('invalid_request');
    }
    return id.toLowerCase();
  }

  @override
  Future<OwnAccount> me() async {
    final me = OwnAccount.fromJson(await _request('GET', '/v1/me'));
    if (me.userId != sessions.userId ||
        (me.profile != null && me.profile!.id != me.userId)) {
      throw const ApiFailure('invalid_response');
    }
    return me;
  }

  @override
  Future<AccountProfile> saveProfile(String name, String locale) async =>
      AccountProfile.fromJson(
        await _request(
          'PUT',
          '/v1/me',
          body: {
            'displayName': name.trim(),
            'locale': locale,
            'adultAttested': true,
          },
        ),
      );
  @override
  Future<List<TrustedCircle>> circles() async =>
      jsonItems(await _request('GET', '/v1/circles'), TrustedCircle.fromJson);
  @override
  Future<TrustedCircle> createCircle(String requestId, String name) async {
    final data = await _request(
      'POST',
      '/v1/circles',
      body: {'clientRequestId': _id(requestId), 'name': name.trim()},
    );
    return TrustedCircle.fromJson(jsonObject(data['circle']));
  }

  @override
  Future<CircleDetail> circle(String id) async =>
      CircleDetail.fromJson(await _request('GET', '/v1/circles/${_id(id)}'));
  @override
  Future<CreatedInvitation> invite(
    String requestId,
    String circleId,
    String recipientId,
  ) async => CreatedInvitation.fromJson(
    await _request(
      'POST',
      '/v1/circles/${_id(circleId)}/invites',
      body: {
        'clientRequestId': _id(requestId),
        'recipientId': _id(recipientId),
      },
    ),
  );
  @override
  Future<List<CircleInvitation>> invitations() async => jsonItems(
    await _request('GET', '/v1/circle-invites'),
    CircleInvitation.fromJson,
  );
  @override
  Future<void> accept(String id, String token) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw const ApiFailure('invalid_request');
    }
    await _request(
      'POST',
      '/v1/circle-invites/${_id(id)}/accept',
      body: {'token': token},
    );
  }

  @override
  Future<void> revoke(String id) async {
    await _request('DELETE', '/v1/circle-invites/${_id(id)}');
  }

  @override
  Future<void> removeMember(String circleId, String memberId) async {
    await _request(
      'DELETE',
      '/v1/circles/${_id(circleId)}/members/${_id(memberId)}',
    );
  }

  @override
  Future<void> closeCircle(String id) async {
    await _request('DELETE', '/v1/circles/${_id(id)}');
  }

  @override
  Future<BlockedContactsPage> blockedContacts({String? after}) async =>
      BlockedContactsPage.fromJson(
        await _request(
          'GET',
          '/v1/me/blocks',
          query: {'limit': '30', if (after != null) 'after': _id(after)},
        ),
      );

  @override
  Future<ContactBlockState> blockState(String userId) async {
    final id = _id(userId);
    final state = ContactBlockState.fromJson(
      await _request('GET', '/v1/me/blocks/$id'),
    );
    if (state.userId != id) throw const ApiFailure('invalid_response');
    return state;
  }

  @override
  Future<ContactBlockState> setBlock(
    String userId,
    bool blocked,
    int expectedVersion,
  ) async {
    final id = _id(userId);
    if (expectedVersion < 0 || expectedVersion > 2147483646) {
      throw const ApiFailure('invalid_request');
    }
    final state = ContactBlockState.fromJson(
      await _request(
        'PUT',
        '/v1/me/blocks/$id',
        body: {'blocked': blocked, 'expectedVersion': expectedVersion},
      ),
    );
    if (state.userId != id ||
        state.blocked != blocked ||
        (state.version != expectedVersion &&
            state.version != expectedVersion + 1)) {
      throw const ApiFailure('invalid_response');
    }
    return state;
  }

  @override
  Future<ReportPageResult> reports({String? cursor}) async =>
      ReportPageResult.fromJson(
        await _request(
          'GET',
          '/v1/reports',
          query: {'limit': '30', 'cursor': ?cursor},
        ),
      );
  @override
  Future<String> submitReport(
    String requestId,
    ReportCategory category,
    String description,
    double latitude,
    double longitude,
    DateTime observedAt,
  ) async {
    final data = await _request(
      'POST',
      '/v1/reports',
      body: {
        'clientRequestId': _id(requestId),
        'category': category.name,
        'description': description.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'observedAt': observedAt.toUtc().toIso8601String(),
      },
    );
    return _reportStatus(data);
  }

  String _reportStatus(Map<String, Object?> data) {
    final status = jsonString(data, 'status');
    if (!['pending', 'reviewed', 'rejected', 'withdrawn'].contains(status)) {
      throw const ApiFailure('invalid_response');
    }
    return status;
  }

  @override
  Future<String> reportStatus(String requestId) async => _reportStatus(
    await _request('GET', '/v1/report-requests/${_id(requestId)}'),
  );

  @override
  Future<void> withdrawReport(String id) async {
    await _request('DELETE', '/v1/reports/${_id(id)}');
  }

  @override
  Future<List<PublishedRoadEvent>> events() async => jsonItems(
    await _request('GET', '/v1/road-events', query: {'limit': '50'}),
    PublishedRoadEvent.fromJson,
  );

  @override
  Future<TripShare?> currentShare() async {
    final data = await _request('GET', '/v1/me/share');
    return data['share'] == null
        ? null
        : TripShare.fromJson(jsonObject(data['share']));
  }

  @override
  Future<TripShare> shareRequest(String requestId) async => TripShare.fromJson(
    await _request('GET', '/v1/share-requests/${_id(requestId)}'),
  );

  @override
  Future<TripShare> createShare(
    String requestId,
    String circleId,
    List<String> recipientIds,
    int durationSeconds,
  ) async => TripShare.fromJson(
    await _request(
      'POST',
      '/v1/shares',
      body: {
        'clientRequestId': _id(requestId),
        'circleId': _id(circleId),
        'recipientIds': recipientIds.map(_id).toList(),
        'durationSeconds': durationSeconds,
      },
    ),
  );

  @override
  Future<TripShare> stopShare(String id) async =>
      TripShare.fromJson(await _request('DELETE', '/v1/shares/${_id(id)}'));

  @override
  Future<void> revokeShareRecipient(String id, String userId) async {
    await _request('DELETE', '/v1/shares/${_id(id)}/recipients/${_id(userId)}');
  }

  @override
  Future<IncomingTripsPage> incomingShares({String? after}) async =>
      IncomingTripsPage.fromJson(
        await _request(
          'GET',
          '/v1/shared-trips',
          query: {'limit': '50', if (after != null) 'after': _id(after)},
        ),
      );

  @override
  Future<SharedTrip> sharedTrip(String id) async =>
      SharedTrip.fromJson(await _request('GET', '/v1/shares/${_id(id)}'));

  @override
  Future<void> publishSharePosition(
    String id,
    int sequence,
    DeviceLocation position,
  ) async {
    final data = await _request(
      'PUT',
      '/v1/shares/${_id(id)}/position',
      body: {
        'sequence': sequence,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracyMetres': position.accuracy,
        'capturedAt': position.capturedAt.toUtc().toIso8601String(),
      },
    );
    if (jsonString(data, 'shareId') != id || data['sequence'] != sequence) {
      throw const ApiFailure('invalid_response');
    }
  }

  @override
  Uri get sharingOrigin => baseUrl;
  Future<ShareDeviceGrant> _device(
    String method,
    String shareId, {
    String? credentialHash,
  }) async {
    final grant = ShareDeviceGrant.fromJson(
      await _request(
        method,
        '/v1/shares/${_id(shareId)}/device',
        body: credentialHash == null
            ? null
            : {'credentialHash': credentialHash},
      ),
    );
    if (grant.shareId != shareId.toLowerCase()) {
      throw const ApiFailure('invalid_response');
    }
    return grant;
  }

  @override
  Future<ShareDeviceGrant> bindShareDevice(
    String shareId,
    String credentialHash,
  ) => _device('POST', shareId, credentialHash: credentialHash);
  @override
  Future<ShareDeviceGrant> shareDevice(String shareId) =>
      _device('GET', shareId);
  @override
  Future<ShareDeviceGrant> revokeShareDevice(String shareId) =>
      _device('DELETE', shareId);

  @override
  Uri get sosOrigin => baseUrl;
  @override
  Future<SosCapability> sosCapability() async =>
      SosCapability.fromJson(await _request('GET', '/v1/sos/status'));
  @override
  Future<SosPreference> sosPreference() async =>
      SosPreference.fromJson(await _request('GET', '/v1/me/sos-preference'));
  @override
  Future<SosPreference> setSosPreference(
    bool allowed,
    int expectedVersion,
  ) async {
    final value = SosPreference.fromJson(
      await _request(
        'PUT',
        '/v1/me/sos-preference',
        body: {'allowed': allowed, 'expectedVersion': expectedVersion},
      ),
    );
    if (value.allowed != allowed || value.version != expectedVersion + 1) {
      throw const ApiFailure('invalid_response');
    }
    return value;
  }

  @override
  Future<List<SosContact>> sosContacts(String circleId) async => jsonItems(
    await _request('GET', '/v1/circles/${_id(circleId)}/sos-recipients'),
    SosContact.fromJson,
  );
  @override
  Future<SosControl?> currentSos() async {
    final value = await _request('GET', '/v1/me/incident');
    return value['incident'] == null
        ? null
        : SosControl.fromJson(jsonObject(value['incident']));
  }

  @override
  Future<SosControl> sosRequest(String requestId) async => SosControl.fromJson(
    await _request('GET', '/v1/incident-requests/${_id(requestId)}'),
  );
  @override
  Future<SosControl> createSos(SosIntent intent) async => SosControl.fromJson(
    await _request(
      'POST',
      '/v1/incidents',
      body: {
        'clientRequestId': intent.id,
        'circleId': intent.circleId,
        'recipientIds': intent.recipients,
        'mode': 'silent',
        'shareLocation': intent.shareLocation,
      },
    ),
  );
  @override
  Future<void> withdrawSos(String requestId) async {
    final value = await _request(
      'DELETE',
      '/v1/incident-requests/${_id(requestId)}',
    );
    if (jsonString(value, 'clientRequestId') != _id(requestId) ||
        value['status'] != 'cancelled' ||
        (value['incidentStatus'] != null &&
            ![
              'ended',
              'cancelled',
              'expired',
            ].contains(value['incidentStatus']))) {
      throw const ApiFailure('invalid_response');
    }
  }

  @override
  Future<SosControl> endSos(String id, String outcome) async {
    final value = SosControl.fromJson(
      await _request(
        'POST',
        '/v1/incidents/${_id(id)}/end',
        body: {'outcome': outcome},
      ),
    );
    if (value.id != _id(id) || value.status == 'active') {
      throw const ApiFailure('invalid_response');
    }
    return value;
  }

  @override
  Future<SosIncomingPage> incomingSos({String? after}) async =>
      SosIncomingPage.fromJson(
        await _request(
          'GET',
          '/v1/me/incidents',
          query: {'limit': '30', if (after != null) 'after': _id(after)},
        ),
      );
  @override
  Future<SosView> viewSos(String id) async {
    final value = SosView.fromJson(
      await _request('GET', '/v1/incidents/${_id(id)}'),
    );
    if (value.id != _id(id)) throw const ApiFailure('invalid_response');
    return value;
  }

  @override
  Future<void> respondSos(
    String id,
    String response,
    int expectedVersion,
  ) async {
    final value = await _request(
      'PUT',
      '/v1/incidents/${_id(id)}/response',
      body: {'response': response, 'expectedVersion': expectedVersion},
    );
    if (jsonString(value, 'incidentId') != _id(id) ||
        value['response'] != response ||
        value['version'] != expectedVersion + 1) {
      throw const ApiFailure('invalid_response');
    }
  }

  @override
  Future<void> declineSos(String id) async {
    final value = await _request('DELETE', '/v1/incidents/${_id(id)}/access');
    if (value['incidentId'] != _id(id) || value['status'] != 'revoked') {
      throw const ApiFailure('invalid_response');
    }
  }

  @override
  Future<DateTime> publishSosPosition(
    String id,
    int sequence,
    DeviceLocation fix,
  ) async {
    final value = await _request(
      'PUT',
      '/v1/incidents/${_id(id)}/position',
      body: {
        'sequence': sequence,
        'latitude': fix.latitude,
        'longitude': fix.longitude,
        'accuracyMetres': fix.accuracy,
        'capturedAt': fix.capturedAt.toUtc().toIso8601String(),
      },
    );
    if (value['incidentId'] != _id(id) || value['sequence'] != sequence) {
      throw const ApiFailure('invalid_response');
    }
    return jsonDate(value, 'acceptedAt');
  }
}
