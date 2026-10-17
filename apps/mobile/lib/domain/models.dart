import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'trip_monitor.dart';

enum TravelMode { car, walk }

enum RoutePreference { lowerRisk, fastest }

enum ReportCategory {
  obstruction,
  lighting,
  theft,
  harassment,
  accident,
  other,
}

enum DemoScenario { normal, offline, routeError, emptyReports }

enum JourneyPhase { idle, active, checkIn }

@immutable
class Destination {
  const Destination(
    this.id,
    this.name,
    this.banglaName, {
    this.point,
    this.namedPlace = false,
  });
  final String id;
  final String name;
  final String banglaName;
  final GeoPoint? point;
  final bool namedPlace;
}

@immutable
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude, longitude;
  double distanceTo(GeoPoint other) {
    const rad = math.pi / 180;
    final h =
        math.pow(math.sin((other.latitude - latitude) * rad / 2), 2) +
        math.cos(latitude * rad) *
            math.cos(other.latitude * rad) *
            math.pow(math.sin((other.longitude - longitude) * rad / 2), 2);
    return 6371000 * 2 * math.asin(math.sqrt(h.clamp(0, 1).toDouble()));
  }

  bool get inPilot =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= 23.62 &&
      latitude <= 24.02 &&
      longitude >= 90.20 &&
      longitude <= 90.58;
  Map<String, double> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };
}

@immutable
class RouteOption {
  const RouteOption({
    required this.id,
    required this.preference,
    required this.minutes,
    required this.kilometres,
    required this.coverage,
    this.corridor,
    this.sourceTimestamp,
    this.syntheticReports = false,
    this.reportRoutingStatus,
  });
  final String id;
  final RoutePreference preference;
  final int minutes;
  final double kilometres;
  // Observed-route coverage (synthetic in fixtures), not a safety score.
  final double? coverage;
  final ApprovedCorridor? corridor;
  final DateTime? sourceTimestamp;
  final bool syntheticReports;
  final String? reportRoutingStatus;
}

@immutable
class CommunityReport {
  const CommunityReport({
    required this.category,
    required this.place,
    required this.description,
    required this.reviewed,
  });
  final ReportCategory category;
  final String place;
  final String description;
  final bool reviewed;
}

@immutable
class ReportDraft {
  const ReportDraft({
    required this.id,
    required this.category,
    required this.place,
    required this.description,
    required this.createdAt,
  });
  final String id;
  final ReportCategory category;
  final String place;
  final String description;
  final DateTime createdAt;
  Map<String, Object> toJson() => {
    'id': id,
    'category': category.name,
    'place': place,
    'description': description,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
  factory ReportDraft.fromJson(Map<String, Object?> json) => ReportDraft(
    id: json['id']! as String,
    category: ReportCategory.values.byName(json['category']! as String),
    place: json['place']! as String,
    description: json['description']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
  );
}
