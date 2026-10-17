import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import 'data/draft_store.dart';
import 'data/geographic_repository.dart';
import 'data/device_location_source.dart';
import 'domain/device_location.dart';
import 'ui/report_composer_view_model.dart';
import 'data/android_trip_platform.dart';
import 'data/google_maps_config.dart';
import 'ui/trip_monitor_view_model.dart';
import 'l10n/generated/app_localizations.dart';
import 'ui/journey_view_model.dart';
import 'ui/account_view_model.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/navigation_observer.dart';

class AwaazApp extends StatefulWidget {
  const AwaazApp({
    super.key,
    this.viewModel,
    this.accountViewModel,
    this.locations,
    this.composerFactory,
    this.tripMonitor,
  });
  final JourneyViewModel? viewModel;
  final AccountViewModel? accountViewModel;
  final LocationSource? locations;
  final ReportComposerFactory? composerFactory;
  final TripMonitorViewModel? tripMonitor;
  @override
  State<AwaazApp> createState() => _AwaazAppState();
}

class _AwaazAppState extends State<AwaazApp> with WidgetsBindingObserver {
  late final JourneyViewModel _vm;
  late final AccountViewModel _accounts;
  late final LocationSource _locations;
  late final TripMonitorViewModel _trips;
  String? _tripOwner;
  bool _tripReady = false;
  bool _mapsEnabled = false;
  Locale _locale = const Locale('en');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accounts = widget.accountViewModel ?? AccountViewModel();
    _locations = widget.locations ?? GeolocatorLocationSource();
    _vm =
        widget.viewModel ??
        JourneyViewModel(
          repository: createSafetyRepository(),
          draftStore: kIsWeb ? MemoryDraftStore() : SecureDraftStore(),
          routingLocations: GeolocatorLocationSource(),
          allowMockedLocations: kDebugMode,
        );
    _trips =
        widget.tripMonitor ??
        TripMonitorViewModel(
          platform: const AndroidTripPlatform(),
          locations: _locations,
        );
    _tripOwner = _accounts.userId;
    _accounts.addListener(_ownerChanged);
    // Let first-paint/startup work complete before beginning a bounded native
    // lookup. Account changes still bind immediately and clear private state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_initializeTrips());
        unawaited(_initializeMaps());
      }
    });
    unawaited(_accounts.initialize());
    unawaited(_vm.initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accounts.removeListener(_ownerChanged);
    if (widget.tripMonitor == null) _trips.dispose();
    if (widget.accountViewModel == null) _accounts.dispose();
    if (widget.viewModel == null) _vm.dispose();
    if (widget.locations == null) unawaited(_locations.cancel());
    super.dispose();
  }

  void _ownerChanged() {
    if (_tripOwner != _accounts.userId) {
      _tripOwner = _accounts.userId;
      _vm.clearAccountRoute();
      unawaited(_trips.bindOwner(_tripOwner));
    }
  }

  Future<void> _initializeTrips() async {
    await _trips.initialize(_tripOwner);
    if (mounted) _tripReady = true;
  }

  Future<void> _initializeMaps() async {
    final configured = await GoogleMapsConfig.isConfigured();
    if (mounted && configured) setState(() => _mapsEnabled = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _vm.cancelPlan();
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_accounts.refresh());
      if (_tripReady) unawaited(_trips.refresh());
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Awaaz',
    debugShowCheckedModeBanner: false,
    locale: _locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: awaazTheme(_locale.languageCode == 'bn'),
    navigatorObservers: [awaazRouteObserver],
    home: AwaazShell(
      mapsEnabled: _mapsEnabled,
      viewModel: _vm,
      accounts: _accounts,
      locations: _locations,
      composerFactory: widget.composerFactory,
      trips: _trips,
      onToggleLanguage: () => setState(() {
        _locale = Locale(_locale.languageCode == 'en' ? 'bn' : 'en');
      }),
    ),
  );
}
