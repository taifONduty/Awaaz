import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:awaaz/app.dart';
import 'package:awaaz/data/account_api.dart';
import 'package:awaaz/data/draft_store.dart';
import 'package:awaaz/data/safety_repository.dart';
import 'package:awaaz/data/supabase_sessions.dart';
import 'package:awaaz/data/command_journal.dart';
import 'package:awaaz/data/private_values.dart';
import 'package:awaaz/data/device_location_source.dart';
import 'package:awaaz/ui/report_composer_view_model.dart';
import 'package:geolocator/geolocator.dart';
import 'package:awaaz/domain/account_models.dart';
import 'package:awaaz/domain/models.dart';
import 'package:awaaz/ui/account_view_model.dart';
import 'package:awaaz/ui/journey_view_model.dart';
import 'package:awaaz/data/android_trip_platform.dart';
import 'package:awaaz/domain/trip_monitor.dart';
import 'package:awaaz/ui/trip_monitor_view_model.dart';

// Synthetic sessions are injectable only from this test entry point.
class FixtureSessions implements SessionRepository {
  FixtureSessions(this.identity);
  Map<String, Object?>? identity;
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  String? get userId => identity?['id'] as String?;
  @override
  Stream<String?> get userChanges => changes.stream;
  void switchTo(Map<String, Object?>? value) {
    identity = value;
    changes.add(userId);
  }

  @override
  Future<String?> accessToken({bool forceRefresh = false}) async =>
      identity?['token'] as String?;
  @override
  Future<void> requestCode(String phone) async =>
      throw const ApiFailure('auth_unavailable');
  @override
  Future<void> verifyCode(String phone, String code) async =>
      throw const ApiFailure('auth_unavailable');
  @override
  Future<void> signOut() async => switchTo(null);
}

// Apply a real HTTP write, then discard its acknowledgement once. This exercises
// the dangerous commit/response gap rather than merely failing before send.
class LostAckClient extends http.BaseClient {
  LostAckClient(this.inner);
  final http.Client inner;
  bool dropReportAck = false;
  final reportIds = <String>[];
  final receiptIds = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' &&
        request.url.path.startsWith('/v1/report-requests/')) {
      receiptIds.add(request.url.pathSegments.last);
    }
    final isReport =
        request.method == 'POST' && request.url.path == '/v1/reports';
    if (isReport && request is http.Request) {
      reportIds.add(
        jsonString(jsonObject(jsonDecode(request.body)), 'clientRequestId'),
      );
    }
    final response = await inner.send(request);
    if (isReport &&
        dropReportAck &&
        response.statusCode >= 200 &&
        response.statusCode < 300) {
      dropReportAck = false;
      await response.stream.drain<void>();
      throw http.ClientException('SYNTHETIC dropped acknowledgement');
    }
    return response;
  }

  @override
  void close() => inner.close();
}

SecureDraftStore fixtureDraftStore() => SecureDraftStore(
  key: 'awaaz.test.preview.drafts.encrypted.v1',
  clearLegacy: false,
);

Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 40),
  );
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> checkpoint(String name) async {
  final base = Uri.parse(
    const String.fromEnvironment(
      'AWAAZ_FIXTURE_URL',
      defaultValue: 'http://10.0.2.2:3031',
    ),
  );
  final client = http.Client();
  try {
    final response = await client
        .post(
          base.resolve('/__fixtures/checkpoint'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'name': name}),
        )
        .timeout(const Duration(seconds: 40));
    expect(response.statusCode, 200);
  } finally {
    client.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  var coldPhase = false;
  testWidgets(
    'a force-stopped native monitor is interrupted and never resumes itself',
    (tester) async {
      final client = http.Client();
      try {
        final metadata = await client.get(
          Uri.parse('http://10.0.2.2:3031/__fixtures'),
        );
        coldPhase =
            jsonObject(jsonDecode(metadata.body))['restartRequestId'] != null;
        final state = await const AndroidTripPlatform().bindOwner(null);
        expect(state.active, isFalse);
        if (coldPhase) expect(state.status, 'interrupted');
        await const AndroidTripPlatform().stop();
      } finally {
        client.close();
      }
    },
  );
  testWidgets(
    'Android encrypted session storage preserves ordering and survives adapter recreation',
    (tester) async {
      final storage = SecureSessionStorage(key: 'awaaz.test.session.synthetic');
      await storage.initialize();
      await storage.persistSession('{"synthetic":true}');
      final reopened = SecureSessionStorage(key: storage.key);
      expect(await reopened.accessToken(), '{"synthetic":true}');
      final writing = storage.persistSession('{"synthetic":"replaced"}');
      final deleting = storage.removePersistedSession();
      await Future.wait([writing, deleting]);
      expect(await reopened.hasAccessToken(), false);
    },
  );
  testWidgets(
    'Android journey, route back, Bangla and local draft smoke cycle',
    (tester) async {
      final draftStore = fixtureDraftStore();
      await draftStore.write([]);
      final vm = JourneyViewModel(
        repository: DemoSafetyRepository(),
        draftStore: draftStore,
      );
      await tester.pumpWidget(AwaazApp(viewModel: vm));
      await settle(tester);

      await tester.pump();
      await checkpoint('01-explore-android');
      await tap(tester, find.byKey(const Key('plan')));
      expect(find.text('Choose your route'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Where to today?'), findsOneWidget);
      await tap(tester, find.byKey(const Key('plan')));
      await tap(tester, find.byKey(const Key('start')));
      expect(vm.phase, JourneyPhase.active);
      await checkpoint('02-journey-android');
      await tap(tester, find.byKey(const Key('deviation')));
      expect(vm.phase, JourneyPhase.checkIn);
      await tap(tester, find.byKey(const Key('accept-detour')));
      expect(vm.baselineRevision, 2);
      await tap(tester, find.byKey(const Key('end')));
      expect(vm.phase, JourneyPhase.idle);
      await tap(tester, find.byKey(const Key('language')));
      await checkpoint('03-bangla-android');
      expect(tester.takeException(), isNull);
      await tap(tester, find.byKey(const Key('language')));
      await tap(tester, find.text('Community'));
      await tap(tester, find.text('Report an incident'));
      await tester.enterText(
        find.byKey(const Key('report-place')),
        'SYNTHETIC TEST: Farmgate',
      );
      await tester.enterText(
        find.byKey(const Key('report-description')),
        'SYNTHETIC TEST: footpath obstruction fixture.',
      );
      await tap(tester, find.byKey(const Key('save-draft')));
      expect(vm.drafts, isEmpty);
      await tap(tester, find.byKey(const Key('draft-consent')));
      await tap(tester, find.byKey(const Key('save-draft')));
      expect(vm.drafts, hasLength(1));
      expect(await fixtureDraftStore().read(), hasLength(1));
      await tap(tester, find.text('Delete local drafts'));
      await tap(tester, find.text('Delete'));
      expect(await fixtureDraftStore().read(), isEmpty);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const Key('plan')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    },
  );
  testWidgets(
    'Android widgets use real local SQL for reports and consented Circle membership',
    (tester) async {
      final base = Uri.parse(
        const String.fromEnvironment(
          'AWAAZ_FIXTURE_URL',
          defaultValue: 'http://10.0.2.2:3031',
        ),
      );
      expect(['10.0.2.2', '127.0.0.1', 'localhost'], contains(base.host));
      final client = LostAckClient(http.Client());
      final response = await client
          .get(base.resolve('/__fixtures'))
          .timeout(const Duration(seconds: 20));
      expect(response.statusCode, 200);
      final fixtures = jsonObject(jsonDecode(response.body));
      expect(fixtures['synthetic'], true);
      final alice = jsonObject(fixtures['alice']),
          bob = jsonObject(fixtures['bob']),
          outsider = jsonObject(fixtures['outsider']);
      final sessions = FixtureSessions(alice);
      final api = AccountApi(baseUrl: base, sessions: sessions, client: client);
      CommandJournal fixtureJournal() => CommandJournal(
        values: const SecurePrivateValues(),
        namespace: 'android-integration-fixtures',
      );
      final accounts = AccountViewModel(
        sessions: sessions,
        repository: api,
        journal: fixtureJournal(),
      );
      final journey = JourneyViewModel(
        repository: DemoSafetyRepository(),
        draftStore: MemoryDraftStore(),
      );
      await accounts.initialize();
      expect(accounts.error, isNull);
      expect(accounts.account?.profile?.displayName, 'Fixture Alice');
      final restartId = fixtures['restartRequestId'];
      expect(accounts.reports, hasLength(restartId is String ? 2 : 1));
      expect(accounts.events, hasLength(restartId is String ? 0 : 1));
      if (restartId is String) {
        // This branch runs only after the host force-stops the previous process.
        expect(accounts.pendingWrites.single.id, restartId);
        final before = (await api.reports()).items;
        expect(before, hasLength(2));
        await tester.pumpWidget(
          AwaazApp(viewModel: journey, accountViewModel: accounts),
        );
        await settle(tester);
        await tap(tester, find.byKey(const Key('account')));
        await tap(tester, find.byKey(Key('retry-write-$restartId')));
        expect(accounts.error, isNull);
        expect(accounts.pendingWrites, isEmpty);
        expect(
          (await api.reports()).items.map((item) => item.id).toSet(),
          before.map((item) => item.id).toSet(),
        );
        expect(client.reportIds, isEmpty);
        expect(client.receiptIds.single, restartId);
        await tap(tester, find.byKey(const Key('account-tab-reports')));
        await checkpoint('08-report-after-process-restart');
        await tester.pumpWidget(const SizedBox());
        accounts.dispose();
        journey.dispose();
        await sessions.changes.close();
        client.close();
        return;
      }
      await tester.pumpWidget(
        AwaazApp(viewModel: journey, accountViewModel: accounts),
      );
      await settle(tester);
      await tap(tester, find.text('Community'));
      expect(
        find.byKey(Key('published-event-${accounts.events.single.id}')),
        findsOneWidget,
      );
      expect(find.text(fixtures['publicSummary'] as String), findsOneWidget);
      expect(
        find.text(
          'Construction blocks part of the footpath near the crossing.',
        ),
        findsNothing,
      );
      await checkpoint('04-community-published-sql');
      await tap(tester, find.text('Circle'));
      expect(
        find.text('No Circles yet. Invite someone you trust.'),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const Key('account')));
      await checkpoint('04-account-local-sql');
      await tap(tester, find.byKey(const Key('account-tab-circles')));
      await tester.enterText(
        find.byKey(const Key('circle-name')),
        'Emulator test family',
      );
      await tap(tester, find.byKey(const Key('create-circle')));
      expect(accounts.error, isNull);
      final circleId = accounts.circles.single.id;
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tap(tester, find.byKey(Key('overview-circle-$circleId')));
      expect(find.byKey(const Key('invite-recipient')), findsOneWidget);
      await checkpoint('04-circle-overview-detail');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(accounts.detail, isNull);
      expect(find.byKey(Key('overview-circle-$circleId')), findsOneWidget);
      await tap(tester, find.byKey(const Key('account')));
      await tap(tester, find.byKey(const Key('account-tab-circles')));
      await tap(tester, find.byKey(Key('circle-$circleId')));
      await tester.ensureVisible(find.byKey(const Key('invite-recipient')));
      await tester.enterText(
        find.byKey(const Key('invite-recipient')),
        bob['id']! as String,
      );
      await tap(tester, find.byKey(const Key('invite-member')));
      expect(accounts.error, isNull);
      expect(accounts.createdInvite, isNotNull);
      final invitation = accounts.createdInvite!;
      sessions.switchTo(outsider);
      expect(accounts.detail, isNull);
      expect(accounts.createdInvite, isNull);
      await settle(tester);
      expect(accounts.circles, isEmpty);
      await expectLater(
        api.circle(circleId),
        throwsA(
          isA<ApiFailure>().having((error) => error.code, 'code', 'not_found'),
        ),
      );
      await expectLater(
        api.accept(invitation.id, invitation.token),
        throwsA(isA<ApiFailure>()),
      );
      sessions.switchTo(bob);
      await settle(tester);
      expect(accounts.invitations, hasLength(1));
      expect(accounts.circles, isEmpty);
      await tap(tester, find.byKey(Key('accept-${invitation.id}')));
      await tester.enterText(
        find.byKey(const Key('accept-invite-code')),
        invitation.token,
      );
      await tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      expect(accounts.error, isNull);
      expect(accounts.circles.single.id, circleId);
      await tap(tester, find.byKey(Key('circle-$circleId')));
      expect(accounts.detail!.members, hasLength(2));
      await checkpoint('05-circle-consented-local-sql');
      expect(await accounts.removeMember(bob['id']! as String), isTrue);
      await settle(tester);
      expect(accounts.circles, isEmpty);
      await expectLater(api.circle(circleId), throwsA(isA<ApiFailure>()));
      sessions.switchTo(alice);
      await settle(tester);
      await tap(tester, find.byKey(const Key('account-tab-reports')));
      await tap(tester, find.byKey(Key('withdraw-${fixtures['reportId']}')));
      await tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      expect(accounts.reports, isEmpty);
      expect(accounts.events, isEmpty);
      client.dropReportAck = true;
      expect(
        await accounts.submitReport(
          ReportCategory.obstruction,
          'SYNTHETIC TEST: observable road obstruction fixture.',
          23.76,
          90.38,
        ),
        isFalse,
      );
      final saved = accounts.pendingWrites.single;
      expect((await api.reports()).items.single.status, 'pending');
      await settle(tester);
      await checkpoint('07-saved-report-lost-ack');
      await tester.pumpWidget(const SizedBox());
      accounts.dispose();
      final restored = AccountViewModel(
        sessions: sessions,
        repository: api,
        journal: fixtureJournal(),
      );
      await restored.initialize();
      expect(restored.pendingWrites.single.id, saved.id);
      expect(client.reportIds, hasLength(1));
      await tester.pumpWidget(
        AwaazApp(viewModel: journey, accountViewModel: restored),
      );
      await settle(tester);
      await tap(tester, find.byKey(const Key('account')));
      await tap(tester, find.byKey(Key('retry-write-${saved.id}')));
      expect(restored.pendingWrites, isEmpty);
      expect(client.reportIds.toSet(), {saved.id});
      expect(restored.reports, hasLength(1));
      expect(restored.reports.single.status, 'pending');
      expect(restored.events, isEmpty);
      await tap(tester, find.byKey(const Key('account-tab-reports')));
      await checkpoint('06-private-report-pending-local-sql');
      client.dropReportAck = true;
      expect(
        await restored.submitReport(
          ReportCategory.lighting,
          'SYNTHETIC TEST: cold process restart recovery fixture.',
          23.76,
          90.38,
        ),
        isFalse,
      );
      final coldRequest = restored.pendingWrites.single;
      expect((await api.reports()).items, hasLength(2));
      final marker = await client
          .post(
            base.resolve('/__fixtures/restart'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'reportRequestId': coldRequest.id}),
          )
          .timeout(const Duration(seconds: 20));
      expect(marker.statusCode, 200);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      restored.dispose();
      journey.dispose();
      await sessions.changes.close();
      client.close();
    },
  );
  testWidgets(
    'native location capture and explicit consent submit a private report through real SQL',
    (tester) async {
      final base = Uri.parse('http://10.0.2.2:3031'), client = http.Client();
      final metadata = await client.get(base.resolve('/__fixtures'));
      final fixtures = jsonObject(jsonDecode(metadata.body));
      final sessions = FixtureSessions(jsonObject(fixtures['alice']));
      final api = AccountApi(baseUrl: base, sessions: sessions, client: client);
      final accounts = AccountViewModel(
        sessions: sessions,
        repository: api,
        journal: CommandJournal(
          values: const SecurePrivateValues(),
          namespace: 'android-location-fixture',
        ),
      );
      await accounts.initialize();
      final before = (await api.reports()).items.map((item) => item.id).toSet();
      final source = GeolocatorLocationSource();
      final journey = JourneyViewModel(
        repository: DemoSafetyRepository(),
        draftStore: MemoryDraftStore(),
      );
      await tester.pumpWidget(
        AwaazApp(
          viewModel: journey,
          accountViewModel: accounts,
          locations: source,
          composerFactory: (account, locations) => ReportComposerViewModel(
            accounts: account,
            locations: locations,
            allowMockLocations: true,
          ),
        ),
      );
      await settle(tester);
      final granted = await client
          .post(
            base.resolve('/__fixtures/location'),
            headers: {'Content-Type': 'application/json'},
            body: '{}',
          )
          .timeout(const Duration(seconds: 30));
      expect(granted.statusCode, 200);
      expect(await Geolocator.checkPermission(), LocationPermission.whileInUse);
      await tap(tester, find.byKey(const Key('account')));
      await tap(tester, find.byKey(const Key('account-tab-reports')));
      await tap(tester, find.byKey(const Key('compose-open')));
      const description = 'SYNTHETIC TEST: native GPS road-condition fixture.';
      await tester.enterText(
        find.byKey(const Key('compose-description')),
        description,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.byKey(const Key('compose-locate')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('compose-locate')));
      await tester.pump(const Duration(milliseconds: 100));
      final dialog = await client
          .post(
            base.resolve('/__fixtures/location-dialog'),
            headers: {'Content-Type': 'application/json'},
            body: '{}',
          )
          .timeout(const Duration(seconds: 25));
      expect(dialog.statusCode, 200);
      await settle(tester);
      expect(find.text('Current location captured'), findsOneWidget);
      final submit = find.descendant(
        of: find.byKey(const Key('compose-submit')),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(
        (await api.reports()).items.map((item) => item.id).toSet(),
        before,
      );
      await checkpoint('09-native-location-composer');
      await tap(tester, find.byKey(const Key('compose-consent')));
      await tap(tester, find.byKey(const Key('compose-submit')));
      expect(accounts.error, isNull);
      final submitted = accounts.reports.singleWhere(
        (item) => item.description == description,
      );
      expect(submitted.latitude, closeTo(23.76, 0.00001));
      expect(submitted.longitude, closeTo(90.38, 0.00001));
      expect(submitted.status, 'pending');
      expect(accounts.events, isEmpty);
      await checkpoint('10-native-composer-private-receipt');
      expect(await accounts.withdrawReport(submitted.id), isTrue);
      expect(
        (await api.reports()).items.map((item) => item.id).toSet(),
        before,
      );
      await tester.pumpWidget(const SizedBox());
      accounts.dispose();
      journey.dispose();
      await source.cancel();
      await sessions.changes.close();
      client.close();
    },
  );
  testWidgets(
    'native foreground service detects sustained departure with the screen asleep',
    (tester) async {
      final base = Uri.parse('http://10.0.2.2:3031'), client = http.Client();
      Future<Map<String, Object?>> tripFixture(String action) async {
        final response = await client
            .post(
              base.resolve('/__fixtures/trip'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'action': action}),
            )
            .timeout(const Duration(seconds: 80));
        expect(response.statusCode, 200, reason: response.body);
        return jsonObject(jsonDecode(response.body));
      }

      final locations = GeolocatorLocationSource();
      final trips = TripMonitorViewModel(
        platform: const AndroidTripPlatform(),
        locations: locations,
        allowFixtures: true,
      );
      final journey = JourneyViewModel(
        repository: DemoSafetyRepository(),
        draftStore: MemoryDraftStore(),
      );
      await tester.pumpWidget(
        AwaazApp(viewModel: journey, locations: locations, tripMonitor: trips),
      );
      await settle(tester);
      await tripFixture('prepare');
      final corridor = ApprovedCorridor(
        graphVersion: 'synthetic-graph-1',
        riskVersion: 'synthetic-risk-1',
        points: [
          [23.76, 90.379],
          [23.76, 90.39],
        ],
        synthetic: true,
      );
      expect(
        await trips.arm('synthetic-native-route', corridor, 'en'),
        isTrue,
        reason: trips.error,
      );
      await tripFixture('onroute');
      await trips.refresh();
      expect(trips.snapshot.status, 'tracking');
      final session = trips.snapshot.sessionId;
      final result = await tripFixture('trace');
      await settle(tester);
      await trips.refresh();
      expect(result['screenOff'], true);
      expect(result['checkInNotification'], true);
      expect(trips.snapshot.status, 'check_in');
      expect(trips.snapshot.alertCount, 1);
      expect(trips.snapshot.sessionId, session);
      expect(trips.snapshot.routeId, 'synthetic-native-route');
      expect(trips.snapshot.revision, 1);
      await settle(tester);
      await checkpoint('12-native-background-check-in');
      await tap(tester, find.byKey(const Key('native-acknowledge')));
      expect(trips.snapshot.routeId, 'synthetic-native-route');
      expect(trips.snapshot.revision, 1);
      expect(
        await trips.replace(
          'synthetic-approved-detour',
          ApprovedCorridor(
            graphVersion: 'synthetic-graph-1',
            riskVersion: 'synthetic-risk-1',
            synthetic: true,
            points: [
              [23.7625, 90.379],
              [23.7625, 90.39],
            ],
          ),
          'en',
        ),
        isTrue,
      );
      expect(trips.snapshot.sessionId, session);
      expect(trips.snapshot.revision, 2);
      final stopped = await tripFixture('notification-stop');
      expect(stopped['notificationStop'], true);
      await settle(tester);
      await trips.refresh();
      expect(trips.snapshot.active, isFalse);
      // Phase one deliberately leaves a real service armed for the process-kill test.
      if (!coldPhase) {
        expect(
          await trips.arm('synthetic-native-route', corridor, 'en'),
          isTrue,
        );
        expect(trips.snapshot.sessionId, isNot(session));
      }
      await tester.pumpWidget(const SizedBox());
      trips.dispose();
      journey.dispose();
      await locations.cancel();
      client.close();
    },
  );
}
