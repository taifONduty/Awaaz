import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:awaaz/data/account_api.dart';
import 'package:awaaz/domain/account_models.dart';
import 'package:awaaz/l10n/generated/app_localizations.dart';
import 'package:awaaz/ui/account_page.dart';
import 'package:awaaz/ui/account_view_model.dart';
import 'package:awaaz/ui/theme.dart';

import 'android_loop_test.dart' show FixtureSessions, checkpoint, settle, tap;

// Commit to the real fixture API, then discard one response. This adapter is
// reachable only from this dedicated integration entry point.
class DropBlockAck extends http.BaseClient {
  final inner = http.Client();
  bool drop = true;
  int writes = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final block =
        request.method == 'PUT' &&
        request.url.path.startsWith('/v1/me/blocks/');
    if (block) writes++;
    final response = await inner.send(request);
    if (block && drop && response.statusCode == 200) {
      drop = false;
      await response.stream.drain<void>();
      throw http.ClientException('Synthetic lost block acknowledgement');
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
    'real Circle block, lost acknowledgement, non-restoring unblock and invitation block',
    (tester) async {
      final transport = DropBlockAck();
      final bobClient = http.Client();
      final language = ValueNotifier('en');
      AccountViewModel? vm;
      FixtureSessions? alice, bob;
      try {
        final response = await bobClient.get(
          Uri.parse('http://10.0.2.2:3031/__fixtures'),
        );
        final fixture = jsonObject(jsonDecode(response.body));
        expect(fixture['synthetic'], true);
        alice = FixtureSessions(jsonObject(fixture['alice']));
        bob = FixtureSessions(jsonObject(fixture['bob']));
        final api = AccountApi(
          baseUrl: Uri.parse('http://10.0.2.2:3031'),
          sessions: alice,
          client: transport,
        );
        final bobApi = AccountApi(
          baseUrl: Uri.parse('http://10.0.2.2:3031'),
          sessions: bob,
          client: bobClient,
        );
        vm = AccountViewModel(sessions: alice, repository: api);
        await vm.initialize();
        expect(vm.error, isNull);
        final circle = await api.createCircle(
          'c1500000-0000-4000-8000-000000000001',
          'Synthetic contact review',
        );
        final invite = await api.invite(
          'c1500000-0000-4000-8000-000000000002',
          circle.id,
          bob.userId!,
        );
        await bobApi.accept(invite.id, invite.token);
        await vm.refresh();
        await vm.selectCircle(circle.id);
        await tester.pumpWidget(
          ValueListenableBuilder<String>(
            valueListenable: language,
            builder: (context, locale, _) => MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: awaazTheme(locale == 'bn'),
              home: AccountPage(vm: vm!, section: AccountSection.circles),
            ),
          ),
        );
        await settle(tester);
        await tap(tester, find.byKey(Key('block-member-${bob.userId}')));
        expect(transport.writes, 0);
        await checkpoint('contact-block-confirm-en');
        await tap(tester, find.byKey(const Key('confirm-contact-block')));
        expect(vm.contactsUnconfirmed, false);
        expect(transport.writes, 1);
        expect((await api.blockState(bob.userId!)).blocked, true);
        expect(vm.detail, isNull);
        await expectLater(
          bobApi.circle(circle.id),
          throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'not_found')),
        );
        await tap(tester, find.byKey(const Key('account-tab-profile')));
        await tap(tester, find.byKey(const Key('open-blocked-accounts')));
        expect(vm.blockedContacts, hasLength(1));
        await checkpoint('contact-block-list-en');
        await tap(tester, find.byKey(Key('unblock-${bob.userId}')));
        await tap(tester, find.byKey(const Key('confirm-contact-block')));
        expect((await api.blockState(bob.userId!)).blocked, false);
        expect(vm.blockedContacts, isEmpty);
        await expectLater(
          bobApi.circle(circle.id),
          throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'not_found')),
        );
        await expectLater(
          bobApi.accept(invite.id, invite.token),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.code,
              'code',
              'invite_unavailable',
            ),
          ),
        );
        language.value = 'bn';
        await settle(tester);
        await checkpoint('contact-block-empty-bn');
        await tester.binding.handlePopRoute();
        await settle(tester);
        final otherCircle = await bobApi.createCircle(
          'c1500000-0000-4000-8000-000000000003',
          'Synthetic invitation',
        );
        final otherInvite = await bobApi.invite(
          'c1500000-0000-4000-8000-000000000004',
          otherCircle.id,
          alice.userId!,
        );
        await vm.refresh();
        await tap(tester, find.byKey(const Key('account-tab-circles')));
        await tap(tester, find.byKey(Key('block-inviter-${otherInvite.id}')));
        await checkpoint('contact-block-confirm-bn');
        await tap(tester, find.byKey(const Key('confirm-contact-block')));
        expect(vm.invitations, isEmpty);
        expect((await api.blockState(bob.userId!)).blocked, true);
        expect(transport.writes, 3);
        await tap(tester, find.byKey(const Key('account-tab-profile')));
        await tap(tester, find.byKey(const Key('open-blocked-accounts')));
        await checkpoint('contact-block-list-bn');
        await tap(tester, find.byKey(Key('unblock-${bob.userId}')));
        await tap(tester, find.byKey(const Key('confirm-contact-block')));
        expect((await api.blockState(bob.userId!)).blocked, false);
        await api.closeCircle(circle.id);
        await bobApi.closeCircle(otherCircle.id);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        vm?.dispose();
        await alice?.changes.close();
        await bob?.changes.close();
        language.dispose();
        transport.close();
        bobClient.close();
      }
    },
  );
}
