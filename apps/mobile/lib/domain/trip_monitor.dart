import 'package:flutter/foundation.dart';

import 'account_models.dart';

@immutable
class ApprovedCorridor {
  ApprovedCorridor({
    required this.graphVersion,
    required this.riskVersion,
    required List<List<double>> points,
    this.synthetic = false,
    this.validUntil,
  }) : points = List.unmodifiable(
         points.map((point) => List<double>.unmodifiable(point)),
       ) {
    if (graphVersion.isEmpty ||
        graphVersion.length > 128 ||
        riskVersion.isEmpty ||
        riskVersion.length > 128 ||
        points.length < 2 ||
        points.length > 2000 ||
        points.any(
          (point) =>
              point.length != 2 ||
              !point[0].isFinite ||
              !point[1].isFinite ||
              point[0] < 23.62 ||
              point[0] > 24.02 ||
              point[1] < 90.20 ||
              point[1] > 90.58,
        )) {
      throw const ApiFailure('invalid_corridor');
    }
  }
  final String graphVersion, riskVersion;
  final List<List<double>> points;
  final bool synthetic;
  final DateTime? validUntil;
}

@immutable
class TripSnapshot {
  const TripSnapshot({
    this.active = false,
    this.status = 'stopped',
    this.quality = 'unreliable',
    this.sessionId,
    this.routeId,
    this.reason,
    this.ownerId,
    this.revision = 0,
    this.synthetic = false,
    this.alertCount = 0,
  });
  final bool active, synthetic;
  final String status, quality;
  final String? sessionId, routeId, reason, ownerId;
  final int revision, alertCount;
  factory TripSnapshot.fromJson(Map<String, Object?> json) {
    final active = jsonBool(json, 'active'),
        status = jsonString(json, 'status');
    if (![
          'stopped',
          'waiting',
          'tracking',
          'candidate',
          'check_in',
          'unreliable',
          'interrupted',
        ].contains(status) ||
        json['sharing'] == true) {
      throw const ApiFailure('invalid_response');
    }
    return TripSnapshot(
      active: active,
      status: status,
      quality: json['quality'] as String? ?? 'unreliable',
      sessionId: json['sessionId'] as String?,
      routeId: json['routeId'] as String?,
      reason: json['reason'] as String?,
      ownerId: json['ownerId'] as String?,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      synthetic: json['synthetic'] == true,
      alertCount: (json['alertCount'] as num?)?.toInt() ?? 0,
    );
  }
}

abstract interface class TripPlatform {
  bool get supported;
  Stream<TripSnapshot> get changes;
  Future<TripSnapshot> bindOwner(String? owner);
  Future<bool> requestNotifications();
  Future<TripSnapshot> start(Map<String, Object?> bundle);
  Future<TripSnapshot> state();
  Future<TripSnapshot> stop();
  Future<TripSnapshot> acknowledge(String sessionId);
  Future<TripSnapshot> replace(Map<String, Object?> bundle);
}
