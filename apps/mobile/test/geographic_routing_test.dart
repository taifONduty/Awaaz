import 'dart:async';
import 'dart:convert';

import 'package:awaaz/data/draft_store.dart';
import 'package:awaaz/data/geographic_repository.dart';
import 'package:awaaz/domain/account_models.dart';
import 'package:awaaz/domain/device_location.dart';
import 'package:awaaz/domain/models.dart';
import 'package:awaaz/ui/journey_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'report_composer_test.dart' show TestLocationSource, fix;

const origin = GeoPoint(23.76, 90.38), target = GeoPoint(23.765, 90.385);
const destination = Destination(
  'pin',
  'Pinned destination',
  'নির্বাচিত গন্তব্য',
  point: target,
);
Map<String, Object?> payload(DateTime now) => {
  'graphVersion': 'dhaka-gh11.1-${'a' * 20}-${'b' * 12}',
  'riskVersion': 'unknown-v1',
  'riskLevel': 'unknown',
  'evidenceCoverage': null,
  'source': 'openstreetmap',
  'license': 'ODbL-1.0',
  'attribution': '© OpenStreetMap contributors',
  'trafficAware': false,
  'durationModel': 'osm_static_speed',
  'sourceTimestamp': now.subtract(const Duration(hours: 1)).toIso8601String(),
  'generatedAt': now.toIso8601String(),
  'expiresAt': now.add(const Duration(minutes: 5)).toIso8601String(),
  'origin': origin.toJson(),
  'destination': target.toJson(),
  'mode': 'car',
  'routes': [
    {
      'id': '11111111-1111-4111-8111-111111111111',
      'preference': 'fastest',
      'durationSeconds': 300,
      'distanceMetres': origin.distanceTo(target),
      'points': [
        [23.76, 90.38],
        [23.765, 90.385],
      ],
    },
  ],
};

void main() {
  test('real route preserves unknown coverage and rejects stale or displaced geometry', () {
    final now = DateTime.now().toUtc();
    final plan = decodeGeographicPlan(
      payload(now),
      origin,
      target,
      TravelMode.car,
      at: now,
    ).single;
    expect(plan.coverage, isNull);
    expect(plan.corridor!.validUntil, now.add(const Duration(minutes: 5)));
    final reviewed = payload(now)
      ..['riskVersion'] =
          'reviewed-decay-v1:11111111-1111-4111-8111-111111111111'
      ..['expiresAt'] = now.add(const Duration(seconds: 90)).toIso8601String()
      ..['reportRouting'] = {'status': 'available', 'synthetic': true};
    final first = (reviewed['routes'] as List).single as Map<String, Object?>;
    first['reportedEvidenceFraction'] = .25;
    reviewed['routes'] = <Object?>[
      first,
      {
        ...first,
        'id': '22222222-2222-4222-8222-222222222222',
        'preference': 'reported',
        'reportedEvidenceFraction': 0,
      },
    ];
    final choices = decodeGeographicPlan(
      reviewed,
      origin,
      target,
      TravelMode.car,
      at: now,
    );
    expect(choices, hasLength(2));
    expect(choices.last.preference, RoutePreference.lowerRisk);
    expect(choices.last.syntheticReports, isTrue);
    expect(choices.first.coverage, .25);
    expect(
      choices.last.corridor!.validUntil,
      now.add(const Duration(seconds: 90)),
    );
    reviewed['expiresAt'] = now
        .add(const Duration(minutes: 5))
        .toIso8601String();
    expect(
      () => decodeGeographicPlan(
        reviewed,
        origin,
        target,
        TravelMode.car,
        at: now,
      ),
      throwsA(isA<ApiFailure>()),
    );
    final shifted = payload(now);
    (shifted['routes'] as List).single['points'] = [
      [23.77, 90.38],
      [23.765, 90.385],
    ];
    expect(
      () => decodeGeographicPlan(
        shifted,
        origin,
        target,
        TravelMode.car,
        at: now,
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => decodeGeographicPlan(
        payload(now.subtract(const Duration(minutes: 6))),
        origin,
        target,
        TravelMode.car,
        at: now,
      ),
      throwsA(isA<ApiFailure>()),
    );
  });
  test(
    'planning cancellation discards a late GPS fix before any network request',
    () async {
      var requests = 0;
      final source = TestLocationSource(fix(DateTime.now().toUtc()))
        ..held = Completer<DeviceLocation>();
      final repository = GeographicRepository(
        baseUrl: Uri.parse('http://127.0.0.1:3031'),
        client: MockClient((request) async {
          requests++;
          return http.Response(
            jsonEncode(payload(DateTime.now().toUtc())),
            200,
          );
        }),
      );
      final vm = JourneyViewModel(
        repository: repository,
        draftStore: MemoryDraftStore(),
        routingLocations: source,
      );
      final pending = vm.plan(destination);
      vm.cancelPlan();
      source.held!.complete(source.value);
      await pending;
      expect(requests, 0);
      expect(vm.selectedRoute, isNull);
      expect(vm.routeError, 'planning_canceled');
      expect(source.cancellations, greaterThan(0));
      vm.dispose();
    },
  );
  test(
    'an unavailable geographic backend never substitutes fixture routes',
    () async {
      final source = TestLocationSource(fix(DateTime.now().toUtc()));
      final repository = GeographicRepository(
        baseUrl: Uri.parse('http://127.0.0.1:3031'),
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.headers.containsKey('Authorization'), false);
          expect(jsonDecode(request.body), {
            'origin': origin.toJson(),
            'destination': target.toJson(),
            'mode': 'car',
          });
          return http.Response('{"code":"routing_unavailable"}', 503);
        }),
      );
      final vm = JourneyViewModel(
        repository: repository,
        draftStore: MemoryDraftStore(),
        routingLocations: source,
      );
      await vm.plan(destination);
      expect(vm.routeFailed, true);
      expect(vm.routes, isEmpty);
      expect(vm.selectedRoute, isNull);
      expect(vm.routeError, 'routing_unavailable');
      vm.dispose();
    },
  );
}
