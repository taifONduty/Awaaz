import 'dart:convert';

import 'package:awaaz/data/account_api.dart';
import 'package:awaaz/domain/account_models.dart';
import 'package:awaaz/domain/device_location.dart';
import 'package:awaaz/l10n/generated/app_localizations.dart';
import 'package:awaaz/ui/account_view_model.dart';
import 'package:awaaz/ui/sharing_page.dart';
import 'package:awaaz/ui/sharing_view_model.dart';
import 'package:awaaz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:uuid/uuid.dart';

import 'android_loop_test.dart' show FixtureSessions, checkpoint, settle, tap;

// All consent, access, expiry and revocation requests use the real local API.
// Only coordinates are synthetic; this entry point is never a production entry.
class SharingFixtureLocation implements LocationSource {
  int captures = 0, cancels = 0;
  @override
  Future<DeviceLocation> acquire() async {
    captures++;
    return DeviceLocation(
      latitude: 23.7508,
      longitude: 90.3931,
      accuracy: 8,
      capturedAt: DateTime.now().toUtc(),
      precise: true,
      mocked: true,
    );
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<bool> openAppSettings() async => false;
  @override
  Future<bool> openLocationSettings() async => false;
}

class LostShareAck extends http.BaseClient {
  final inner = http.Client();
  bool drop = true;
  final requests = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final create = request.method == 'POST' && request.url.path == '/v1/shares';
    if (create && request is http.Request) requests.add(request.body);
    final response = await inner.send(request);
    if (create && drop && response.statusCode < 300) {
      drop = false;
      await response.stream.drain<void>();
      throw http.ClientException('Synthetic lost share acknowledgement');
    }
    return response;
  }

  @override
  void close() => inner.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'sharing consent, lost acknowledgement, foreground pause, recipient revoke and stop',
    (tester) async {
      final transport = LostShareAck(), bobTransport = http.Client();
      final fixtures = jsonObject(
        jsonDecode(
          (await bobTransport.get(Uri.parse('http://10.0.2.2:3031/__fixtures')))
              .body,
        ),
      );
      expect(fixtures['synthetic'], true);
      final alice = FixtureSessions(jsonObject(fixtures['alice'])),
          bob = FixtureSessions(jsonObject(fixtures['bob']));
      final aliceApi = AccountApi(
        baseUrl: Uri.parse('http://10.0.2.2:3031'),
        sessions: alice,
        client: transport,
      );
      final bobApi = AccountApi(
        baseUrl: Uri.parse('http://10.0.2.2:3031'),
        sessions: bob,
        client: bobTransport,
      );
      final accounts = AccountViewModel(sessions: alice, repository: aliceApi),
          bobAccounts = AccountViewModel(sessions: bob, repository: bobApi);
      final locations = SharingFixtureLocation();
      final vm = SharingViewModel(
        accounts: accounts,
        repository: aliceApi,
        locations: locations,
        allowMockLocations: true,
      );
      final receiver = SharingViewModel(
        accounts: bobAccounts,
        repository: bobApi,
        locations: SharingFixtureLocation(),
        allowMockLocations: true,
      );
      String? circleId, shareId;
      Future<void> show(SharingViewModel model, {String locale = 'en'}) async {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('$locale-${identical(model, vm)}'),
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: awaazTheme(locale == 'bn'),
            home: SharingPage(vm: model),
          ),
        );
        await settle(tester);
      }

      try {
        await accounts.initialize();
        await bobAccounts.initialize();
        // Make reruns terminal without mutating unrelated accounts or fixtures.
        final previous = await aliceApi.currentShare();
        if (previous?.status == 'active') {
          await aliceApi.stopShare(previous!.id);
        }
        final circle = await aliceApi.createCircle(
          const Uuid().v4(),
          'Evening commute',
        );
        circleId = circle.id;
        final invite = await aliceApi.invite(
          const Uuid().v4(),
          circle.id,
          bob.userId!,
        );
        await bobApi.accept(invite.id, invite.token);
        await accounts.refresh();
        await show(vm);
        await tap(tester, find.byKey(Key('share-circle-${circle.id}')));
        await tap(tester, find.byKey(Key('share-person-${bob.userId}')));
        await checkpoint('sharing-consent');
        await tap(tester, find.byKey(const Key('share-start')));
        expect(vm.pendingConsent, true);
        expect(locations.captures, 0);
        shareId = (await aliceApi.currentShare())!.id;
        // A current-state read can discover the committed share before its
        // consent receipt is resolved. The exact retry must remain reachable.
        await vm.refresh();
        await settle(tester);
        expect(vm.active, true);
        await tap(tester, find.byKey(const Key('share-start')));
        expect(vm.pendingConsent, false);
        expect(vm.own!.id, shareId);
        expect(transport.requests.length, 2);
        expect(transport.requests[0], transport.requests[1]);
        expect(vm.error, isNull);
        expect(vm.own!.sequence, 1);
        expect(vm.updating, true);
        await checkpoint('sharing-active');
        final captures = locations.captures;
        vm.setForeground(false);
        expect(vm.updating, false);
        vm.setForeground(true);
        await settle(tester);
        expect(vm.updating, false);
        expect(locations.captures, captures);

        await receiver.refresh();
        expect(receiver.incoming.any((trip) => trip.id == shareId), true);
        await show(receiver);
        await tester.scrollUntilVisible(
          find.byKey(Key('shared-trip-$shareId')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tap(tester, find.byKey(Key('shared-trip-$shareId')));
        expect(receiver.position, isNotNull);
        await tester.drag(find.byType(ListView), const Offset(0, -350));
        await settle(tester);
        expect(find.byKey(const Key('share-location-fresh')), findsOneWidget);
        await checkpoint('sharing-recipient');
        await vm.revoke(bob.userId!);
        await receiver.view(shareId);
        await tester.pump();
        expect(receiver.position, isNull);
        expect(find.byKey(const Key('share-location-fresh')), findsNothing);
        vm.setForeground(true);
        await show(vm, locale: 'bn');
        await tap(tester, find.byKey(const Key('share-stop')));
        await tap(
          tester,
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'শেয়ার বন্ধ করুন'),
          ),
        );
        expect(vm.own!.status, 'stopped');
        expect(vm.updating, false);
        final first = jsonObject(jsonDecode(transport.requests.first));
        final replay = await aliceApi.createShare(
          jsonString(first, 'clientRequestId'),
          circle.id,
          [bob.userId!],
          1800,
        );
        expect(replay.id, shareId);
        expect(replay.status, 'stopped');
        await checkpoint('sharing-stopped-bn');
        alice.switchTo(null);
        expect(vm.own, isNull);
        expect(vm.circle, isNull);
        expect(vm.incoming, isEmpty);
        expect(vm.position, isNull);
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        vm.dispose();
        receiver.dispose();
        alice.switchTo(jsonObject(fixtures['alice']));
        if (shareId != null) await aliceApi.stopShare(shareId);
        if (circleId != null) await aliceApi.closeCircle(circleId);
        accounts.dispose();
        bobAccounts.dispose();
        await alice.changes.close();
        await bob.changes.close();
        transport.close();
        bobTransport.close();
      }
    },
  );
}
