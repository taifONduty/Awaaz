import 'dart:convert';

import 'package:awaaz/data/account_api.dart';
import 'package:awaaz/data/android_sharing_platform.dart';
import 'package:awaaz/data/device_location_source.dart';
import 'package:awaaz/domain/account_models.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real native capture uploads with the screen off; notification stop is remotely acknowledged',
    (tester) async {
      final client = http.Client();
      final fixture = jsonObject(
        jsonDecode(
          (await client.get(Uri.parse('http://10.0.2.2:3031/__fixtures'))).body,
        ),
      );
      expect(fixture['synthetic'], true);
      final alice = FixtureSessions(jsonObject(fixture['alice'])),
          bob = FixtureSessions(jsonObject(fixture['bob']));
      final api = AccountApi(
        baseUrl: Uri.parse('http://10.0.2.2:3031'),
        sessions: alice,
        client: client,
      );
      final recipient = AccountApi(
        baseUrl: Uri.parse('http://10.0.2.2:3031'),
        sessions: bob,
        client: client,
      );
      const platform = AndroidSharingPlatform();
      final accounts = AccountViewModel(sessions: alice, repository: api);
      SharingViewModel? sharing;
      String? circleId, shareId;
      Future<Map<String, Object?>> action(String action, {String? id}) async {
        final response = await client
            .post(
              Uri.parse('http://10.0.2.2:3031/__fixtures/share-trip'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'action': action, 'shareId': ?id}),
            )
            .timeout(const Duration(seconds: 85));
        expect(response.statusCode, 200, reason: response.body);
        final data = jsonObject(jsonDecode(response.body));
        expect(data['synthetic'], true);
        return data;
      }

      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(child: Text('Native sharing transport diagnostic')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final preparedDevice = await client.post(
          Uri.parse('http://10.0.2.2:3031/__fixtures/trip'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'action': 'prepare'}),
        );
        expect(preparedDevice.statusCode, 200);
        await accounts.initialize();
        await platform.bindOwner(alice.userId);
        final previous = await api.currentShare();
        if (previous != null) await api.stopShare(previous.id);
        final circle = await api.createCircle(
          const Uuid().v4(),
          'Native commute sharing',
        );
        circleId = circle.id;
        final invite = await api.invite(
          const Uuid().v4(),
          circle.id,
          bob.userId!,
        );
        await recipient.accept(invite.id, invite.token);
        final share = await api.createShare(const Uuid().v4(), circle.id, [
          bob.userId!,
        ], 900);
        shareId = share.id;
        final prepared = await platform.prepare(
          alice.userId!,
          share.id,
          api.sharingOrigin,
        );
        expect(prepared.credentialHash, matches(RegExp(r'^[0-9a-f]{64}$')));
        await accounts.refresh();
        sharing = SharingViewModel(
          accounts: accounts,
          repository: api,
          locations: GeolocatorLocationSource(),
          native: platform,
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: awaazTheme(false),
            home: SharingPage(vm: sharing),
          ),
        );
        await sharing.refresh();
        await settle(tester);
        // Begin with the actual foreground publisher, then hand it over.
        await tap(tester, find.byKey(const Key('share-updates')));
        expect(sharing.error, isNull);
        expect(sharing.updating, true);
        expect(sharing.own!.sequence, greaterThanOrEqualTo(1));
        final backgroundButton = find.byKey(const Key('share-background'));
        await tester.ensureVisible(backgroundButton);
        await tap(tester, backgroundButton);
        expect(find.byKey(const Key('share-background-agree')), findsOneWidget);
        await tap(tester, find.text('Cancel'));
        expect((await api.shareDevice(share.id)).status, 'unbound');
        expect((await platform.state()).active, false);
        await tap(tester, backgroundButton);
        await tap(tester, find.byKey(const Key('share-background-agree')));
        expect(sharing.error, isNull);
        expect(sharing.backgroundActive, true);
        expect(sharing.updating, false);
        final active = await platform.state();
        expect(active.active, true);
        expect(active.shareId, share.id);
        expect((await api.currentShare())!.expiresAt, share.expiresAt);
        // Public pause and fresh consent to resume preserve the same binding.
        final updates = find.byKey(const Key('share-updates'));
        await tester.ensureVisible(updates);
        await tap(tester, updates);
        expect((await platform.state()).phase, 'paused');
        expect(sharing.backgroundActive, false);
        await tap(tester, updates);
        await tap(tester, find.byKey(const Key('share-background-agree')));
        expect(sharing.error, isNull);
        expect(sharing.backgroundActive, true);
        await checkpoint('native-sharing-active');
        final background = await action('background-fix', id: share.id);
        expect(background['screenOff'], true);
        expect(background['serverPositionWhileAsleep'], true);
        expect(background['nativeForeground'], true);
        expect(background['sameProcess'], true);
        final live = await recipient.sharedTrip(share.id);
        expect(live.position, isNotNull);
        expect(live.position!.latitude, closeTo(23.76234, .00001));
        expect(live.position!.longitude, closeTo(90.38123, .00001));
        expect(live.freshness, 'fresh');
        final sleepingState = await platform.state();
        expect(sleepingState.active, true);
        final stopped = await action('notification-stop', id: share.id);
        expect(stopped['notificationAction'], true);
        expect(stopped['remoteStopped'], true);
        expect(stopped['nativeInactive'], true);
        expect(stopped['lostStopAck'], true);
        expect(stopped['stopReplayed'], true);
        expect(stopped['sameProcess'], true);
        final until = DateTime.now().add(const Duration(seconds: 15));
        var state = await platform.state();
        while (state.phase == 'stopping' && DateTime.now().isBefore(until)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          state = await platform.state();
        }
        expect(state.active, false);
        expect(state.phase, 'stopped');
        expect(await api.currentShare(), isNull);
        await expectLater(
          recipient.sharedTrip(share.id),
          throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'not_found')),
        );
        final oldGrant = await api.bindShareDevice(
          share.id,
          prepared.credentialHash,
        );
        expect(oldGrant.status, 'stopped');
        await expectLater(
          platform.activate(prepared, oldGrant),
          throwsA(isA<ApiFailure>()),
        );
        await checkpoint('native-sharing-stopped');
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('Stopped sharing'))),
        );
        sharing.dispose();
        sharing = null;
        // A new consent gets a new native secret. Logout stops its capture and
        // the same scoped outbox can erase it after the local account is gone.
        final next = await api.createShare(const Uuid().v4(), circle.id, [
          bob.userId!,
        ], 900);
        shareId = next.id;
        final nextPrepared = await platform.prepare(
          alice.userId!,
          next.id,
          api.sharingOrigin,
        );
        expect(nextPrepared.credentialHash, isNot(prepared.credentialHash));
        final nextGrant = await api.bindShareDevice(
          next.id,
          nextPrepared.credentialHash,
        );
        expect((await platform.activate(nextPrepared, nextGrant)).active, true);
        final signedOut = await platform.bindOwner(null);
        expect(signedOut.active, false);
        expect(signedOut.shareId, isNull);
        final stopUntil = DateTime.now().add(const Duration(seconds: 20));
        while (await api.currentShare() != null &&
            DateTime.now().isBefore(stopUntil)) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        expect(await api.currentShare(), isNull);
        expect((await platform.state()).active, false);
        expect(tester.takeException(), isNull);
      } finally {
        await action('wake');
        await platform.bindOwner(null);
        if (shareId != null) await api.stopShare(shareId);
        if (circleId != null) await api.closeCircle(circleId);
        await tester.pumpWidget(const SizedBox.shrink());
        sharing?.dispose();
        accounts.dispose();
        await alice.changes.close();
        await bob.changes.close();
        client.close();
      }
    },
  );
}
