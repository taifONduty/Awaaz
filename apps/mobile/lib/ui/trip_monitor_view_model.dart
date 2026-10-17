import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/account_models.dart';
import '../domain/trip_monitor.dart';
import '../domain/device_location.dart';

class TripMonitorViewModel extends ChangeNotifier {
  TripMonitorViewModel({
    required this.platform,
    required this.locations,
    this.allowFixtures = false,
  });
  final TripPlatform platform;
  final LocationSource locations;
  final bool allowFixtures;
  StreamSubscription<TripSnapshot>? _subscription;
  TripSnapshot snapshot = const TripSnapshot();
  String? owner, error;
  bool busy = false, _disposed = false;
  bool statusConfirmed = false, statusFailure = false, _ownerBound = false;
  int _epoch = 0;
  Map<String, Object?>? _pendingStart;
  String? _pendingIntent;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _acceptSnapshot(TripSnapshot value) {
    // A notification action, expiry or permission loss can stop the service
    // without calling the Flutter stop command. A later trip needs a new UUID.
    if (snapshot.active && !value.active) {
      _pendingStart = null;
      _pendingIntent = null;
    }
    snapshot = value;
    statusConfirmed = true;
    statusFailure = false;
  }

  Future<void> initialize(String? value) async {
    await bindOwner(value);
    if (_disposed) return;
    _subscription ??= platform.changes.listen(
      (value) {
        if (_disposed || value.ownerId != owner) return;
        _acceptSnapshot(value);
        _emit();
      },
      onError: (Object _) {
        if (_disposed) return;
        statusConfirmed = false;
        statusFailure = true;
        _emit();
      },
    );
  }

  Future<void> bindOwner(String? value) async {
    final epoch = ++_epoch;
    owner = value;
    _pendingStart = null;
    _pendingIntent = null;
    error = null;
    statusConfirmed = false;
    statusFailure = false;
    _ownerBound = false;
    snapshot = const TripSnapshot();
    unawaited(locations.cancel());
    _emit();
    try {
      final result = await platform.bindOwner(value);
      if (epoch == _epoch && !_disposed) {
        _ownerBound = true;
        _acceptSnapshot(result);
      }
    } catch (_) {
      if (epoch == _epoch && !_disposed) statusFailure = true;
    }
    _emit();
  }

  Future<bool> _command(
    Future<TripSnapshot> Function() action, {
    bool synchronizing = false,
  }) async {
    if (busy || _disposed) return false;
    final epoch = _epoch;
    busy = true;
    error = null;
    _emit();
    try {
      final result = await action();
      if (epoch != _epoch || _disposed) return false;
      _acceptSnapshot(result);
      return true;
    } on ApiFailure catch (failure) {
      if (epoch == _epoch) error = failure.code;
      return false;
    } on LocationFailure catch (failure) {
      if (epoch == _epoch) error = failure.code;
      return false;
    } catch (_) {
      if (epoch == _epoch) error = 'monitor_unavailable';
      return false;
    } finally {
      if (!_disposed) {
        if (epoch == _epoch && error != null) {
          // A timed-out command may still have reached the native service.
          // Keep its last snapshot, but do not present it as current truth.
          statusConfirmed = false;
          if (synchronizing) {
            statusFailure = true;
            error = null;
          }
        }
        busy = false;
        _emit();
      }
    }
  }

  Future<bool> arm(
    String routeId,
    ApprovedCorridor? corridor,
    String locale,
  ) async {
    if (corridor == null || (corridor.synthetic && !allowFixtures)) {
      error = 'corridor_unavailable';
      _emit();
      return false;
    }
    if (corridor.validUntil != null &&
        !corridor.validUntil!.isAfter(DateTime.now().toUtc())) {
      error = 'route_expired';
      _emit();
      return false;
    }
    if (!platform.supported) {
      error = 'monitor_unsupported';
      _emit();
      return false;
    }
    // A failed owner binding must be retried before any permission prompt or
    // start command; a plain state read cannot establish that binding.
    if ((!statusConfirmed || !_ownerBound) && !await refresh()) return false;
    if (snapshot.active) {
      error = 'monitor_active';
      _emit();
      return false;
    }
    final intent = jsonEncode([
      routeId,
      corridor.graphVersion,
      corridor.riskVersion,
      corridor.points,
      corridor.synthetic,
      corridor.validUntil?.millisecondsSinceEpoch,
      locale,
    ]);
    final epoch = _epoch;
    return _command(() async {
      if (!await platform.requestNotifications()) {
        throw const ApiFailure('notifications_required');
      }
      if (epoch != _epoch || _disposed) {
        throw const ApiFailure('account_changed');
      }
      // Contextual foreground permission/fix check before starting the service.
      final fix = await locations.acquire();
      final problem = fix.problemAt(
        DateTime.now().toUtc(),
        allowMocked: allowFixtures,
      );
      if (problem != null) throw ApiFailure(problem);
      if (epoch != _epoch || _disposed) {
        throw const ApiFailure('account_changed');
      }
      if (corridor.validUntil != null &&
          !corridor.validUntil!.isAfter(DateTime.now().toUtc())) {
        throw const ApiFailure('route_expired');
      }
      if (_pendingIntent != intent) {
        _pendingIntent = intent;
        _pendingStart = {
          'sessionId': const Uuid().v4(),
          'ownerId': owner,
          'routeId': routeId,
          'graphVersion': corridor.graphVersion,
          'riskVersion': corridor.riskVersion,
          'points': corridor.points,
          'revision': 1,
          'durationSeconds': 7200,
          'synthetic': corridor.synthetic,
          'routeValidUntilEpochMs': corridor.validUntil?.millisecondsSinceEpoch,
          'locale': locale,
          'userApproved': true,
        };
      }
      final state = await platform.start(_pendingStart!);
      if (!state.active) throw const ApiFailure('start_unavailable');
      return state;
    });
  }

  Future<bool> refresh() => _command(() async {
    if (_ownerBound) return platform.state();
    final epoch = _epoch;
    final result = await platform.bindOwner(owner);
    if (epoch == _epoch && !_disposed) _ownerBound = true;
    return result;
  }, synchronizing: true);
  Future<bool> stop() async {
    final stopped = await _command(platform.stop);
    if (stopped && !snapshot.active) {
      _pendingStart = null;
      _pendingIntent = null;
      return true;
    }
    if (stopped) {
      error = 'stop_unconfirmed';
      _emit();
    }
    return false;
  }

  Future<bool> acknowledge() {
    final id = snapshot.sessionId;
    return id == null
        ? Future.value(false)
        : _command(() => platform.acknowledge(id));
  }

  Future<bool> replace(
    String routeId,
    ApprovedCorridor corridor,
    String locale,
  ) {
    final id = snapshot.sessionId;
    if (id == null ||
        !snapshot.active ||
        !statusConfirmed ||
        (corridor.synthetic && !allowFixtures)) {
      return Future.value(false);
    }
    final expectedRevision = snapshot.revision + 1;
    final expectedOwner = owner;
    return _command(() async {
      if (corridor.validUntil != null &&
          !corridor.validUntil!.isAfter(DateTime.now().toUtc())) {
        throw const ApiFailure('route_expired');
      }
      final result = await platform.replace({
        'sessionId': id,
        'ownerId': owner,
        'routeId': routeId,
        'graphVersion': corridor.graphVersion,
        'riskVersion': corridor.riskVersion,
        'points': corridor.points,
        'revision': expectedRevision,
        'durationSeconds': 7200,
        'synthetic': corridor.synthetic,
        'routeValidUntilEpochMs': corridor.validUntil?.millisecondsSinceEpoch,
        'locale': locale,
        'userApproved': true,
      });
      if (!result.active ||
          result.sessionId != id ||
          result.ownerId != expectedOwner ||
          result.routeId != routeId ||
          result.revision != expectedRevision) {
        throw const ApiFailure('replacement_unconfirmed');
      }
      return result;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    unawaited(locations.cancel());
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
