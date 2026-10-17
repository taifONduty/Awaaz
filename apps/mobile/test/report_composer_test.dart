import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awaaz/domain/device_location.dart';
import 'package:awaaz/ui/account_view_model.dart';
import 'package:awaaz/ui/report_composer_view_model.dart';
import 'package:awaaz/ui/report_composer_page.dart';
import 'package:awaaz/l10n/generated/app_localizations.dart';
import 'package:awaaz/ui/theme.dart';

import 'account_api_test.dart' show TestSessions, bob;
import 'account_view_model_test.dart' show TestAccountRepository;

Future<void> tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

DeviceLocation fix(
  DateTime now, {
  double accuracy = 5,
  bool precise = true,
  bool mocked = false,
  double latitude = 23.76,
}) => DeviceLocation(
  latitude: latitude,
  longitude: 90.38,
  accuracy: accuracy,
  capturedAt: now,
  precise: precise,
  mocked: mocked,
);

class TestLocationSource implements LocationSource {
  TestLocationSource(this.value);
  DeviceLocation value;
  Completer<DeviceLocation>? held;
  String? failure;
  int calls = 0, cancellations = 0;
  @override
  Future<DeviceLocation> acquire() async {
    calls++;
    if (failure != null) throw LocationFailure(failure!);
    return held?.future ?? value;
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }

  @override
  Future<bool> openAppSettings() async => true;
  @override
  Future<bool> openLocationSettings() async => true;
}

class TestEnvironment {
  final sessions = TestSessions();
  late final repository = TestAccountRepository(sessions);
  late final accounts = AccountViewModel(
    sessions: sessions,
    repository: repository,
  );
  Future<void> close() async {
    accounts.dispose();
    await sessions.controller.close();
  }
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  test('location quality rejects imprecise, stale, inaccurate, mocked and outside-pilot fixes', () {
    final now = DateTime.now().toUtc();
    expect(fix(now).problemAt(now), isNull);
    expect(fix(now, precise: false).problemAt(now), 'location_approximate');
    expect(fix(now, accuracy: 200).problemAt(now), 'location_inaccurate');
    expect(
      fix(now, accuracy: double.nan).problemAt(now),
      'location_inaccurate',
    );
    expect(
      fix(now.subtract(const Duration(minutes: 3))).problemAt(now),
      'location_stale',
    );
    expect(
      fix(now.add(const Duration(minutes: 1))).problemAt(now),
      'location_stale',
    );
    expect(fix(now, mocked: true).problemAt(now), 'location_mocked');
    expect(fix(now, latitude: 37).problemAt(now), 'outside_pilot');
  });
  test('capture is explicit, edits reset consent and stale locations cannot submit', () async {
    final env = TestEnvironment();
    await env.accounts.initialize();
    var now = DateTime.now().toUtc();
    final source = TestLocationSource(fix(now));
    final vm = ReportComposerViewModel(
      accounts: env.accounts,
      locations: source,
      now: () => now,
    );
    vm.setDescription('Observable lighting issue');
    expect(source.calls, 0);
    await vm.locate();
    expect(vm.ready, isFalse);
    vm.setConsent(true);
    expect(vm.ready, isTrue);
    vm.setDescription('Another observable lighting issue');
    expect(vm.consent, isFalse);
    vm.setConsent(true);
    now = now.add(const Duration(minutes: 3));
    expect(await vm.submit(), isFalse);
    expect(env.repository.reportIds, isEmpty);
    vm.dispose();
    await env.close();
  });
  test('account change and backgrounding discard late locations without automatic recapture', () async {
    final env = TestEnvironment();
    await env.accounts.initialize();
    final now = DateTime.now().toUtc();
    final source = TestLocationSource(fix(now))
      ..held = Completer<DeviceLocation>();
    final vm = ReportComposerViewModel(
      accounts: env.accounts,
      locations: source,
    );
    vm.setDescription('PRIVATE Alice report text');
    final locating = vm.locate();
    env.sessions.switchTo(bob);
    source.held!.complete(fix(now));
    await locating;
    expect(vm.description, isEmpty);
    expect(vm.location, isNull);
    expect(vm.consent, isFalse);
    await env.accounts.refresh();
    source.held = null;
    await vm.locate();
    vm.setConsent(true);
    vm.setActive(false);
    expect(vm.location, isNull);
    expect(vm.consent, isFalse);
    final calls = source.calls;
    vm.setActive(true);
    expect(source.calls, calls);
    expect(source.cancellations, greaterThan(0));
    vm.dispose();
    await env.close();
  });
  test('denied acquisition and lost submission acknowledgements remain honest and private', () async {
    final env = TestEnvironment();
    env.repository.failReportOnce = true;
    await env.accounts.initialize();
    final source = TestLocationSource(fix(DateTime.now().toUtc()))
      ..failure = 'location_denied';
    final vm = ReportComposerViewModel(
      accounts: env.accounts,
      locations: source,
    );
    vm.setDescription('Observable road obstruction');
    await vm.locate();
    expect(vm.error, 'location_denied');
    expect(vm.ready, isFalse);
    expect(env.repository.reportIds, isEmpty);
    source.failure = null;
    await vm.locate();
    vm.setConsent(true);
    expect(await vm.submit(), isFalse);
    expect(vm.error, 'network_unavailable');
    expect(env.accounts.pendingWrites, hasLength(1));
    expect(env.accounts.events, isEmpty);
    vm.dispose();
    await env.close();
  });
  for (final language in ['en', 'bn']) {
    testWidgets(
      '$language composer fits large text and clears private fields on account change',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final env = TestEnvironment();
        await env.accounts.initialize();
        final source = TestLocationSource(fix(DateTime.now().toUtc()));
        final vm = ReportComposerViewModel(
          accounts: env.accounts,
          locations: source,
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: awaazTheme(language == 'bn'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: ReportComposerPage(vm: vm),
          ),
        );
        await tester.enterText(
          find.byKey(const Key('compose-description')),
          'PRIVATE Alice road report',
        );
        await tap(tester, find.byKey(const Key('compose-locate')));
        expect(vm.location, isNotNull);
        expect(vm.ready, isFalse);
        await tap(tester, find.byKey(const Key('compose-consent')));
        expect(vm.ready, isTrue);
        expect(tester.takeException(), isNull);
        env.sessions.switchTo(bob);
        await tester.pumpAndSettle();
        expect(find.text('PRIVATE Alice road report'), findsNothing);
        expect(vm.location, isNull);
        expect(vm.consent, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await env.close();
      },
    );
  }
}
