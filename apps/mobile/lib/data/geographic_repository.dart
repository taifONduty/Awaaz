import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/account_models.dart';
import '../domain/models.dart';
import '../domain/trip_monitor.dart';
import 'safety_repository.dart';
import 'place_search.dart';

abstract interface class GeographicRouting implements SafetyRepository {
  Future<List<RouteOption>> routesFrom(
    GeoPoint origin,
    Destination destination,
    TravelMode mode,
  );
  void cancel();
  void close();
}

SafetyRepository createSafetyRepository() {
  const value = String.fromEnvironment('AWAAZ_ROUTING_API_URL');
  if (value.isEmpty) return DemoSafetyRepository();
  Uri? uri;
  try {
    uri = Uri.parse(value);
    if (uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                !kReleaseMode &&
                ['127.0.0.1', 'localhost', '10.0.2.2'].contains(uri.host)))) {
      uri = null;
    }
  } catch (_) {
    uri = null;
  }
  return GeographicRepository(baseUrl: uri, client: http.Client());
}

class GeographicRepository implements GeographicRouting, PlaceSearchService {
  GeographicRepository({required this.baseUrl, required this.client});
  final Uri? baseUrl;
  final http.Client client;
  Completer<void>? _abort;
  Completer<void>? _searchAbort;
  @override
  void cancelSearch() {
    final abort = _searchAbort;
    _searchAbort = null;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  @override
  Future<List<NamedPlace>> searchPlaces(String query) async {
    cancelSearch();
    final root = baseUrl;
    if (root == null ||
        query.trim().runes.length < 2 ||
        query.runes.length > 80) {
      throw const ApiFailure('places_unavailable');
    }
    final abort = _searchAbort = Completer<void>();
    final deadline = Timer(const Duration(seconds: 6), () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final request =
          http.AbortableRequest(
              'POST',
              root.resolve('/v1/places/search'),
              abortTrigger: abort.future,
            )
            ..headers['content-type'] = 'application/json'
            ..body = jsonEncode({'query': query.trim()});
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 6));
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 6),
      )) {
        bytes.add(chunk);
        if (bytes.length > 32000) throw const ApiFailure('places_unavailable');
      }
      if (response.statusCode != 200 || abort.isCompleted) {
        throw const ApiFailure('places_unavailable');
      }
      final data = jsonObject(jsonDecode(utf8.decode(bytes.takeBytes())));
      final sourceTime = DateTime.tryParse(
        data['sourceTimestamp'] as String? ?? '',
      );
      if (data['source'] != 'openstreetmap' ||
          data['license'] != 'ODbL-1.0' ||
          data['coverage'] != 'imported_places_only' ||
          data['attribution'] != '© OpenStreetMap contributors' ||
          sourceTime == null ||
          sourceTime.isAfter(
            DateTime.now().toUtc().add(const Duration(minutes: 5)),
          ) ||
          !RegExp(r'^dhaka-gh11\.1-[0-9a-f]{20}-[0-9a-f]{12}$')
              .hasMatch(data['graphVersion'] as String? ?? '') ||
          !RegExp(r'^dhaka-places-v1-[0-9a-f]{20}$')
              .hasMatch(data['datasetVersion'] as String? ?? '')) {
        throw const ApiFailure('places_unavailable');
      }
      final values = data['items'];
      if (values is! List<Object?> || values.length > 8) {
        throw const ApiFailure('places_unavailable');
      }
      final ids = <String>{};
      final result = <NamedPlace>[];
      for (final raw in values) {
        final v = jsonObject(raw), p = jsonObject(v['point']);
        final id = v['id'],
            en = v['nameEn'],
            bn = v['nameBn'],
            kind = v['kind'];
        if (id is! String ||
            !RegExp(r'^osm:(node|way|relation):[1-9][0-9]{0,19}$')
                .hasMatch(id) ||
            !ids.add(id) ||
            en is! String ||
            en.trim().isEmpty ||
            en.runes.length > 160 ||
            bn is! String ||
            bn.trim().isEmpty ||
            bn.runes.length > 160 ||
            kind is! String ||
            !const [
              'road',
              'education',
              'health',
              'transit',
              'shop',
              'area',
              'place',
            ].contains(kind) ||
            p['latitude'] is! num ||
            p['longitude'] is! num) {
          throw const ApiFailure('places_unavailable');
        }
        final point = GeoPoint(
          (p['latitude']! as num).toDouble(),
          (p['longitude']! as num).toDouble(),
        );
        if (!point.inPilot) throw const ApiFailure('places_unavailable');
        result.add(
          NamedPlace(id: id, nameEn: en, nameBn: bn, kind: kind, point: point),
        );
      }
      return List.unmodifiable(result);
    } catch (_) {
      throw const ApiFailure('places_unavailable');
    } finally {
      deadline.cancel();
      if (identical(_searchAbort, abort)) _searchAbort = null;
      if (!abort.isCompleted) abort.complete();
    }
  }

  @override
  bool get geographic => true;
  @override
  List<Destination> get destinations => const [];
  @override
  List<CommunityReport> get reports => const [];
  @override
  Future<List<RouteOption>> routes(
    Destination destination,
    TravelMode mode,
    DemoScenario scenario,
  ) async => throw const ApiFailure('origin_required');
  @override
  void cancel() {
    final abort = _abort;
    _abort = null;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  @override
  void close() {
    cancel();
    cancelSearch();
    client.close();
  }

  @override
  Future<List<RouteOption>> routesFrom(
    GeoPoint origin,
    Destination destination,
    TravelMode mode,
  ) async {
    final target = destination.point;
    if (!origin.inPilot || target == null || !target.inPilot) {
      throw const ApiFailure('outside_pilot');
    }
    final base = baseUrl;
    if (base == null) throw const ApiFailure('routing_not_configured');
    cancel();
    final abort = Completer<void>();
    _abort = abort;
    final request =
        http.AbortableRequest(
            'POST',
            base.resolve('/v1/routes'),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll({
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode({
            'origin': origin.toJson(),
            'destination': target.toJson(),
            'mode': mode.name,
            'includeReports': true,
          });
    Future<List<RouteOption>> send() async {
      final response = await client.send(request);
      final bytes = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.stream) {
        total += chunk.length;
        if (total > 262144) throw const ApiFailure('invalid_response');
        bytes.add(chunk);
      }
      final data = jsonObject(jsonDecode(utf8.decode(bytes.takeBytes())));
      if (response.statusCode != 200) {
        const codes = {
          'outside_pilot',
          'already_at_destination',
          'route_snap_too_far',
          'route_outside_pilot',
          'route_unavailable',
          'routing_not_configured',
          'routing_busy',
          'routing_version_changed',
          'routing_unavailable',
          'rate_limited',
        };
        final code = data['code'];
        throw ApiFailure(
          code is String && codes.contains(code) ? code : 'routing_unavailable',
          retryable: response.statusCode >= 500 || response.statusCode == 429,
        );
      }
      return decodeGeographicPlan(data, origin, target, mode);
    }

    try {
      return await send().timeout(const Duration(seconds: 12));
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure('routing_unavailable', retryable: true);
    } finally {
      if (identical(_abort, abort)) _abort = null;
      if (!abort.isCompleted) abort.complete();
    }
  }
}

List<RouteOption> decodeGeographicPlan(
  Map<String, Object?> data,
  GeoPoint origin,
  GeoPoint target,
  TravelMode mode, {
  DateTime? at,
}) {
  final now = at ?? DateTime.now().toUtc();
  final graph = jsonString(data, 'graphVersion'),
      risk = jsonString(data, 'riskVersion');
  final generated = jsonDate(data, 'generatedAt'),
      expiry = jsonDate(data, 'expiresAt'),
      source = jsonDate(data, 'sourceTimestamp');
  final reviewed = RegExp(
    r'^reviewed-decay-v1:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(risk);
  final reporting = data['reportRouting'] == null
      ? null
      : jsonObject(data['reportRouting']);
  final status = reporting?['status'];
  if (reporting != null &&
      (reporting['synthetic'] is! bool ||
          !const {
            'available',
            'no_evidence',
            'unavailable',
            'disabled',
            'same_route',
          }.contains(status))) {
    throw const ApiFailure('invalid_response');
  }
  bool matches(Object? value, GeoPoint point) {
    final p = jsonObject(value);
    return (jsonNumber(p, 'latitude') - point.latitude).abs() < 1e-8 &&
        (jsonNumber(p, 'longitude') - point.longitude).abs() < 1e-8;
  }

  if (!RegExp(r'^dhaka-gh11\.1-[a-f0-9]{20}-[a-f0-9]{12}$').hasMatch(graph) ||
      (risk != 'unknown-v1' && !reviewed) ||
      (reviewed && status != 'available' && status != 'same_route') ||
      data['riskLevel'] != 'unknown' ||
      !data.containsKey('evidenceCoverage') ||
      data['evidenceCoverage'] != null ||
      data['source'] != 'openstreetmap' ||
      data['trafficAware'] != false ||
      data['durationModel'] != 'osm_static_speed' ||
      data['license'] != 'ODbL-1.0' ||
      data['attribution'] != '© OpenStreetMap contributors' ||
      data['mode'] != mode.name ||
      !matches(data['origin'], origin) ||
      !matches(data['destination'], target) ||
      generated.isAfter(now.add(const Duration(seconds: 30))) ||
      generated.isBefore(now.subtract(const Duration(minutes: 5))) ||
      !expiry.isAfter(now) ||
      (!reviewed &&
          expiry.difference(generated) != const Duration(minutes: 5)) ||
      (reviewed &&
          (!expiry.isAfter(generated) ||
              expiry.difference(generated) > const Duration(minutes: 2))) ||
      source.isAfter(generated.add(const Duration(seconds: 30)))) {
    throw const ApiFailure('invalid_response');
  }
  final routes = data['routes'];
  if (routes is! List ||
      routes.isEmpty ||
      routes.length > 2 ||
      (!reviewed && routes.length != 1) ||
      (routes.length == 2 && status != 'available')) {
    throw const ApiFailure('invalid_response');
  }
  final result = <RouteOption>[];
  final ids = <String>{};
  for (var routeIndex = 0; routeIndex < routes.length; routeIndex++) {
    final route = jsonObject(routes[routeIndex]), id = jsonString(route, 'id');
    final duration = jsonNumber(route, 'durationSeconds'),
        distance = jsonNumber(route, 'distanceMetres');
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(id) ||
        route['preference'] != (routeIndex == 0 ? 'fastest' : 'reported') ||
        !ids.add(id) ||
        duration <= 0 ||
        duration > 21600 ||
        duration != duration.truncateToDouble() ||
        distance < 1 ||
        distance > 100000) {
      throw const ApiFailure('invalid_response');
    }
    final coordinates = route['points'];
    final fraction = route['reportedEvidenceFraction'];
    if ((reviewed &&
            (fraction is! num ||
                !fraction.isFinite ||
                fraction < 0 ||
                fraction > 1)) ||
        (!reviewed && fraction != null)) {
      throw const ApiFailure('invalid_response');
    }
    if (coordinates is! List ||
        coordinates.length < 2 ||
        coordinates.length > 2000) {
      throw const ApiFailure('invalid_response');
    }
    final points = coordinates.map((value) {
      if (value is! List ||
          value.length != 2 ||
          value[0] is! num ||
          value[1] is! num) {
        throw const ApiFailure('invalid_response');
      }
      return [(value[0] as num).toDouble(), (value[1] as num).toDouble()];
    }).toList();
    final corridor = ApprovedCorridor(
      graphVersion: graph,
      riskVersion: risk,
      points: points,
      validUntil: expiry,
    );
    final geometry = points.map((p) => GeoPoint(p[0], p[1])).toList();
    var length = 0.0;
    for (var index = 1; index < geometry.length; index++) {
      length += geometry[index - 1].distanceTo(geometry[index]);
    }
    if (geometry.first.distanceTo(origin) > 50 ||
        geometry.last.distanceTo(target) > 75 ||
        length < 1 ||
        length > 100000 ||
        (length - distance).abs() >
            (distance * .05 > 100 ? distance * .05 : 100)) {
      throw const ApiFailure('invalid_response');
    }
    result.add(
      RouteOption(
        id: id,
        preference: routeIndex == 0
            ? RoutePreference.fastest
            : RoutePreference.lowerRisk,
        minutes: (duration / 60).ceil(),
        kilometres: (distance / 100).round() / 10,
        coverage: (fraction as num?)?.toDouble(),
        corridor: corridor,
        sourceTimestamp: source,
        syntheticReports: reporting?['synthetic'] == true,
        reportRoutingStatus: status as String?,
      ),
    );
  }
  return result;
}
