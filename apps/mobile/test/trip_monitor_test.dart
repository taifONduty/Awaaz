import 'dart:async';

import 'package:awaaz/app.dart';
import 'package:awaaz/data/draft_store.dart';
import 'package:awaaz/data/safety_repository.dart';
import 'package:awaaz/domain/account_models.dart';
import 'package:awaaz/domain/models.dart';
import 'package:awaaz/domain/trip_monitor.dart';
import 'package:awaaz/ui/journey_view_model.dart';
import 'package:awaaz/ui/trip_monitor_view_model.dart';
import 'package:awaaz/ui/trip_monitor_panel.dart';
import 'package:awaaz/l10n/generated/app_localizations.dart';
import 'package:awaaz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'report_composer_test.dart' show TestLocationSource, fix;

ApprovedCorridor corridor({bool synthetic = false, String graph = 'graph-1'}) =>
    ApprovedCorridor(
      graphVersion: graph,
      riskVersion: 'risk-1',
      points: [
        [23.76, 90.38],
        [23.76, 90.39],
      ],
      synthetic: synthetic,
    );

class TestTripPlatform implements TripPlatform {
  final events = StreamController<TripSnapshot>.broadcast(sync: true);
  final starts = <Map<String, Object?>>[];
  final replacements = <Map<String, Object?>>[];
  bool notifications = true, failStart = false, failStop = false;
  bool failBinding = false, failState = false;
  bool loseReplacementReceipt = false;
  String? replacementFailure;
  int bindings = 0;
  String? owner;
  Completer<bool>? notificationDecision;
  Completer<TripSnapshot>? heldBinding;
  Completer<TripSnapshot>? heldStop;
  int streamReads = 0;
  TripSnapshot current = const TripSnapshot();
  @override
  bool get supported => true;
  @override
  Stream<TripSnapshot> get changes {
    streamReads++;
    return events.stream;
  }

  @override
  Future<TripSnapshot> bindOwner(String? value) async {
    bindings++;
    if (failBinding) throw const ApiFailure('monitor_unavailable');
    owner = value;
    if (heldBinding != null) return heldBinding!.future;
    return current = TripSnapshot(ownerId: owner);
  }

  @override
  Future<bool> requestNotifications() async =>
      notificationDecision?.future ?? notifications;
  @override
  Future<TripSnapshot> start(Map<String, Object?> bundle) async {
    starts.add(Map.of(bundle));
    if (failStart) throw const ApiFailure('start_unavailable');
    current = TripSnapshot(
      active: true,
      status: 'waiting',
      ownerId: owner,
      sessionId: bundle['sessionId'] as String,
      routeId: bundle['routeId'] as String,
      revision: bundle['revision'] as int,
    );
    return current;
  }

  @override
  Future<TripSnapshot> state() async {
    if (failState) throw const ApiFailure('monitor_unavailable');
    return current;
  }

  @override
  Future<TripSnapshot> stop() async {
    if (failStop) throw const ApiFailure('stop_unavailable');
    return current =
        await (heldStop?.future ?? Future.value(TripSnapshot(ownerId: owner)));
  }

  @override
  Future<TripSnapshot> acknowledge(String sessionId) async =>
      current = TripSnapshot(
        active: true,
        status: 'tracking',
        ownerId: owner,
        sessionId: sessionId,
        routeId: current.routeId,
        revision: current.revision,
      );
  @override
  Future<TripSnapshot> replace(Map<String, Object?> bundle) async {
    replacements.add(Map.of(bundle));
    if (replacementFailure != null) throw ApiFailure(replacementFailure!);
    current = TripSnapshot(
      active: true,
      status: 'waiting',
      ownerId: owner,
      sessionId: bundle['sessionId'] as String,
      routeId: bundle['routeId'] as String,
      revision: bundle['revision'] as int,
    );
    if (loseReplacementReceipt) throw const ApiFailure('monitor_unavailable');
    return current;
  }
}

class TestCorridorSafetyRepository extends DemoSafetyRepository {
  @override
  Future<List<RouteOption>> routes(
    Destination destination,
    TravelMode mode,
    DemoScenario scenario,
  ) async => [
    RouteOption(
      id: 'route',
      preference: RoutePreference.fastest,
      minutes: 20,
      kilometres: 5.4,
      coverage: 0,
      sourceTimestamp: DateTime.utc(2026, 10, 14),
      corridor: corridor(),
    ),
  ];
}

void main() {
  late TestTripPlatform platform;
  late TestLocationSource locations;
  late TripMonitorViewModel vm;
  setUp(() async {
    platform = TestTripPlatform();
    locations = TestLocationSource(fix(DateTime.now().toUtc()));
    vm = TripMonitorViewModel(platform: platform, locations: locations);
    await vm.initialize('owner-a');
  });
  tearDown(() async {
    vm.dispose();
    await platform.events.close();
  });

  test(
    'preview and synthetic geometry cannot arm production monitoring',
    () async {
      expect(await vm.arm('preview', null, 'en'), isFalse);
      expect(await vm.arm('test', corridor(synthetic: true), 'en'), isFalse);
      final expired = ApprovedCorridor(
        graphVersion: 'graph-1',
        riskVersion: 'risk-1',
        points: [
          [23.76, 90.38],
          [23.76, 90.39],
        ],
        validUntil: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );
      expect(await vm.arm('expired', expired, 'en'), isFalse);
      expect(vm.error, 'route_expired');
      expect(locations.calls, 0);
      expect(platform.starts, isEmpty);
    },
  );
  test('notification denial does not acquire GPS or start a service', () async {
    platform.notifications = false;
    expect(await vm.arm('route', corridor(), 'en'), isFalse);
    expect(vm.error, 'notifications_required');
    expect(locations.calls, 0);
    expect(platform.starts, isEmpty);
  });
  test(
    'unreliable GPS fails before starting and preserves specific error',
    () async {
      locations.failure = 'location_permission';
      expect(await vm.arm('route', corridor(), 'en'), isFalse);
      expect(vm.error, 'location_permission');
      expect(platform.starts, isEmpty);
    },
  );
  test(
    'account change during permission prompt cannot start for a new owner',
    () async {
      platform.notificationDecision = Completer<bool>();
      final pending = vm.arm('route', corridor(), 'en');
      await vm.bindOwner('owner-b');
      platform.notificationDecision!.complete(true);
      expect(await pending, isFalse);
      expect(platform.starts, isEmpty);
      expect(vm.error, isNull);
    },
  );
  test('account change during GPS acquisition discards its result', () async {
    locations.held = Completer();
    final pending = vm.arm('route', corridor(), 'en');
    await Future<void>.delayed(Duration.zero);
    await vm.bindOwner('owner-b');
    locations.held!.complete(fix(DateTime.now().toUtc()));
    expect(await pending, isFalse);
    expect(platform.starts, isEmpty);
  });
  test(
    'ambiguous start reuses only the same complete corridor intent',
    () async {
      platform.failStart = true;
      await vm.arm('route', corridor(), 'en');
      await vm.arm('route', corridor(), 'en');
      expect(platform.starts[0]['sessionId'], platform.starts[1]['sessionId']);
      await vm.arm('route', corridor(graph: 'graph-2'), 'en');
      expect(
        platform.starts[2]['sessionId'],
        isNot(platform.starts[1]['sessionId']),
      );
      expect(platform.starts[2]['graphVersion'], 'graph-2');
    },
  );
  test('acknowledgement preserves baseline; explicit replacement increments revision', () async {
    expect(await vm.arm('route', corridor(), 'en'), isTrue);
    final id = vm.snapshot.sessionId;
    expect(await vm.arm('other', corridor(), 'en'), isFalse);
    expect(vm.error, 'monitor_active');
    expect(await vm.acknowledge(), isTrue);
    expect(vm.snapshot.routeId, 'route');
    expect(vm.snapshot.revision, 1);
    expect(
      await vm.replace('replacement', corridor(graph: 'graph-2'), 'bn'),
      isTrue,
    );
    expect(vm.snapshot.sessionId, id);
    expect(vm.snapshot.revision, 2);
    expect(platform.replacements.single['userApproved'], true);
    platform.heldStop = Completer<TripSnapshot>()..complete(platform.current);
    expect(await vm.stop(), isFalse);
    expect(vm.error, 'stop_unconfirmed');
    expect(vm.snapshot.active, isTrue);
    platform.heldStop = null;
    expect(await vm.stop(), isTrue);
    expect(await vm.arm('route', corridor(), 'en'), isTrue);
    expect(vm.snapshot.sessionId, isNot(id));
  });
  test('late snapshots from another owner cannot expose that trip', () async {
    await vm.bindOwner('owner-b');
    platform.events.add(
      const TripSnapshot(
        active: true,
        ownerId: 'owner-a',
        sessionId: 'private-a',
        status: 'check_in',
      ),
    );
    expect(vm.snapshot.active, isFalse);
    expect(vm.snapshot.sessionId, isNull);
  });
  test(
    'a native notification stop discards the previous start nonce',
    () async {
      expect(await vm.arm('route', corridor(), 'en'), isTrue);
      final previous = vm.snapshot.sessionId;
      platform.events.add(
        const TripSnapshot(ownerId: 'owner-a', reason: 'user_stopped'),
      );
      expect(vm.snapshot.active, isFalse);
      expect(await vm.arm('route', corridor(), 'en'), isTrue);
      expect(vm.snapshot.sessionId, isNot(previous));
    },
  );
  test(
    'disposing during native binding cannot attach a late event listener',
    () async {
      final reads = platform.streamReads;
      platform.heldBinding = Completer<TripSnapshot>();
      final other = TripMonitorViewModel(
        platform: platform,
        locations: locations,
      );
      final initializing = other.initialize('owner-a');
      other.dispose();
      platform.heldBinding!.complete(const TripSnapshot(ownerId: 'owner-a'));
      await initializing;
      expect(platform.streamReads, reads);
    },
  );
  test('unknown native status retries owner binding before arming', () async {
    platform.failBinding = true;
    await vm.bindOwner('owner-b');
    expect(vm.statusConfirmed, isFalse);
    expect(vm.statusFailure, isTrue);
    expect(vm.error, isNull);
    expect(await vm.arm('route', corridor(), 'en'), isFalse);
    expect(platform.starts, isEmpty);
    expect(locations.calls, 0);
    final bindings = platform.bindings;
    platform.failBinding = false;
    expect(await vm.refresh(), isTrue);
    expect(platform.bindings, bindings + 1);
    expect(vm.statusConfirmed, isTrue);
    expect(vm.statusFailure, isFalse);
    expect(await vm.arm('route', corridor(), 'en'), isTrue);
    final session = vm.snapshot.sessionId;
    platform.failState = true;
    expect(await vm.refresh(), isFalse);
    expect(vm.snapshot.active, isTrue);
    expect(vm.snapshot.sessionId, session);
    expect(vm.statusConfirmed, isFalse);
    expect(vm.statusFailure, isTrue);
    platform.failState = false;
    expect(await vm.refresh(), isTrue);
    expect(vm.statusConfirmed, isTrue);
    expect(vm.statusFailure, isFalse);
    expect(vm.snapshot.sessionId, session);
  });
  testWidgets(
    'Bangla check-in panel fits narrow screen with large text and usable controls',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1560);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      vm.snapshot = const TripSnapshot(
        active: true,
        status: 'check_in',
        ownerId: 'owner-a',
        sessionId: 'session',
        routeId: 'route',
        revision: 1,
      );
      platform.current = vm.snapshot;
      await tester.pumpWidget(
        MaterialApp(
          theme: awaazTheme(true),
          locale: const Locale('bn'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(child: TripMonitorPanel(vm: vm)),
          ),
        ),
      );
      platform.events.addError(const ApiFailure('monitor_unavailable'));
      await tester.pumpAndSettle();
      expect(vm.statusConfirmed, isFalse);
      expect(find.byKey(const Key('native-refresh')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('native-monitor-status')))
            .data,
        'পর্যবেক্ষণের অবস্থা জানা যাচ্ছে না',
      );
      await tester.ensureVisible(find.byKey(const Key('native-refresh')));
      await tester.tap(find.byKey(const Key('native-refresh')));
      await tester.pumpAndSettle();
      expect(vm.statusConfirmed, isTrue);
      expect(find.byKey(const Key('native-refresh')), findsNothing);
      expect(find.byKey(const Key('native-acknowledge')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('native-acknowledge')));
      await tester.tap(find.byKey(const Key('native-acknowledge')));
      await tester.pumpAndSettle();
      expect(vm.snapshot.revision, 1);
      expect(vm.snapshot.status, 'tracking');
      expect(tester.takeException(), isNull);

      // The main journey keeps the baseline visible until a native stop receipt.
      // Reuse this existing flow instead of adding a second widget harness.
      final journey = JourneyViewModel(
        repository: TestCorridorSafetyRepository(),
        draftStore: MemoryDraftStore(),
      );
      platform.failBinding = true;
      await tester.pumpWidget(
        AwaazApp(viewModel: journey, tripMonitor: vm, locations: locations),
      );
      await tester.pumpAndSettle();
      expect(find.text('Monitoring status unavailable'), findsOneWidget);
      expect(find.byKey(const Key('native-refresh')), findsOneWidget);
      platform.failBinding = false;
      await tester.tap(find.byKey(const Key('native-refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('native-refresh')), findsNothing);
      await tester.tap(find.byKey(const Key('plan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();
      expect(platform.starts, isEmpty);
      expect(locations.calls, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(journey.phase, JourneyPhase.idle);
      expect(locations.calls, 0);
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('native-arm-confirm')));
      await tester.pumpAndSettle();
      expect(journey.phase, JourneyPhase.active);
      expect(find.byKey(const Key('native-monitor-status')), findsOneWidget);
      expect(find.byKey(const Key('native-stop')), findsNothing);
      final activeSnapshot = platform.current;
      platform.heldBinding = Completer<TripSnapshot>();
      final rebinding = vm.bindOwner(platform.owner);
      await tester.pump();
      expect(vm.statusConfirmed, isFalse);
      expect(journey.phase, JourneyPhase.active);
      platform.heldBinding!.completeError(
        const ApiFailure('monitor_unavailable'),
      );
      await rebinding;
      await tester.pumpAndSettle();
      expect(journey.phase, JourneyPhase.active);
      platform.failStop = true;
      await tester.ensureVisible(find.byKey(const Key('end')));
      await tester.tap(find.byKey(const Key('end')));
      await tester.pumpAndSettle();
      expect(journey.phase, JourneyPhase.active);
      expect(vm.error, 'stop_unavailable');
      platform.failStop = false;
      platform.heldBinding = Completer<TripSnapshot>()
        ..complete(activeSnapshot);
      expect(await vm.refresh(), isTrue);
      platform.heldBinding = null;
      await tester.pumpAndSettle();
      expect(vm.snapshot.sessionId, activeSnapshot.sessionId);
      expect(journey.phase, JourneyPhase.active);
      final tripScroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(tripScroll.maxScrollExtent, greaterThan(0));
      tripScroll.jumpTo(tripScroll.maxScrollExtent);
      platform.current = TripSnapshot(
        active: true,
        status: 'check_in',
        ownerId: platform.owner,
        sessionId: activeSnapshot.sessionId,
        routeId: activeSnapshot.routeId,
        revision: activeSnapshot.revision,
      );
      platform.events.add(platform.current);
      await tester.pumpAndSettle();
      expect(tripScroll.pixels, 0);
      expect(
        find.byKey(const Key('native-acknowledge')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('native-acknowledge')));
      await tester.pumpAndSettle();
      expect(vm.snapshot.revision, activeSnapshot.revision);
      platform.failStop = true;
      await tester.ensureVisible(find.byKey(const Key('end')));
      await tester.tap(find.byKey(const Key('end')));
      await tester.pumpAndSettle();
      expect(journey.phase, JourneyPhase.active);
      expect(vm.snapshot.active, isTrue);
      expect(vm.error, 'stop_unavailable');
      platform.failStop = false;
      platform.heldStop = Completer<TripSnapshot>();
      await tester.ensureVisible(find.byKey(const Key('end')));
      await tester.tap(find.byKey(const Key('end')));
      await tester.pump();
      expect(journey.phase, JourneyPhase.active);
      expect(find.text('Stopping monitoring…'), findsOneWidget);
      platform.heldStop!.complete(TripSnapshot(ownerId: platform.owner));
      await tester.pumpAndSettle();
      expect(journey.phase, JourneyPhase.idle);
      expect(vm.snapshot.active, isFalse);
      expect(find.text('Where to today?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      journey.dispose();
    },
  );
}
