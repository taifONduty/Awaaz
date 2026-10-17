import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awaaz/app.dart';
import 'package:awaaz/ui/account_page.dart';
import 'package:awaaz/ui/account_view_model.dart';
import 'package:awaaz/l10n/generated/app_localizations.dart';
import 'package:awaaz/ui/theme.dart';
import 'package:awaaz/domain/models.dart';
import 'package:awaaz/domain/account_models.dart';

import 'account_api_test.dart' show TestSessions, alice, bob;
import 'account_view_model_test.dart' show TestAccountRepository;
import 'widget_test.dart' show tap, model;

Widget accountApp(
  AccountViewModel vm, {
  String language = 'en',
  double scale = 1,
}) => MaterialApp(
  locale: Locale(language),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: awaazTheme(language == 'bn'),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: AccountPage(vm: vm),
);

void main() {
  for (final language in ['en', 'bn']) {
    testWidgets(
      '$language blocked account and confirmation fit 320px at double text size',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final sessions = TestSessions();
        final repository = TestAccountRepository(sessions)
          ..storedBlock = const ContactBlockState(
            userId: bob,
            blocked: true,
            version: 1,
          );
        final vm = AccountViewModel(sessions: sessions, repository: repository);
        await vm.initialize();
        await tester.pumpWidget(accountApp(vm, language: language, scale: 2));
        await tap(tester, find.byKey(const Key('open-blocked-accounts')));
        await tester.scrollUntilVisible(
          find.byKey(const Key('unblock-$bob')),
          160,
        );
        await tap(tester, find.byKey(const Key('unblock-$bob')));
        expect(repository.blockWrites, 0);
        expect(tester.takeException(), isNull);
        await tap(tester, find.byKey(const Key('confirm-contact-block')));
        expect(repository.blockWrites, 1);
        expect(vm.blockedContacts, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        vm.dispose();
        await sessions.controller.close();
      },
    );
  }
  testWidgets(
    'an account change cancels a saved-request removal confirmation',
    (tester) async {
      final sessions = TestSessions();
      final repository = TestAccountRepository(sessions)..failCircleOnce = true;
      final vm = AccountViewModel(sessions: sessions, repository: repository);
      await vm.initialize();
      await vm.createCircle('PRIVATE Alice family');
      final saved = vm.pendingWrites.single;
      await tester.pumpWidget(accountApp(vm));
      await tap(tester, find.byKey(Key('forget-write-${saved.id}')));
      sessions.switchTo(bob);
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE Alice family'), findsNothing);
      await tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      expect((await vm.journal.read(alice)).single.id, saved.id);
      expect(vm.pendingWrites, isEmpty);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      await sessions.controller.close();
    },
  );
  for (final language in ['en', 'bn']) {
    testWidgets(
      '$language saved-request controls fit large text and require explicit retry',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final sessions = TestSessions();
        final repository = TestAccountRepository(sessions)
          ..failReportOnce = true;
        final vm = AccountViewModel(sessions: sessions, repository: repository);
        await vm.initialize();
        await vm.submitReport(
          ReportCategory.lighting,
          'SYNTHETIC observable lighting issue',
          23.76,
          90.38,
        );
        final saved = vm.pendingWrites.single;
        await tester.pumpWidget(accountApp(vm, language: language, scale: 2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(repository.reportIds, hasLength(1));
        await tap(tester, find.byKey(Key('retry-write-${saved.id}')));
        expect(vm.pendingWrites, isEmpty);
        expect(repository.reportIds.toSet(), {saved.id});
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        vm.dispose();
        await sessions.controller.close();
      },
    );
  }
  testWidgets(
    'Circle details open directly and Android back clears the private invitation',
    (tester) async {
      final sessions = TestSessions();
      final repository = TestAccountRepository(sessions);
      final vm = AccountViewModel(sessions: sessions, repository: repository);
      await vm.initialize();
      await vm.createCircle('Family navigation');
      await tester.pumpWidget(accountApp(vm));
      await tap(tester, find.byKey(const Key('account-tab-circles')));
      await tap(tester, find.byKey(Key('circle-${vm.circles.single.id}')));
      expect(find.byKey(const Key('circle-name')), findsNothing);
      expect(find.byKey(const Key('invite-recipient')), findsOneWidget);
      await vm.invite(bob);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('created-invite-code')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(vm.detail, isNull);
      expect(vm.createdInvite, isNull);
      expect(find.byKey(const Key('circle-name')), findsOneWidget);
      expect(find.byKey(const Key('created-invite-code')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      await sessions.controller.close();
    },
  );
  testWidgets(
    'synthetic OTP, adult profile, Circle creation and signout work through widgets',
    (tester) async {
      final sessions = TestSessions(null);
      final repository = TestAccountRepository(sessions)..profileExists = false;
      final vm = AccountViewModel(sessions: sessions, repository: repository);
      await vm.initialize();
      await tester.pumpWidget(accountApp(vm));
      await tester.enterText(
        find.byKey(const Key('account-phone')),
        '০১৭০০ ০০০০০০',
      );
      await tap(tester, find.byKey(const Key('send-otp')));
      expect(sessions.requestedPhone, '+8801700000000');
      await tester.enterText(find.byKey(const Key('account-otp')), '১২৩৪৫৬');
      await tap(tester, find.byKey(const Key('verify-otp')));
      expect(sessions.verifiedCode, '123456');
      await tester.enterText(
        find.byKey(const Key('account-name')),
        'Fixture member',
      );
      final button = find.descendant(
        of: find.byKey(const Key('save-profile')),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tap(tester, find.byKey(const Key('account-adult')));
      await tap(tester, find.byKey(const Key('save-profile')));
      expect(vm.account!.userId, alice);
      await tap(tester, find.text('Trusted Circles'));
      await tester.enterText(
        find.byKey(const Key('circle-name')),
        'Fixture family',
      );
      await tap(tester, find.byKey(const Key('create-circle')));
      expect(find.text('Fixture family'), findsOneWidget);
      await tap(tester, find.text('Profile'));
      await tap(tester, find.byKey(const Key('account-signout')));
      expect(find.byKey(const Key('account-phone')), findsOneWidget);
      expect(find.text('Fixture family'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      await sessions.controller.close();
    },
  );
  testWidgets('private form contents disappear when the session changes', (
    tester,
  ) async {
    final sessions = TestSessions();
    final repository = TestAccountRepository(sessions)..profileExists = false;
    final vm = AccountViewModel(sessions: sessions, repository: repository);
    await vm.initialize();
    await tester.pumpWidget(accountApp(vm));
    await tester.enterText(
      find.byKey(const Key('account-name')),
      'PRIVATE Alice draft',
    );
    sessions.switchTo(bob);
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE Alice draft'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('account-name')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
    await sessions.controller.close();
  });
  for (final language in ['en', 'bn']) {
    testWidgets(
      '$language account screens fit a narrow phone at 200 percent text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final sessions = TestSessions();
        final repository = TestAccountRepository(sessions);
        final vm = AccountViewModel(sessions: sessions, repository: repository);
        await vm.initialize();
        await tester.pumpWidget(accountApp(vm, language: language, scale: 2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        vm.dispose();
        await sessions.controller.close();
      },
    );
  }
  testWidgets(
    'main Community and Circles use account data and clear it on signout',
    (tester) async {
      final journey = model();
      final sessions = TestSessions();
      final repository = TestAccountRepository(sessions);
      final accounts = AccountViewModel(
        sessions: sessions,
        repository: repository,
      );
      repository.published = [
        PublishedRoadEvent(
          id: alice,
          category: ReportCategory.lighting,
          summary: 'SERVER published lighting observation',
          observedAt: DateTime.now().toUtc(),
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      ];
      await accounts.initialize();
      await accounts.createCircle('PRIVATE fixture family');
      final circleId = accounts.circles.single.id;
      await tester.pumpWidget(
        AwaazApp(viewModel: journey, accountViewModel: accounts),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('account')));
      expect(find.byType(AccountPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AccountPage), findsNothing);
      expect(find.byKey(const Key('plan')), findsOneWidget);
      await tap(tester, find.text('Community'));
      expect(find.byKey(const Key('published-event-$alice')), findsOneWidget);
      expect(
        find.text('SERVER published lighting observation'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Construction blocks part of the footpath near the crossing.',
        ),
        findsNothing,
      );
      await tap(tester, find.text('Circle'));
      await tap(tester, find.byKey(Key('overview-circle-$circleId')));
      expect(find.byKey(const Key('invite-recipient')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AccountPage), findsNothing);
      expect(accounts.detail, isNull);
      expect(find.byKey(Key('overview-circle-$circleId')), findsOneWidget);
      sessions.switchTo(null);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Community'));
      expect(find.text('SERVER published lighting observation'), findsNothing);
      expect(find.text('PRIVATE fixture family'), findsNothing);
      expect(find.text('Continue with your phone'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      journey.dispose();
      accounts.dispose();
      await sessions.controller.close();
    },
  );
}
