import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awaaz/app.dart';
import 'package:awaaz/data/draft_store.dart';
import 'package:awaaz/data/safety_repository.dart';
import 'package:awaaz/domain/models.dart';
import 'package:awaaz/ui/journey_view_model.dart';
import 'package:awaaz/ui/components.dart';
import 'package:awaaz/startup.dart';
import 'package:awaaz/ui/account_view_model.dart';
import 'package:awaaz/data/place_search.dart';
import 'package:awaaz/ui/geographic_map.dart';
import 'package:awaaz/l10n/generated/app_localizations.dart';
import 'package:awaaz/ui/theme.dart';

class SearchPlacesFixture implements PlaceSearchService {
  final old = Completer<List<NamedPlace>>();
  int canceled = 0;
  @override
  void cancelSearch() => canceled++;
  @override
  Future<List<NamedPlace>> searchPlaces(String query) => query == 'old'
      ? old.future
      : Future.value(const [
          NamedPlace(
            id: 'osm:node:123',
            nameEn: 'Farmgate',
            nameBn: 'ফার্মগেট',
            kind: 'transit',
            point: GeoPoint(23.758, 90.387),
          ),
        ]);
}

JourneyViewModel model() => JourneyViewModel(
  repository: DemoSafetyRepository(),
  draftStore: MemoryDraftStore(),
);

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openJourney(WidgetTester tester) async {
  await tap(tester, find.byKey(const Key('plan')));
  expect(find.text('Choose your route'), findsOneWidget);
  await tap(tester, find.byKey(const Key('start')));
}

void main() {
  testWidgets(
    'named-place search ignores late results and requires arrival-point confirmation in both languages',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final locale in ['en', 'bn']) {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        final service = SearchPlacesFixture();
        Destination? chosen;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            theme: awaazTheme(locale == 'bn'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const Key('open-place-picker'),
                  onPressed: () async {
                    chosen = await Navigator.push<Destination>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GeographicDestinationPicker(
                          mapsEnabled: false,
                          places: service,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('open-place-picker')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('search-named-place')));
        await tester.tap(find.byKey(const Key('search-named-place')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('place-query')), 'old');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(
          find.byKey(const Key('place-query')),
          'Farmgate',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        service.old.complete(const []);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('place-osm:node:123')),
          150,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('place-results')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('place-osm:node:123')),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('place-osm:node:123')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('place-osm:node:123')));
        await tester.pumpAndSettle();
        expect(chosen, isNull);
        expect(
          find.text(locale == 'bn' ? 'ফার্মগেট' : 'Farmgate'),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const Key('use-destination-pin')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('use-destination-pin')));
        await tester.pumpAndSettle();
        expect(chosen!.namedPlace, true);
        expect(chosen!.point!.latitude, 23.758);
        expect(chosen!.name, 'Farmgate');
        expect(service.canceled, greaterThan(0));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('startup paints before account work and releases late services', (
    tester,
  ) async {
    final pending = Completer<AccountViewModel>();
    var closed = 0;
    await tester.pumpWidget(AwaazStartup(loadAccounts: () => pending.future));
    expect(find.byKey(const Key('startup-loading')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('startup-loading')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pending.complete(AccountViewModel(onClose: () => closed++));
    await tester.pump();
    expect(closed, 1);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      AwaazStartup(
        loadAccounts: () async => AccountViewModel(onClose: () => closed++),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AwaazApp), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(closed, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Android back closes an unfinished route and returns from other tabs',
    (tester) async {
      final vm = model();
      await tester.pumpWidget(AwaazApp(viewModel: vm));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const Key('plan')));
      expect(find.text('Choose your route'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Where to today?'), findsOneWidget);
      await tap(tester, find.text('Community'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Where to today?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    },
  );
  testWidgets(
    'navigation starts at the top and demo status stays visible while scrolling',
    (tester) async {
      final vm = model();
      await tester.pumpWidget(AwaazApp(viewModel: vm));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Community'));
      final controller = tester
          .widget<SingleChildScrollView>(find.byKey(const Key('page-scroll')))
          .controller!;
      controller.jumpTo(160);
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      final notice = tester.getRect(
        find.text('DEMO · No live tracking or messages'),
      );
      expect(notice.top, greaterThanOrEqualTo(56));
      expect(notice.bottom, lessThan(150));
      await tap(tester, find.text('Circle'));
      expect(controller.offset, 0);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    },
  );
  testWidgets('quick destinations and map zoom/reset respond to input', (
    tester,
  ) async {
    final vm = model();
    await tester.pumpWidget(AwaazApp(viewModel: vm));
    await tester.pumpAndSettle();
    final viewer = find.descendant(
      of: find.byType(SchematicMap),
      matching: find.byType(InteractiveViewer),
    );
    final transform = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    expect(transform.value.getMaxScaleOnAxis(), 1);
    await tap(tester, find.byKey(const Key('map-zoom')));
    expect(transform.value.getMaxScaleOnAxis(), 2.5);
    await tap(tester, find.byKey(const Key('map-reset')));
    expect(transform.value.getMaxScaleOnAxis(), 1);
    await tap(tester, find.byKey(const Key('quick-destination-station')));
    await tap(tester, find.byKey(const Key('plan')));
    expect(vm.destination!.id, 'station');
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  });
  testWidgets('community filters show only the selected report category', (
    tester,
  ) async {
    final vm = model();
    await tester.pumpWidget(AwaazApp(viewModel: vm));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Community'));
    expect(find.text('Road obstruction'), findsWidgets);
    expect(find.text('Street lighting issue'), findsWidgets);
    await tap(tester, find.byKey(const Key('filter-lighting')));
    expect(find.text('Street lighting issue'), findsWidgets);
    // The obstruction filter remains available, but its report is hidden.
    expect(find.text('Road obstruction'), findsOneWidget);
    await tap(tester, find.byKey(const Key('filter-all')));
    expect(find.text('Road obstruction'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  });
  testWidgets('destination search requires an explicit matching selection', (
    tester,
  ) async {
    final vm = model();
    await tester.pumpWidget(AwaazApp(viewModel: vm));
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('open-destination-search')));
    await tester.enterText(
      find.byKey(const Key('destination-search')),
      'No such destination',
    );
    await tester.pumpAndSettle();
    expect(find.text('No demo destinations match'), findsOneWidget);
    expect(find.byKey(const Key('destination-result-campus')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('destination-search')),
      'University',
    );
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('destination-result-campus')));
    await tap(tester, find.byKey(const Key('plan')));
    expect(vm.destination!.id, 'campus');
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  });
  testWidgets(
    'journey choice, explicit detour acceptance, help access and end',
    (tester) async {
      final vm = model();
      await tester.pumpWidget(AwaazApp(viewModel: vm));
      await tester.pumpAndSettle();
      expect(find.text('DEMO · No live tracking or messages'), findsOneWidget);
      await openJourney(tester);
      expect(vm.phase, JourneyPhase.active);
      await tap(tester, find.byKey(const Key('deviation')));
      expect(find.text('Your route has changed'), findsOneWidget);
      final original = vm.baselineId;
      await tap(tester, find.byKey(const Key('keep-route')));
      expect(vm.baselineId, original);
      await tap(tester, find.byKey(const Key('deviation')));
      await tap(tester, find.byKey(const Key('accept-detour')));
      expect(vm.baselineRevision, 2);
      await tap(tester, find.text('Open SOS'));
      expect(find.text('Help requests'), findsOneWidget);
      expect(find.byKey(const Key('sos-dial')), findsOneWidget);
      expect(find.byKey(const Key('sos-start')), findsNothing);
      await tap(tester, find.byTooltip('Back'));
      expect(vm.phase, JourneyPhase.active);
      await tap(tester, find.byKey(const Key('end')));
      expect(vm.phase, JourneyPhase.idle);
      expect(find.text('Where to today?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    },
  );
  testWidgets('private draft requires consent and can be deleted', (
    tester,
  ) async {
    final vm = model();
    await tester.pumpWidget(AwaazApp(viewModel: vm));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Community'));
    await tap(tester, find.text('Report an incident'));
    await tester.enterText(
      find.byKey(const Key('report-place')),
      'Demo Farmgate',
    );
    await tester.enterText(
      find.byKey(const Key('report-description')),
      'A demo footpath is obstructed.',
    );
    await tap(tester, find.byKey(const Key('save-draft')));
    expect(vm.drafts, isEmpty);
    await tap(tester, find.byKey(const Key('draft-consent')));
    await tap(tester, find.byKey(const Key('save-draft')));
    expect(vm.drafts, hasLength(1));
    expect(find.text('Your local drafts'), findsOneWidget);
    await tap(tester, find.text('Delete local drafts'));
    await tap(tester, find.text('Delete'));
    expect(vm.drafts, isEmpty);
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  });
  testWidgets('offline/error and empty data are honest and recoverable', (
    tester,
  ) async {
    final vm = model();
    await tester.pumpWidget(AwaazApp(viewModel: vm));
    await tester.pumpAndSettle();
    vm.setScenario(DemoScenario.offline);
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('plan')));
    expect(find.text('Routes could not be loaded'), findsOneWidget);
    vm.setScenario(DemoScenario.normal);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Try again'));
    expect(find.text('Lower reported risk'), findsOneWidget);
    vm.setScenario(DemoScenario.emptyReports);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Community'));
    expect(find.text('No reports means unknown, not safe.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  });
  for (final width in [320.0, 1024.0]) {
    testWidgets('English and Bangla layouts at width $width with 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final vm = model();
      await tester.pumpWidget(AwaazApp(viewModel: vm));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byType(NavigationRail),
        width >= 840 ? findsOneWidget : findsNothing,
      );
      await tap(tester, find.byKey(const Key('language')));
      expect(find.text('আজ কোথায় যাবেন?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, find.byKey(const Key('plan')));
      expect(tester.takeException(), isNull);
      await tap(tester, find.byKey(const Key('start')));
      expect(tester.takeException(), isNull);
      await tap(tester, find.byKey(const Key('deviation')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    });
  }
  testWidgets(
    'Community, Circle and Report fit a small phone at 200% text in both languages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final vm = model();
      await tester.pumpWidget(AwaazApp(viewModel: vm));
      await tester.pumpAndSettle();
      for (final bangla in [false, true]) {
        await tap(tester, find.text(bangla ? 'আপনজন' : 'Circle'));
        expect(tester.takeException(), isNull);
        await tap(tester, find.text(bangla ? 'কমিউনিটি' : 'Community'));
        expect(tester.takeException(), isNull);
        await tap(
          tester,
          find.text(bangla ? 'একটি ঘটনা জানান' : 'Report an incident'),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Report layout, Bangla: $bangla',
        );
        await tap(tester, find.byTooltip(bangla ? 'ফিরুন' : 'Back'));
        if (!bangla) await tap(tester, find.byKey(const Key('language')));
      }
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    },
  );
}
