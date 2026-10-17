import 'package:flutter/foundation.dart';

import '../data/geographic_repository.dart';
import '../domain/account_models.dart';
import '../domain/device_location.dart';
import '../domain/models.dart';
import '../domain/trip_monitor.dart';
import 'journey_view_model.dart';
import 'trip_monitor_view_model.dart';

/// A temporary comparison. Only the journey owns an approved native change.
class RouteChangeViewModel extends ChangeNotifier {
  RouteChangeViewModel({required this.journey, required this.trips})
    : previous = journey.selectedRoute!,
      destination = journey.destination!,
      expected = trips.snapshot {
    journey.addListener(_changed);
    trips.addListener(_changed);
  }
  final JourneyViewModel journey;
  final TripMonitorViewModel trips;
  final RouteOption previous;
  final Destination destination;
  final TripSnapshot expected;
  List<RouteOption> routes = const [];
  RouteOption? selected, _approved;
  GeoPoint? origin;
  String? error;
  bool loading = false, applying = false, _disposed = false;
  int _generation = 0;
  bool get ownerChanged =>
      trips.owner != expected.ownerId || journey.destination == null;
  bool get applied =>
      _approved != null &&
      journey.selectedRoute == _approved &&
      journey.baselineRevision == expected.revision + 1;
  bool get available =>
      journey.phase == JourneyPhase.active &&
      journey.selectedRoute == previous &&
      trips.owner == expected.ownerId &&
      trips.statusConfirmed &&
      trips.snapshot.active &&
      trips.snapshot.sessionId == expected.sessionId &&
      trips.snapshot.routeId == previous.id &&
      trips.snapshot.revision == expected.revision;
  bool get busy => loading || applying || trips.busy;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _changed() {
    if (_disposed) return;
    if (trips.owner != expected.ownerId ||
        journey.phase == JourneyPhase.idle ||
        (trips.statusConfirmed && !available && !applying)) {
      cancel();
    } else {
      _emit();
    }
  }

  Future<void> search() async {
    if (!available || busy || journey.replacementPending) return;
    final repository = journey.repository;
    final locations = journey.routingLocations;
    if (repository is! GeographicRouting || locations == null) {
      error = 'routing_unavailable';
      _emit();
      return;
    }
    final generation = ++_generation;
    routes = const [];
    selected = null;
    origin = null;
    error = null;
    loading = true;
    _emit();
    try {
      final fix = await locations.acquire();
      if (_disposed || generation != _generation || !available) return;
      final problem = fix.problemAt(
        DateTime.now().toUtc(),
        allowMocked: journey.allowMockedLocations,
      );
      if (problem != null) throw ApiFailure(problem);
      final point = GeoPoint(fix.latitude, fix.longitude);
      final result = await repository.routesFrom(
        point,
        destination,
        journey.mode,
      );
      if (_disposed || generation != _generation || !available) return;
      if (result.isEmpty || result.any((route) => route.corridor == null)) {
        throw const ApiFailure('invalid_response');
      }
      routes = List.unmodifiable(result);
      selected = routes.first;
      origin = point;
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error = failure is ApiFailure
          ? failure.code
          : failure is LocationFailure
          ? failure.code
          : 'routing_unavailable';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _emit();
      }
    }
  }

  void select(RouteOption route) {
    if (busy ||
        !available ||
        journey.replacementPending ||
        !routes.contains(route)) {
      return;
    }
    selected = route;
    _emit();
  }

  Future<bool> apply(String locale) async {
    final route = selected, point = origin;
    if (busy ||
        !available ||
        route == null ||
        point == null ||
        journey.replacementPending) {
      return false;
    }
    applying = true;
    error = null;
    _approved = route;
    _emit();
    final success = await journey.replaceRoute(
      previous: previous,
      next: route,
      newOrigin: point,
      expected: expected,
      trips: trips,
      locale: locale,
    );
    if (!_disposed) {
      applying = false;
      if (!success) error = trips.error ?? 'route_change_unconfirmed';
      _emit();
    }
    return success;
  }

  Future<void> reconcile() async {
    if (busy) return;
    await trips.refresh();
    if (_disposed) return;
    journey.reconcileRouteChange(trips);
    error = applied
        ? null
        : available
        ? 'route_change_not_applied'
        : 'route_change_unconfirmed';
    _emit();
  }

  void cancel() {
    ++_generation;
    if (loading) {
      final source = journey.repository;
      if (source is GeographicRouting) source.cancel();
      journey.routingLocations?.cancel();
    }
    loading = false;
    routes = const [];
    selected = null;
    origin = null;
    error = 'planning_canceled';
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    journey.removeListener(_changed);
    trips.removeListener(_changed);
    super.dispose();
  }
}
