import 'dart:async';
import 'dart:convert';

import 'package:awaaz/data/draft_store.dart';
import 'package:awaaz/data/geographic_repository.dart';
import 'package:awaaz/l10n/generated/app_localizations.dart';
import 'package:awaaz/ui/journey_view_model.dart';
import 'package:awaaz/ui/route_change_page.dart';
import 'package:awaaz/ui/route_change_view_model.dart';
import 'package:awaaz/ui/theme.dart';
import 'package:awaaz/ui/trip_monitor_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'geographic_routing_test.dart' show payload, destination;
import 'report_composer_test.dart' show TestLocationSource, fix;
import 'trip_monitor_test.dart' show TestTripPlatform;

void main() {
  late JourneyViewModel journey;
  late TripMonitorViewModel trips;
  late TestTripPlatform platform;
  late TestLocationSource locations;
  late RouteChangeViewModel change;
  setUp(() async {
    var requestCount = 0;
    final repository = GeographicRepository(
      baseUrl: Uri.parse('http://127.0.0.1:3031'),
      client: MockClient((_) async {
        final data = payload(DateTime.now().toUtc());
        final route = (data['routes'] as List).single as Map<String, Object?>;
        route['id'] = (++requestCount == 1)
            ? '11111111-1111-4111-8111-111111111111'
            : '22222222-2222-4222-8222-222222222222';
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    locations = TestLocationSource(fix(DateTime.now().toUtc()));
    journey = JourneyViewModel(
      repository: repository,
      draftStore: MemoryDraftStore(),
      routingLocations: locations,
    );
    await journey.plan(destination);
    platform = TestTripPlatform();
    trips = TripMonitorViewModel(platform: platform, locations: locations);
    await trips.initialize(null);
    await trips.arm(
      journey.selectedRoute!.id,
      journey.selectedRoute!.corridor,
      'en',
    );
    journey.start();
    trips.addListener(() => journey.reconcileRouteChange(trips));
    change = RouteChangeViewModel(journey: journey, trips: trips);
  });
  tearDown(() async {
    // Individual cases may already dispose the comparison to simulate closing it.
    trips.dispose();
    journey.dispose();
    await platform.events.close();
  });

  test('comparison does not replace baseline; lost receipt reconciles after page disposal', () async {
    final oldRoute = journey.selectedRoute,
        oldSession = trips.snapshot.sessionId;
    await change.search();
    expect(change.routes, hasLength(1));
    expect(journey.selectedRoute, same(oldRoute));
    expect(platform.replacements, isEmpty);
    final candidate = change.selected;
    platform.loseReplacementReceipt = true;
    expect(await change.apply('en'), isFalse);
    expect(trips.statusConfirmed, isFalse);
    expect(journey.selectedRoute, same(oldRoute));
    expect(journey.replacementPending, isTrue);
    change.dispose();
    expect(await trips.refresh(), isTrue);
    expect(journey.selectedRoute, same(candidate));
    expect(journey.baselineRevision, 2);
    expect(trips.snapshot.sessionId, oldSession);
    expect(journey.replacementPending, isFalse);
    expect(platform.replacements, hasLength(1));
  });

  test(
    'late GPS after cancellation and account change cannot propose a new route',
    () async {
      locations.held = Completer();
      final pending = change.search();
      change.cancel();
      locations.held!.complete(fix(DateTime.now().toUtc()));
      await pending;
      expect(change.routes, isEmpty);
      expect(journey.baselineRevision, 1);
      locations.held = null;
      await change.search();
      await trips.bindOwner('another-owner');
      expect(await change.apply('en'), isFalse);
      expect(platform.replacements, isEmpty);
      change.dispose();
    },
  );

  testWidgets(
    'large-text Bangla comparison requires both consents before native replacement',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1440);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late BuildContext entry;
      await tester.pumpWidget(
        MaterialApp(
          theme: awaazTheme(true),
          locale: const Locale('bn'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              entry = context;
              return const Scaffold(body: Text('Journey'));
            },
          ),
        ),
      );
      unawaited(
        Navigator.of(entry).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                RouteChangePage(vm: change, mapsEnabled: false, onSos: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final calls = locations.calls;
      await tester.scrollUntilVisible(
        find.byKey(const Key('change-find-routes')),
        250,
        scrollable: find
            .descendant(
              of: find.byType(RouteChangePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('change-find-routes')));
      await tester.pumpAndSettle();
      expect(locations.calls, calls);
      await tester.ensureVisible(
        find.byKey(const Key('change-location-consent')),
      );
      await tester.tap(find.byKey(const Key('change-location-consent')));
      await tester.pumpAndSettle();
      expect(change.selected, isNotNull);
      expect(platform.replacements, isEmpty);
      platform.replacementFailure = 'route_expired';
      await tester.tap(find.byKey(const Key('change-apply-route')));
      await tester.pumpAndSettle();
      expect(platform.replacements, isEmpty);
      await tester.ensureVisible(find.byKey(const Key('change-route-confirm')));
      await tester.tap(find.byKey(const Key('change-route-confirm')));
      await tester.pumpAndSettle();
      expect(platform.replacements, hasLength(1));
      expect(journey.baselineRevision, 1);
      expect(find.byKey(const Key('change-route-failure')), findsOneWidget);
      await change.reconcile();
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      platform.replacementFailure = null;
      await tester.tap(find.byKey(const Key('change-apply-route')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('change-route-confirm')));
      await tester.tap(find.byKey(const Key('change-route-confirm')));
      await tester.pumpAndSettle();
      expect(platform.replacements, hasLength(2));
      expect(journey.baselineRevision, 2);
      expect(find.text('Journey'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      change.dispose();
    },
  );
}
