import 'dart:convert';

import 'package:awaaz/data/account_api.dart';
import 'package:awaaz/data/device_location_source.dart';
import 'package:awaaz/data/private_values.dart';
import 'package:awaaz/data/sos_journal.dart';
import 'package:awaaz/domain/account_models.dart';
import 'package:awaaz/l10n/generated/app_localizations.dart';
import 'package:awaaz/ui/account_view_model.dart';
import 'package:awaaz/ui/sos_page.dart';
import 'package:awaaz/ui/sos_view_model.dart';
import 'package:awaaz/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:uuid/uuid.dart';

import 'android_loop_test.dart' show FixtureSessions, checkpoint, settle, tap;

class LostSosAcknowledgement extends http.BaseClient {
  final inner = http.Client();
  bool dropped = false, holdReads = false;
  int starts = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (holdReads &&
        request.method == 'GET' &&
        (request.url.path == '/v1/me/incident' ||
            request.url.path.startsWith('/v1/incident-requests/'))) {
      throw http.ClientException('Synthetic receipt outage');
    }
    final start =
        request.method == 'POST' && request.url.path == '/v1/incidents';
    if (start) starts++;
    final response = await inner.send(request);
    if (start &&
        !dropped &&
        response.statusCode >= 200 &&
        response.statusCode < 300) {
      dropped = holdReads = true;
      await response.stream.drain<void>();
      throw http.ClientException('Synthetic lost committed acknowledgement');
    }
    return response;
  }

  @override
  void close() => inner.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'private SOS survives a lost save receipt, sends an explicit response, and clears location on resolve',
    (tester) async {
      final base = Uri.parse('http://10.0.2.2:3031');
      final client = http.Client(), lossy = LostSosAcknowledgement();
      final data = jsonObject(
        jsonDecode((await client.get(base.resolve('/__fixtures'))).body),
      );
      expect(data['synthetic'], true);
      final alice = FixtureSessions(jsonObject(data['alice'])),
          bob = FixtureSessions(jsonObject(data['bob']));
      final api = AccountApi(baseUrl: base, sessions: alice, client: lossy);
      final recipient = AccountApi(
        baseUrl: base,
        sessions: bob,
        client: client,
      );
      final accounts = AccountViewModel(sessions: alice, repository: api);
      final other = AccountViewModel(sessions: bob, repository: recipient);
      final journal = SosJournal(
        values: const SecurePrivateValues(),
        namespace: 'synthetic-sos-integration',
      );
      SosViewModel? sender;
      final receiver = SosViewModel(
        accounts: other,
        repository: recipient,
        locations: GeolocatorLocationSource(),
      );
      String? circleId;
      Future<void> press(Key key) async {
        final finder = find.byKey(key);
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            300,
            scrollable: find.descendant(
              of: find.byKey(const Key('sos-scroll')),
              matching: find.byType(Scrollable),
            ),
            maxScrolls: 20,
          );
        }
        await tap(tester, finder);
      }

      Future<void> show(
        SosViewModel model,
        AccountViewModel account, {
        String language = 'en',
      }) async {
        await tester.pumpWidget(const SizedBox());
        model.setForeground(true);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            theme: awaazTheme(language == 'bn'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SosPage(vm: model, accounts: account, onManage: () async {}),
          ),
        );
        await model.refresh();
        await settle(tester);
      }

      try {
        await accounts.initialize();
        await other.initialize();
        final previous = await api.currentSos();
        if (previous?.status == 'active') {
          await api.endSos(previous!.id, 'cancelled');
        }
        final circle = await api.createCircle(
          const Uuid().v4(),
          'Dhaka help contacts',
        );
        circleId = circle.id;
        final invitation = await api.invite(
          const Uuid().v4(),
          circle.id,
          bob.userId!,
        );
        await recipient.accept(invitation.id, invitation.token);
        await accounts.refresh();
        await other.refresh();
        await show(receiver, other);
        await press(const Key('sos-receive'));
        if (!receiver.preference!.allowed) {
          await press(const Key('sos-receive-switch'));
        }
        await press(const Key('sos-confirm'));
        expect(receiver.preference!.allowed, true, reason: receiver.error);
        expect(receiver.preferenceUnconfirmed, false);

        sender = SosViewModel(
          accounts: accounts,
          repository: api,
          journal: journal,
          locations: GeolocatorLocationSource(),
          allowMockLocations: true,
        );
        await show(sender, accounts);
        await press(Key('sos-circle-${circle.id}'));
        await press(Key('sos-contact-${bob.userId}'));
        await press(const Key('sos-location'));
        await press(const Key('sos-start'));
        expect(find.textContaining('Native fixture Bob'), findsWidgets);
        await press(const Key('sos-confirm'));
        expect(lossy.dropped, true);
        expect(sender.pending, isNotNull);
        final requestId = sender.pending!.id;
        expect((await journal.read(alice.userId!))!.id, requestId);
        await tester.pumpWidget(const SizedBox());
        sender.dispose();
        lossy.holdReads = false;
        sender = SosViewModel(
          accounts: accounts,
          repository: api,
          journal: journal,
          locations: GeolocatorLocationSource(),
          allowMockLocations: true,
        );
        await show(sender, accounts);
        expect(sender.own?.status, 'active', reason: sender.error);
        expect(sender.pending, isNull);
        expect(await journal.read(alice.userId!), isNull);
        expect(
          lossy.starts,
          1,
        ); // Recovery reads the receipt; it never resends.
        expect(sender.updating, false); // Recovery never silently resumes GPS.
        final id = sender.own!.id;
        await checkpoint('sos-saved');
        final prepared = await client.post(
          base.resolve('/__fixtures/trip'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'action': 'prepare'}),
        );
        expect(prepared.statusCode, 200);
        await press(const Key('sos-resume-location'));
        await press(const Key('sos-confirm'));
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        while (sender.lastUpload == null && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await tester.pump();
        }
        expect(sender.lastUpload, isNotNull, reason: sender.locationError);
        expect((await recipient.viewSos(id)).position, isNotNull);
        expect((await recipient.viewSos(id)).response, isNull);
        await show(receiver, other);
        await press(Key('sos-incoming-$id'));
        expect(
          receiver.viewed!.response,
          isNull,
        ); // Opening is not acknowledgement.
        expect(receiver.position, isNotNull);
        await press(const Key('sos-response-helping'));
        await press(const Key('sos-confirm'));
        expect(receiver.viewed!.response, 'helping', reason: receiver.error);
        await checkpoint('sos-received');
        await show(sender, accounts);
        expect(sender.own!.recipients.single.response, 'helping');
        await press(const Key('sos-resolve'));
        await press(const Key('sos-confirm'));
        expect(sender.own!.status, 'ended', reason: sender.error);
        final ended = await recipient.viewSos(id);
        expect(ended.status, 'ended');
        expect(ended.position, isNull);
        await show(receiver, other, language: 'bn');
        await press(Key('sos-incoming-$id'));
        expect(receiver.viewed!.status, 'ended');
        expect(receiver.position, isNull);
        await checkpoint('sos-bangla');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        sender?.dispose();
        receiver.dispose();
        lossy.holdReads = false;
        final current = await api.currentSos();
        if (current?.status == 'active') {
          await api.endSos(current!.id, 'cancelled');
        }
        if (circleId != null) await api.closeCircle(circleId);
        accounts.dispose();
        other.dispose();
        await alice.changes.close();
        await bob.changes.close();
        client.close();
        lossy.close();
      }
    },
  );
}
