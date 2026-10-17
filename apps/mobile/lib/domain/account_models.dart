import 'package:flutter/foundation.dart';

import 'models.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.code, {this.retryable = false});
  final String code;
  final bool retryable;
  @override
  String toString() => 'ApiFailure($code)';
}

Map<String, Object?> jsonObject(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const ApiFailure('invalid_response');
  }
  return value;
}

String jsonString(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is! String) throw const ApiFailure('invalid_response');
  return value;
}

bool jsonBool(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is! bool) throw const ApiFailure('invalid_response');
  return value;
}

DateTime jsonDate(Map<String, Object?> data, String key) {
  final value = DateTime.tryParse(jsonString(data, key));
  if (value == null) throw const ApiFailure('invalid_response');
  return value.toUtc();
}

double jsonNumber(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is! num || !value.isFinite) {
    throw const ApiFailure('invalid_response');
  }
  return value.toDouble();
}

List<T> jsonItems<T>(
  Map<String, Object?> data,
  T Function(Map<String, Object?>) parse,
) {
  final value = data['items'];
  if (value is! List<Object?>) throw const ApiFailure('invalid_response');
  return List.unmodifiable(value.map((item) => parse(jsonObject(item))));
}

@immutable
class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.displayName,
    required this.locale,
  });
  final String id;
  final String displayName;
  final String locale;
  factory AccountProfile.fromJson(Map<String, Object?> data) {
    final locale = jsonString(data, 'locale');
    if (!['en', 'bn'].contains(locale) || !jsonBool(data, 'adultAttested')) {
      throw const ApiFailure('invalid_response');
    }
    return AccountProfile(
      id: jsonString(data, 'id'),
      displayName: jsonString(data, 'displayName'),
      locale: locale,
    );
  }
}

@immutable
class OwnAccount {
  const OwnAccount({
    required this.userId,
    required this.phoneVerified,
    required this.profile,
  });
  final String userId;
  final bool phoneVerified;
  final AccountProfile? profile;
  factory OwnAccount.fromJson(Map<String, Object?> data) => OwnAccount(
    userId: jsonString(data, 'userId'),
    phoneVerified: jsonBool(data, 'phoneVerified'),
    profile: data['profile'] == null
        ? null
        : AccountProfile.fromJson(jsonObject(data['profile'])),
  );
}

@immutable
class TrustedCircle {
  const TrustedCircle({
    required this.id,
    required this.name,
    required this.ownerId,
  });
  final String id;
  final String name;
  final String ownerId;
  factory TrustedCircle.fromJson(Map<String, Object?> data) => TrustedCircle(
    id: jsonString(data, 'id'),
    name: jsonString(data, 'name'),
    ownerId: jsonString(data, 'ownerId'),
  );
}

@immutable
class CircleMember {
  const CircleMember({
    required this.userId,
    required this.displayName,
    required this.isOwner,
  });
  final String userId;
  final String displayName;
  final bool isOwner;
  factory CircleMember.fromJson(Map<String, Object?> data) {
    final role = jsonString(data, 'role');
    if (!['owner', 'member'].contains(role)) {
      throw const ApiFailure('invalid_response');
    }
    return CircleMember(
      userId: jsonString(data, 'userId'),
      displayName: jsonString(data, 'displayName'),
      isOwner: role == 'owner',
    );
  }
}

@immutable
class CircleDetail {
  CircleDetail({required this.circle, required List<CircleMember> members})
    : members = List.unmodifiable(members);
  final TrustedCircle circle;
  final List<CircleMember> members;
  factory CircleDetail.fromJson(Map<String, Object?> data) {
    final members = data['members'];
    if (members is! List<Object?>) throw const ApiFailure('invalid_response');
    return CircleDetail(
      circle: TrustedCircle.fromJson(data),
      members: members
          .map((item) => CircleMember.fromJson(jsonObject(item)))
          .toList(),
    );
  }
}

@immutable
class CircleInvitation {
  const CircleInvitation({
    required this.id,
    required this.circleName,
    required this.inviterName,
    required this.inviterId,
    required this.expiresAt,
  });
  final String id;
  final String circleName;
  final String inviterName;
  final String inviterId;
  final DateTime expiresAt;
  factory CircleInvitation.fromJson(Map<String, Object?> data) =>
      CircleInvitation(
        id: jsonString(data, 'id'),
        circleName: jsonString(data, 'circleName'),
        inviterName: jsonString(data, 'inviterName'),
        inviterId: jsonString(data, 'inviterId'),
        expiresAt: jsonDate(data, 'expiresAt'),
      );
}

@immutable
class CreatedInvitation {
  const CreatedInvitation({
    required this.id,
    required this.token,
    required this.expiresAt,
  });
  final String id;
  final String token;
  final DateTime expiresAt;
  factory CreatedInvitation.fromJson(Map<String, Object?> data) =>
      CreatedInvitation(
        id: jsonString(data, 'id'),
        token: jsonString(data, 'token'),
        expiresAt: jsonDate(data, 'expiresAt'),
      );
}

@immutable
class PrivateRoadReport {
  const PrivateRoadReport({
    required this.id,
    required this.category,
    required this.description,
    required this.status,
    required this.latitude,
    required this.longitude,
    required this.observedAt,
  });
  final String id;
  final ReportCategory category;
  final String description;
  final String status;
  final double latitude;
  final double longitude;
  final DateTime observedAt;
  factory PrivateRoadReport.fromJson(Map<String, Object?> data) {
    final status = jsonString(data, 'status');
    if (!['pending', 'reviewed', 'rejected'].contains(status)) {
      throw const ApiFailure('invalid_response');
    }
    return PrivateRoadReport(
      id: jsonString(data, 'id'),
      category: reportCategory(data),
      description: jsonString(data, 'description'),
      status: status,
      latitude: jsonNumber(data, 'latitude'),
      longitude: jsonNumber(data, 'longitude'),
      observedAt: jsonDate(data, 'observedAt'),
    );
  }
}

ReportCategory reportCategory(Map<String, Object?> data) {
  final name = jsonString(data, 'category');
  for (final category in ReportCategory.values) {
    if (category.name == name) return category;
  }
  throw const ApiFailure('invalid_response');
}

@immutable
class ReportPageResult {
  ReportPageResult({
    required List<PrivateRoadReport> items,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);
  final List<PrivateRoadReport> items;
  final String? nextCursor;
  factory ReportPageResult.fromJson(Map<String, Object?> data) {
    final cursor = data['nextCursor'];
    if (cursor != null && cursor is! String) {
      throw const ApiFailure('invalid_response');
    }
    return ReportPageResult(
      items: jsonItems(data, PrivateRoadReport.fromJson),
      nextCursor: cursor as String?,
    );
  }
}

@immutable
class PublishedRoadEvent {
  const PublishedRoadEvent({
    required this.id,
    required this.category,
    required this.summary,
    required this.observedAt,
    required this.expiresAt,
  });
  final String id;
  final ReportCategory category;
  final String summary;
  final DateTime observedAt;
  final DateTime expiresAt;
  factory PublishedRoadEvent.fromJson(Map<String, Object?> data) =>
      PublishedRoadEvent(
        id: jsonString(data, 'id'),
        category: reportCategory(data),
        summary: jsonString(data, 'summary'),
        observedAt: jsonDate(data, 'observedAt'),
        expiresAt: jsonDate(data, 'expiresAt'),
      );
}

@immutable
class ContactBlockState {
  const ContactBlockState({
    required this.userId,
    required this.blocked,
    required this.version,
  });
  final String userId;
  final bool blocked;
  final int version;
  factory ContactBlockState.fromJson(Map<String, Object?> data) {
    final version = data['version'];
    if (version is! int || version < 0 || version > 2147483646) {
      throw const ApiFailure('invalid_response');
    }
    return ContactBlockState(
      userId: jsonString(data, 'userId'),
      blocked: jsonBool(data, 'blocked'),
      version: version,
    );
  }
}

@immutable
class BlockedContact {
  const BlockedContact({required this.userId, required this.displayName});
  final String userId;
  final String? displayName;
  factory BlockedContact.fromJson(Map<String, Object?> data) {
    final name = data['displayName'];
    if (name != null && name is! String) {
      throw const ApiFailure('invalid_response');
    }
    return BlockedContact(
      userId: jsonString(data, 'userId'),
      displayName: name as String?,
    );
  }
}

@immutable
class BlockedContactsPage {
  BlockedContactsPage({
    required List<BlockedContact> items,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);
  final List<BlockedContact> items;
  final String? nextCursor;
  factory BlockedContactsPage.fromJson(Map<String, Object?> data) {
    final cursor = data['nextCursor'];
    if (cursor != null && cursor is! String) {
      throw const ApiFailure('invalid_response');
    }
    return BlockedContactsPage(
      items: jsonItems(data, BlockedContact.fromJson),
      nextCursor: cursor as String?,
    );
  }
}

abstract interface class SessionRepository {
  String? get userId;
  Stream<String?> get userChanges;
  Future<String?> accessToken({bool forceRefresh = false});
  Future<void> requestCode(String phone);
  Future<void> verifyCode(String phone, String code);
  Future<void> signOut();
}

abstract interface class AccountRepository {
  Future<OwnAccount> me();
  Future<AccountProfile> saveProfile(String name, String locale);
  Future<List<TrustedCircle>> circles();
  Future<TrustedCircle> createCircle(String requestId, String name);
  Future<CircleDetail> circle(String id);
  Future<CreatedInvitation> invite(
    String requestId,
    String circleId,
    String recipientId,
  );
  Future<List<CircleInvitation>> invitations();
  Future<void> accept(String id, String token);
  Future<void> revoke(String id);
  Future<void> removeMember(String circleId, String memberId);
  Future<void> closeCircle(String id);
  Future<BlockedContactsPage> blockedContacts({String? after});
  Future<ContactBlockState> blockState(String userId);
  Future<ContactBlockState> setBlock(
    String userId,
    bool blocked,
    int expectedVersion,
  );
  Future<ReportPageResult> reports({String? cursor});
  Future<String> submitReport(
    String requestId,
    ReportCategory category,
    String description,
    double latitude,
    double longitude,
    DateTime observedAt,
  );
  Future<void> withdrawReport(String id);
  Future<String> reportStatus(String requestId);
  Future<List<PublishedRoadEvent>> events();
}
