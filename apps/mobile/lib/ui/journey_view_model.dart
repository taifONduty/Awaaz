import 'package:flutter/foundation.dart';

import '../data/draft_store.dart';
import '../data/safety_repository.dart';
import '../data/geographic_repository.dart';
import '../domain/device_location.dart';
import '../domain/account_models.dart' show ApiFailure;
import '../domain/deviation_monitor.dart';
import '../domain/models.dart';
import '../domain/trip_monitor.dart';
import 'trip_monitor_view_model.dart';

class _ApprovedRouteChange {
  const _ApprovedRouteChange(
    this.previous,
    this.next,
    this.origin,
    this.expected,
  );
  final RouteOption previous, next;
  final GeoPoint origin;
  final TripSnapshot expected;
}

class JourneyViewModel extends ChangeNotifier {
  JourneyViewModel({
    required this.repository,
    required this.draftStore,
    this.routingLocations,
    this.allowMockedLocations = false,
  });
  final SafetyRepository repository;
  final DraftStore draftStore;
  final LocationSource? routingLocations;
  final bool allowMockedLocations;
  GeoPoint? origin;
  String? routeError;
  final DeviationMonitor monitor = DeviationMonitor();
  DemoScenario scenario = DemoScenario.normal;
  TravelMode mode = TravelMode.car;
  JourneyPhase phase = JourneyPhase.idle;
  Destination? destination;
  List<RouteOption> _routes = [];
  List<ReportDraft> _drafts = [];
  RouteOption? selectedRoute;
  String? baselineId;
  int baselineRevision = 0;
  bool loading = false;
  bool routeFailed = false;
  bool storageFailed = false;
  bool saving = false;
  bool initialized = false;
  bool _disposed = false;
  int _requestVersion = 0;
  _ApprovedRouteChange? _approvedChange;
  bool get replacementPending => _approvedChange != null;
  List<RouteOption> get routes => List.unmodifiable(_routes);
  List<ReportDraft> get drafts => List.unmodifiable(_drafts);
  List<CommunityReport> get reports =>
      scenario == DemoScenario.emptyReports ? [] : repository.reports;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      _drafts = await draftStore.read();
    } catch (_) {
      storageFailed = true;
    }
    initialized = true;
    _emit();
  }

  void setScenario(DemoScenario value) {
    scenario = value;
    _emit();
  }

  void setMode(TravelMode value) {
    if (phase != JourneyPhase.idle || loading) return;
    mode = value;
    _emit();
  }

  Future<void> plan(Destination value) async {
    if (phase != JourneyPhase.idle) return;
    final version = ++_requestVersion;
    destination = value;
    loading = true;
    routeFailed = false;
    routeError = null;
    origin = null;
    _routes = [];
    selectedRoute = null;
    _emit();
    try {
      final source = repository;
      List<RouteOption> result;
      if (source is GeographicRouting) {
        if (source is GeographicRepository && source.baseUrl == null) {
          throw const ApiFailure('routing_not_configured');
        }
        final locations = routingLocations;
        if (locations == null) throw const ApiFailure('location_unavailable');
        final fix = await locations.acquire();
        if (_disposed || version != _requestVersion) return;
        final problem = fix.problemAt(
          DateTime.now().toUtc(),
          allowMocked: allowMockedLocations,
        );
        if (problem != null) throw ApiFailure(problem);
        final point = GeoPoint(fix.latitude, fix.longitude);
        result = await source.routesFrom(point, value, mode);
        if (_disposed || version != _requestVersion) return;
        origin = point;
      } else {
        result = await source.routes(value, mode, scenario);
      }
      if (_disposed || version != _requestVersion) return;
      _routes = List.of(result);
      selectedRoute = result.isEmpty ? null : result.first;
    } catch (failure) {
      if (_disposed || version != _requestVersion) return;
      routeFailed = true;
      routeError = failure is ApiFailure
          ? failure.code
          : failure is LocationFailure
          ? failure.code
          : 'routing_unavailable';
    } finally {
      if (!_disposed && version == _requestVersion) {
        loading = false;
        _emit();
      }
    }
  }

  void cancelPlan() {
    if (!repository.geographic || !loading) return;
    _requestVersion++;
    final source = repository;
    if (source is GeographicRouting) source.cancel();
    routingLocations?.cancel();
    loading = false;
    routeFailed = true;
    routeError = 'planning_canceled';
    origin = null;
    _routes = [];
    selectedRoute = null;
    _emit();
  }

  void select(RouteOption route) {
    if (phase != JourneyPhase.idle || !_routes.contains(route)) return;
    selectedRoute = route;
    _emit();
  }

  void start() {
    if (selectedRoute == null || loading || phase != JourneyPhase.idle) return;
    phase = JourneyPhase.active;
    baselineId = selectedRoute!.id;
    baselineRevision = 1;
    monitor.acknowledge();
    _emit();
  }

  void simulateDeviation() {
    if (selectedRoute?.corridor != null) return;
    if (phase != JourneyPhase.active) return;
    monitor.acknowledge();
    for (final second in [0, 10, 20]) {
      final status = monitor.update(
        CorridorSample(
          elapsed: Duration(seconds: second),
          distanceMetres: 150,
          accuracyMetres: 10,
          fixAge: Duration.zero,
          speedMps: 8,
        ),
      );
      if (status == MonitorStatus.checkIn) phase = JourneyPhase.checkIn;
    }
    _emit();
  }

  void acknowledgeDetour({required bool accept}) {
    if (selectedRoute?.corridor != null) return;
    if (phase != JourneyPhase.checkIn) return;
    if (accept) {
      baselineRevision++;
      baselineId = '${selectedRoute!.id}-detour-$baselineRevision';
    }
    monitor.acknowledge();
    phase = JourneyPhase.active;
    _emit();
  }

  void end() {
    _approvedChange = null;
    phase = JourneyPhase.idle;
    baselineId = null;
    monitor.acknowledge();
    _emit();
  }

  Future<bool> replaceRoute({
    required RouteOption previous,
    required RouteOption next,
    required GeoPoint newOrigin,
    required TripSnapshot expected,
    required TripMonitorViewModel trips,
    required String locale,
  }) async {
    final current = trips.snapshot;
    if (_disposed ||
        replacementPending ||
        phase != JourneyPhase.active ||
        selectedRoute != previous ||
        next.corridor == null ||
        !trips.statusConfirmed ||
        !current.active ||
        current.sessionId != expected.sessionId ||
        current.ownerId != expected.ownerId ||
        current.revision != expected.revision ||
        current.routeId != previous.id ||
        expected.routeId != previous.id ||
        trips.owner != expected.ownerId) {
      return false;
    }
    // Approval is owned by the journey, not the temporary comparison page.
    // A late native receipt can still reconcile after that page is covered.
    _approvedChange = _ApprovedRouteChange(previous, next, newOrigin, expected);
    _emit();
    await trips.replace(next.id, next.corridor!, locale);
    reconcileRouteChange(trips);
    return selectedRoute == next && baselineRevision == expected.revision + 1;
  }

  bool reconcileRouteChange(TripMonitorViewModel trips) {
    final change = _approvedChange;
    if (change == null || _disposed) return false;
    if (phase != JourneyPhase.active ||
        selectedRoute != change.previous ||
        trips.owner != change.expected.ownerId) {
      _approvedChange = null;
      _emit();
      return false;
    }
    if (!trips.statusConfirmed) return false;
    final state = trips.snapshot;
    if (state.active &&
        state.ownerId == change.expected.ownerId &&
        state.sessionId == change.expected.sessionId &&
        state.routeId == change.next.id &&
        state.revision == change.expected.revision + 1) {
      selectedRoute = change.next;
      _routes = [change.next];
      origin = change.origin;
      baselineId = change.next.id;
      baselineRevision = state.revision;
      _approvedChange = null;
      monitor.acknowledge();
      _emit();
      return true;
    }
    // Only a completed native reconciliation can resolve an ambiguous command.
    if (!trips.busy) {
      _approvedChange = null;
      _emit();
    }
    return false;
  }

  void clearAccountRoute() {
    cancelPlan();
    _requestVersion++;
    destination = null;
    origin = null;
    _routes = [];
    selectedRoute = null;
    baselineRevision = 0;
    loading = false;
    routeFailed = false;
    end();
  }

  Future<bool> saveDraft(
    ReportCategory category,
    String place,
    String description,
  ) async {
    if (!initialized ||
        saving ||
        place.trim().isEmpty ||
        place.trim().runes.length > 120 ||
        _drafts.length >= 20 ||
        description.trim().runes.length < 10 ||
        description.runes.length > 700) {
      return false;
    }
    saving = true;
    storageFailed = false;
    _emit();
    final now = DateTime.now().toUtc();
    final next = [
      ..._drafts,
      ReportDraft(
        id: 'demo-${now.microsecondsSinceEpoch}',
        category: category,
        place: place.trim(),
        description: description.trim(),
        createdAt: now,
      ),
    ];
    try {
      await draftStore.write(next);
      _drafts = next;
      return true;
    } catch (_) {
      storageFailed = true;
      return false;
    } finally {
      saving = false;
      _emit();
    }
  }

  Future<void> deleteDrafts() async {
    if (saving || !initialized) return;
    saving = true;
    _emit();
    try {
      await draftStore.write([]);
      _drafts = [];
      storageFailed = false;
    } catch (_) {
      storageFailed = true;
    }
    saving = false;
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _requestVersion++;
    final source = repository;
    if (source is GeographicRouting) source.close();
    routingLocations?.cancel();
    super.dispose();
  }
}
