import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/device_location.dart';
import '../domain/sharing.dart';
import '../domain/sos.dart';
import '../data/device_location_source.dart';
import '../data/android_sharing_platform.dart';
import '../l10n/generated/app_localizations.dart';
import 'components.dart';
import 'journey_view_model.dart';
import 'account_page.dart';
import 'account_view_model.dart';
import 'pages.dart';
import 'explore_page.dart';
import 'community_page.dart';
import 'circle_overview_page.dart';
import 'report_page.dart';
import 'report_composer_page.dart';
import 'report_composer_view_model.dart';
import 'trip_monitor_view_model.dart';
import 'trip_monitor_panel.dart';
import 'route_change_view_model.dart';
import 'route_change_page.dart';
import 'theme.dart';
import 'sharing_page.dart';
import 'sharing_view_model.dart';
import 'sos_page.dart';
import 'sos_view_model.dart';

enum JourneyPage { home, routes, journey }

class AwaazShell extends StatefulWidget {
  const AwaazShell({
    super.key,
    required this.viewModel,
    required this.accounts,
    required this.locations,
    this.composerFactory,
    required this.trips,
    required this.onToggleLanguage,
    this.mapsEnabled = false,
  });
  final JourneyViewModel viewModel;
  final AccountViewModel accounts;
  final LocationSource locations;
  final ReportComposerFactory? composerFactory;
  final TripMonitorViewModel trips;
  final VoidCallback onToggleLanguage;
  final bool mapsEnabled;
  @override
  State<AwaazShell> createState() => _AwaazShellState();
}

class _AwaazShellState extends State<AwaazShell> {
  int _tab = 0;
  JourneyPage _page = JourneyPage.home;
  bool _report = false;
  bool _composing = false;
  bool _finishingJourney = false;
  bool _startingJourney = false;
  bool _changingRoute = false;
  bool _openingSos = false;
  Destination? _target;
  final _scroll = ScrollController(keepScrollOffset: false);
  String? _visibleContentKey;
  String? _owner;
  late String _nativeStatus;
  JourneyViewModel get vm => widget.viewModel;
  Future<void> _sharing() async {
    final repository = widget.accounts.repository;
    if (repository is! SharingRepository || !widget.accounts.canReport) return;
    final sharing = SharingViewModel(
      accounts: widget.accounts,
      repository: repository as SharingRepository,
      locations: GeolocatorLocationSource(),
      native: const AndroidSharingPlatform(),
    );
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              SharingPage(vm: sharing, mapsEnabled: widget.mapsEnabled),
        ),
      );
    } finally {
      sharing.dispose();
    }
  }

  void _account([
    AccountSection section = AccountSection.profile,
    bool directCircle = false,
  ]) {
    vm.cancelPlan();
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => AccountPage(
            vm: widget.accounts,
            section: section,
            directCircle: directCircle,
            onToggleLanguage: widget.onToggleLanguage,
            onCompose: () => unawaited(_composeReport()),
          ),
        ),
      ),
    );
  }

  Future<void> _composeReport({bool showHistory = false}) async {
    if (_composing) return;
    if (!widget.accounts.canReport) {
      _account(AccountSection.reports);
      return;
    }
    _composing = true;
    try {
      final model =
          widget.composerFactory?.call(widget.accounts, widget.locations) ??
          ReportComposerViewModel(
            accounts: widget.accounts,
            locations: widget.locations,
          );
      final result = await Navigator.of(context).push<ComposerResult>(
        MaterialPageRoute(builder: (_) => ReportComposerPage(vm: model)),
      );
      if (!mounted) return;
      if (result == ComposerResult.submitted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.accounts.reportReceipt == 'withdrawn'
                  ? l.accountWithdrawnReceipt
                  : l.composeSuccess,
            ),
          ),
        );
      }
      if (result != null &&
          (showHistory || result == ComposerResult.savedRequests)) {
        _account(AccountSection.reports);
      }
    } finally {
      _composing = false;
    }
  }

  Future<void> _openCircle(String id) async {
    final owner = widget.accounts.userId;
    final opened = await widget.accounts.selectCircle(id);
    if (mounted &&
        opened &&
        owner == widget.accounts.userId &&
        widget.accounts.detail?.circle.id == id) {
      _account(AccountSection.circles, true);
    }
  }

  @override
  void initState() {
    super.initState();
    _target = vm.repository.destinations.isEmpty
        ? null
        : vm.repository.destinations.first;
    _owner = widget.accounts.userId;
    _nativeStatus = widget.trips.snapshot.status;
    widget.accounts.addListener(_accountChanged);
    widget.trips.addListener(_tripChanged);
  }

  void _accountChanged() {
    if (_owner == widget.accounts.userId) return;
    _owner = widget.accounts.userId;
    setState(() {
      _target = vm.repository.destinations.isEmpty
          ? null
          : vm.repository.destinations.first;
      _page = JourneyPage.home;
      _tab = 0;
      _report = false;
    });
  }

  void _tripChanged() {
    final status = widget.trips.snapshot.status;
    if (status == 'check_in' && _nativeStatus != status) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    _nativeStatus = status;
    vm.reconcileRouteChange(widget.trips);
    if (vm.selectedRoute?.corridor != null &&
        vm.phase != JourneyPhase.idle &&
        !_finishingJourney &&
        !widget.trips.busy &&
        widget.trips.statusConfirmed &&
        !widget.trips.snapshot.active) {
      vm.end();
      setState(() => _page = JourneyPage.home);
    }
  }

  @override
  void dispose() {
    widget.accounts.removeListener(_accountChanged);
    widget.trips.removeListener(_tripChanged);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _plan(Destination destination) async {
    if (widget.trips.busy || _finishingJourney || _startingJourney) return;
    if (vm.phase != JourneyPhase.idle) {
      setState(() {
        _tab = 0;
        _page = JourneyPage.journey;
      });
      return;
    }
    if (vm.repository.geographic) {
      final owner = _owner;
      final l = AppLocalizations.of(context);
      final consent = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(l.geoPlanConsentTitle),
          content: Text(l.geoPlanConsentBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const Key('route-location-consent'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.geoUseOrigin),
            ),
          ],
        ),
      );
      if (!mounted || consent != true || owner != _owner) return;
    }
    setState(() {
      _tab = 0;
      _page = JourneyPage.routes;
    });
    unawaited(vm.plan(destination));
  }

  Future<void> _start() async {
    if (widget.trips.busy || _startingJourney || _finishingJourney) return;
    final route = vm.selectedRoute;
    if (route == null || vm.loading || vm.phase != JourneyPhase.idle) return;
    final owner = widget.accounts.userId;
    setState(() => _startingJourney = true);
    try {
      if (route.corridor != null) {
        final l = AppLocalizations.of(context);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text(l.journeyArmTitle),
            content: Text('${l.nativeArmBody}\n\n${l.nativePrivate}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                key: const Key('native-arm-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.journeyStartNative),
              ),
            ],
          ),
        );
        if (!mounted ||
            confirmed != true ||
            owner != widget.accounts.userId ||
            route != vm.selectedRoute) {
          return;
        }
        final started = await widget.trips.arm(
          route.id,
          route.corridor,
          Localizations.localeOf(context).languageCode,
        );
        if (!started || !mounted) return;
        if (owner != widget.accounts.userId || route != vm.selectedRoute) {
          if (owner == widget.accounts.userId &&
              widget.trips.snapshot.routeId == route.id) {
            await widget.trips.stop();
          }
          return;
        }
      }
      vm.start();
      setState(() => _page = JourneyPage.journey);
    } finally {
      if (mounted) setState(() => _startingJourney = false);
    }
  }

  Future<void> _end() async {
    if (_finishingJourney || widget.trips.busy) return;
    final owner = widget.accounts.userId;
    final route = vm.selectedRoute;
    setState(() => _finishingJourney = true);
    try {
      if ((route?.corridor != null ||
              widget.trips.snapshot.active ||
              !widget.trips.statusConfirmed) &&
          !await widget.trips.stop()) {
        return;
      }
      if (!mounted ||
          owner != widget.accounts.userId ||
          route != vm.selectedRoute) {
        return;
      }
      vm.end();
      setState(() => _page = JourneyPage.home);
    } finally {
      if (mounted) setState(() => _finishingJourney = false);
    }
  }

  Future<void> _changeRoute() async {
    if (_changingRoute ||
        _finishingJourney ||
        _startingJourney ||
        widget.trips.busy) {
      return;
    }
    _changingRoute = true;
    RouteChangeViewModel? comparison;
    final route = vm.selectedRoute;
    final owner = _owner;
    try {
      if (!widget.trips.statusConfirmed && !await widget.trips.refresh()) {
        return;
      }
      if (!mounted ||
          owner != _owner ||
          route != vm.selectedRoute ||
          vm.phase != JourneyPhase.active ||
          !widget.trips.snapshot.active ||
          !vm.repository.geographic ||
          vm.destination == null) {
        return;
      }
      comparison = RouteChangeViewModel(journey: vm, trips: widget.trips);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RouteChangePage(
            vm: comparison!,
            mapsEnabled: widget.mapsEnabled,
            onSos: _sos,
          ),
        ),
      );
    } finally {
      comparison?.dispose();
      _changingRoute = false;
    }
  }

  void _selectTab(int value) {
    if (widget.trips.busy || _finishingJourney || _startingJourney) return;
    vm.cancelPlan();
    setState(() {
      _tab = value;
      _report = false;
    });
  }

  void _back() {
    if (widget.trips.busy || _finishingJourney || _startingJourney) return;
    vm.cancelPlan();
    setState(() {
      if (_report) {
        _report = false;
      } else if (_tab == 0) {
        _page = JourneyPage.home;
      } else {
        _tab = 0;
      }
    });
  }

  Future<void> _sos() async {
    if (_openingSos) return;
    _openingSos = true;
    final repository = widget.accounts.repository;
    final model = repository is SosRepository
        ? SosViewModel(
            accounts: widget.accounts,
            repository: repository as SosRepository,
            locations: GeolocatorLocationSource(),
          )
        : null;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => SosPage(
            vm: model,
            accounts: widget.accounts,
            onManage: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => AccountPage(
                    vm: widget.accounts,
                    section: AccountSection.circles,
                  ),
                ),
              );
            },
            mapsEnabled: widget.mapsEnabled,
          ),
        ),
      );
    } finally {
      model?.dispose();
      _openingSos = false;
    }
  }

  Widget _content(AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.trips.snapshot.active ||
          widget.trips.error != null ||
          widget.trips.statusFailure ||
          widget.trips.snapshot.status == 'interrupted')
        if (!(_tab == 0 &&
            _page == JourneyPage.journey &&
            vm.phase == JourneyPhase.active &&
            vm.selectedRoute?.corridor != null)) ...[
          TripMonitorPanel(
            vm: widget.trips,
            hasCorridor: vm.selectedRoute?.corridor != null,
          ),
          const SizedBox(height: 12),
        ],
      _pageContent(l),
    ],
  );
  Widget _pageContent(AppLocalizations l) {
    if (_tab == 1) {
      if (_report) {
        return ReportPage(
          vm: vm,
          onSaved: () => setState(() => _report = false),
        );
      }
      return CommunityPage(
        key: ValueKey(_owner),
        vm: vm,
        accounts: widget.accounts,
        onHistory: () => _account(AccountSection.reports),
        onReport: () {
          if (widget.accounts.configured) {
            unawaited(_composeReport(showHistory: true));
          } else {
            setState(() => _report = true);
          }
        },
      );
    }
    if (_tab == 2) {
      return CircleOverviewPage(
        accounts: widget.accounts,
        onHelp: () => unawaited(_sos()),
        onShare: widget.accounts.repository is SharingRepository
            ? () => unawaited(_sharing())
            : null,
        onManage: () => _account(AccountSection.circles),
        onOpen: (id) => unawaited(_openCircle(id)),
      );
    }
    if (vm.phase == JourneyPhase.checkIn) {
      return DeviationPage(vm: vm, onSos: _sos);
    }
    if (_page == JourneyPage.journey && vm.phase == JourneyPhase.active) {
      return ActiveJourneyPage(
        vm: vm,
        onEnd: _end,
        onSos: _sos,
        trips: widget.trips,
        finishing: _finishingJourney,
        mapsEnabled: widget.mapsEnabled,
        showActions: vm.selectedRoute?.sourceTimestamp == null,
        onChangeRoute:
            vm.repository.geographic && vm.selectedRoute?.corridor != null
            ? _changeRoute
            : null,
      );
    }
    if (_page == JourneyPage.routes) {
      return RoutesPage(vm: vm, mapsEnabled: widget.mapsEnabled);
    }
    return ExplorePage(
      key: ValueKey(_owner),
      mapsEnabled: widget.mapsEnabled,
      vm: vm,
      initialDestination: _target,
      onTargetChanged: (value) => setState(() => _target = value),
      onPlan: _plan,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, widget.trips]),
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final labels = [l.explore, l.community, l.circle];
      final icons = [
        Icons.explore_outlined,
        Icons.campaign_outlined,
        Icons.groups_outlined,
      ];
      return LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 840;
          final home =
              _tab == 0 &&
              _page == JourneyPage.home &&
              vm.phase == JourneyPhase.idle;
          final showJourneyAction =
              _tab == 0 &&
              _page == JourneyPage.routes &&
              vm.phase == JourneyPhase.idle;
          final showGeographicJourneyActions =
              _tab == 0 &&
              _page == JourneyPage.journey &&
              vm.phase == JourneyPhase.active &&
              vm.selectedRoute?.sourceTimestamp != null;
          final canGoBack =
              _report ||
              (_tab == 0 &&
                  _page == JourneyPage.routes &&
                  vm.phase == JourneyPhase.idle);
          final viewKey = '$_tab-$_page-$_report-${vm.phase}';
          if (_visibleContentKey != viewKey) {
            _visibleContentKey = viewKey;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
            });
          }
          final content = SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.science_outlined,
                                  size: 16,
                                  color: AwaazColors.warning,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.trips.snapshot.active
                                        ? l.journeyNativeStatus
                                        : vm.repository.geographic
                                        ? l.geoStatus
                                        : widget.mapsEnabled
                                        ? l.mapPreviewStatus
                                        : l.demo,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall!
                                        .copyWith(color: AwaazColors.warning),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (vm.scenario == DemoScenario.offline)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(l.offline),
                            ),
                          if (vm.storageFailed)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                l.storageError,
                                style: const TextStyle(
                                  color: AwaazColors.danger,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child:
                      home &&
                          !widget.trips.snapshot.active &&
                          widget.trips.error == null &&
                          !widget.trips.statusFailure &&
                          widget.trips.snapshot.status != 'interrupted'
                      ? _pageContent(l)
                      : SingleChildScrollView(
                          key: const Key('page-scroll'),
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1120),
                              child: AnimatedSwitcher(
                                duration: uiMotion(context),
                                child: KeyedSubtree(
                                  key: ValueKey(viewKey),
                                  child: _content(l),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          );
          return PopScope<void>(
            canPop:
                !canGoBack &&
                _tab == 0 &&
                !widget.trips.busy &&
                !_finishingJourney &&
                !_startingJourney,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _back();
            },
            child: Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                toolbarHeight: 52,
                leading: canGoBack
                    ? IconButton(
                        tooltip: l.back,
                        icon: const Icon(Icons.arrow_back),
                        onPressed: _back,
                      )
                    : null,
                title: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 88) {
                      return Semantics(
                        label: 'Awaaz',
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Icon(
                            Icons.shield_rounded,
                            color: AwaazColors.primary,
                          ),
                        ),
                      );
                    }
                    return const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield_rounded, color: AwaazColors.primary),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Awaaz',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                actions: [
                  if (vm.phase == JourneyPhase.idle)
                    IconButton(
                      key: const Key('account'),
                      tooltip: l.accountOpen,
                      icon: const Icon(Icons.account_circle_outlined),
                      onPressed: () => _account(),
                    ),
                  if (vm.phase != JourneyPhase.idle &&
                      (_tab != 0 || _page != JourneyPage.journey))
                    IconButton(
                      key: const Key('header-sos'),
                      tooltip: l.openSos,
                      icon: const Icon(Icons.sos, color: AwaazColors.danger),
                      onPressed: _sos,
                    ),
                  TextButton(
                    key: const Key('language'),
                    onPressed: widget.onToggleLanguage,
                    child: Text(
                      Localizations.localeOf(context).languageCode == 'en'
                          ? 'বাংলা'
                          : 'EN',
                      style: const TextStyle(fontFamily: 'Noto Sans Bengali'),
                    ),
                  ),
                  if (!vm.repository.geographic)
                    PopupMenuButton<DemoScenario>(
                      tooltip: l.demoScenarios,
                      icon: const Icon(Icons.tune),
                      onSelected: vm.setScenario,
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: DemoScenario.normal,
                          child: Text(l.normal),
                        ),
                        PopupMenuItem(
                          value: DemoScenario.offline,
                          child: Text(l.simulateOffline),
                        ),
                        PopupMenuItem(
                          value: DemoScenario.routeError,
                          child: Text(l.simulateError),
                        ),
                        PopupMenuItem(
                          value: DemoScenario.emptyReports,
                          child: Text(l.emptyReports),
                        ),
                      ],
                    ),
                ],
              ),
              body: wide
                  ? Row(
                      children: [
                        NavigationRail(
                          selectedIndex: _tab,
                          onDestinationSelected: _selectTab,
                          labelType: NavigationRailLabelType.all,
                          destinations: [
                            for (var i = 0; i < 3; i++)
                              NavigationRailDestination(
                                icon: Icon(icons[i]),
                                label: Text(labels[i]),
                              ),
                          ],
                        ),
                        const VerticalDivider(
                          width: 1,
                          color: AwaazColors.border,
                        ),
                        Expanded(child: content),
                      ],
                    )
                  : content,
              bottomNavigationBar: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: const Border(
                    top: BorderSide(color: AwaazColors.border),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AwaazColors.ink.withValues(alpha: .04),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showGeographicJourneyActions)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ActionButton(
                                  key: const Key('end'),
                                  label: _finishingJourney
                                      ? l.journeyEnding
                                      : l.endJourney,
                                  icon: Icons.stop_rounded,
                                  onPressed:
                                      _finishingJourney || widget.trips.busy
                                      ? null
                                      : _end,
                                ),
                                const SizedBox(height: 8),
                                ActionButton(
                                  label: l.openSos,
                                  quiet: true,
                                  icon: Icons.sos,
                                  onPressed:
                                      _finishingJourney || widget.trips.busy
                                      ? null
                                      : _sos,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (showJourneyAction)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: ActionButton(
                              key: const Key('start'),
                              label: _startingJourney
                                  ? l.journeyStarting
                                  : vm.repository.geographic ||
                                        vm.selectedRoute?.corridor != null
                                  ? l.journeyStartNative
                                  : l.start,
                              onPressed:
                                  vm.loading ||
                                      widget.trips.busy ||
                                      _startingJourney ||
                                      vm.routeFailed ||
                                      vm.selectedRoute == null
                                  ? null
                                  : _start,
                            ),
                          ),
                        ),
                      ),
                    if (!wide)
                      NavigationBar(
                        selectedIndex: _tab,
                        onDestinationSelected: _selectTab,
                        destinations: [
                          for (var i = 0; i < 3; i++)
                            NavigationDestination(
                              icon: Icon(icons[i]),
                              label: labels[i],
                            ),
                        ],
                      ),
                    if (wide && showJourneyAction)
                      const SafeArea(top: false, child: SizedBox(height: 0)),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
