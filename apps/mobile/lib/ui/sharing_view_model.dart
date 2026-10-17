import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/account_models.dart';
import '../domain/device_location.dart';
import '../domain/sharing.dart';
import '../domain/native_sharing.dart';
import 'account_view_model.dart';

class SharingViewModel extends ChangeNotifier {
  SharingViewModel({
    required this.accounts,
    required this.repository,
    required this.locations,
    this.allowMockLocations = false,
    this.native,
  }) {
    _owner = accounts.userId;
    accounts.addListener(_accountChanged);
    _session = accounts.sessions?.userChanges.listen((_) => _reset());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }
  final AccountViewModel accounts;
  final SharingRepository repository;
  final LocationSource locations;
  final bool allowMockLocations;
  final NativeSharingPlatform? native;
  NativeShareState? nativeState;
  bool _nativeBound = false, _nativeUnknown = false;
  int get consentEpoch => _epoch;
  bool get backgroundSupported =>
      native?.supported == true && repository is ShareDeviceRepository;
  bool get backgroundActive =>
      nativeState?.shareId == own?.id && nativeState?.active == true;
  bool get backgroundMode => _nativeBound || _nativeUnknown || backgroundActive;
  bool get backgroundUnconfirmed => _nativeUnknown;
  bool get sendingUpdates => backgroundMode ? backgroundActive : updating;
  StreamSubscription<String?>? _session;
  Timer? _timer;
  String? _owner;
  int _epoch = 0,
      _selection = 0,
      _ticks = 0,
      _viewVersion = 0,
      _readVersion = 0;
  bool _disposed = false,
      _foreground = true,
      _refreshing = false,
      _viewLoading = false;
  bool busy = false, loaded = false, updating = false;
  String? error;
  TripShare? own;
  CircleDetail? circle;
  final Set<String> selected = {};
  int minutes = 30;
  List<IncomingTrip> incoming = [];
  String? incomingCursor;
  SharedTrip? viewed;
  String? viewingId;
  Stopwatch? _viewAge;
  Duration _pointLease = Duration.zero, _tripLease = Duration.zero;
  String? _requestId, _requestCircle;
  List<String> _requestRecipients = [];
  int _requestDuration = 0;
  DeviceLocation? _pendingPosition;
  int? _pendingSequence;
  String? _pendingShare;
  bool get authorized =>
      accounts.canReport && accounts.signedIn && !accounts.contactsUnconfirmed;
  bool get pendingConsent => _requestId != null;
  bool get viewLoading => _viewLoading;
  bool get active =>
      own?.status == 'active' && own!.expiresAt.isAfter(DateTime.now().toUtc());
  SharedPosition? get position =>
      _foreground &&
          _viewAge != null &&
          _viewAge!.elapsed < _pointLease &&
          _viewAge!.elapsed < _tripLease
      ? viewed?.position
      : null;
  bool get canStart =>
      authorized &&
      loaded &&
      !busy &&
      !active &&
      !pendingConsent &&
      circle != null &&
      selected.isNotEmpty;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int epoch) =>
      !_disposed && epoch == _epoch && authorized && _owner == accounts.userId;
  void _accountChanged() {
    if (_owner != accounts.userId || !authorized) _reset();
  }

  void _reset() {
    _epoch++;
    _selection++;
    _viewVersion++;
    _owner = accounts.userId;
    own = null;
    nativeState = null;
    _nativeBound = _nativeUnknown = false;
    circle = null;
    selected.clear();
    incoming = [];
    incomingCursor = null;
    closeView();
    updating = false;
    busy = loaded = false;
    _refreshing = _viewLoading = false;
    _requestId = _requestCircle = null;
    _requestRecipients = [];
    _pendingPosition = null;
    _pendingSequence = null;
    _pendingShare = null;
    error = null;
    unawaited(locations.cancel());
    _emit();
  }

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (!value) {
      updating = false;
      closeView();
      unawaited(locations.cancel());
    } else {
      unawaited(refresh());
    }
    _emit();
  }

  void _tick() {
    if (!_foreground || !authorized || _disposed) return;
    _ticks++;
    if (!active && updating) updating = false;
    if (_ticks % 15 == 0 && updating && !busy) unawaited(publish());
    if (_ticks % 10 == 0) {
      if (viewingId != null) unawaited(view(viewingId!));
      unawaited(refresh());
    }
    // Remove leased coordinates even when every subsequent request fails.
    if (viewed?.position != null && position == null) {
      viewed = null;
      _viewAge = null;
    }
    _emit();
  }

  Future<void> refresh() async {
    if (!authorized || !_foreground || busy || _refreshing || _disposed) return;
    final epoch = _epoch, version = _readVersion;
    _refreshing = true;
    try {
      final share = await repository.currentShare();
      final trips = await repository.incomingShares();
      NativeShareState? state;
      ShareDeviceGrant? device;
      if (!_current(epoch) || version != _readVersion) return;
      if (backgroundSupported) {
        // A reopened page must reconcile the publisher before allowing Dart
        // capture. Failure keeps the publisher unknown, never foreground.
        _nativeUnknown = true;
        try {
          state = await native!.state();
          if (!_current(epoch) || version != _readVersion) return;
          if (share?.status == 'active') {
            device = await (repository as ShareDeviceRepository).shareDevice(
              share!.id,
            );
          } else if (state.active && state.shareId != null) {
            // A remote stop has already ended the audience. End matching local
            // capture too, including when the current-share endpoint is empty.
            state = await native!.stop(state.shareId!);
          }
        } catch (_) {
          if (_current(epoch) && version == _readVersion) {
            updating = false;
            unawaited(locations.cancel());
          }
          rethrow;
        }
      }
      if (!_current(epoch) || version != _readVersion) return;
      own = share;
      nativeState = state?.shareId == share?.id ? state : null;
      _nativeBound = device?.status == 'active';
      _nativeUnknown = false;
      if (backgroundSupported &&
          [
            'cleanup_pending',
            'starting',
            'stopping',
            'stop_unconfirmed',
          ].contains(state?.phase)) {
        _nativeUnknown = true;
      }
      if (_nativeBound || nativeState?.active == true) {
        updating = false;
        unawaited(locations.cancel());
      }
      incoming = trips.items;
      incomingCursor = trips.nextCursor;
      loaded = true;
      error = null;
      if (share?.circleId != null && circle?.circle.id != share?.circleId) {
        circle = null;
        final detail = await accounts.repository!.circle(share!.circleId!);
        if (_current(epoch) && version == _readVersion) circle = detail;
      }
    } catch (e) {
      if (_current(epoch)) {
        error = _code(e);
      }
    } finally {
      if (_current(epoch)) {
        _refreshing = false;
        _emit();
      }
    }
  }

  Future<void> chooseCircle(String id) async {
    if (!authorized || busy || active || pendingConsent) return;
    final epoch = _epoch, selection = ++_selection;
    circle = null;
    selected.clear();
    error = null;
    _emit();
    try {
      final detail = await accounts.repository!.circle(id);
      if (_current(epoch) && selection == _selection) circle = detail;
    } catch (e) {
      if (_current(epoch) && selection == _selection) error = _code(e);
    }
    if (_current(epoch)) _emit();
  }

  Future<void> moreIncoming() async {
    final cursor = incomingCursor;
    if (cursor == null || busy || !authorized || !_foreground || _refreshing) {
      return;
    }
    await _action(() async {
      final page = await repository.incomingShares(after: cursor);
      return () {
        final ids = incoming.map((trip) => trip.id).toSet();
        incoming = [
          ...incoming,
          ...page.items.where((trip) => ids.add(trip.id)),
        ];
        incomingCursor = page.nextCursor;
      };
    });
  }

  void chooseRecipient(String id, bool value) {
    if (busy ||
        active ||
        pendingConsent ||
        id == accounts.userId ||
        !authorized) {
      return;
    }
    if (circle?.members.any((member) => member.userId == id) != true) return;
    if (value && selected.length < 10) selected.add(id);
    if (!value) selected.remove(id);
    _emit();
  }

  void chooseDuration(int value) {
    if (!busy && !pendingConsent && !active && [15, 30, 60].contains(value)) {
      minutes = value;
      _emit();
    }
  }

  Future<void> start() async {
    if (!canStart || !_foreground) return;
    _requestId = const Uuid().v4();
    _requestCircle = circle!.circle.id;
    _requestRecipients = selected.toList()..sort();
    _requestDuration = minutes * 60;
    await retryConsent();
  }

  Future<void> retryConsent() async {
    if (!authorized || !_foreground || busy || !pendingConsent) return;
    final epoch = _epoch;
    await _action(() async {
      // Explicit retries preserve the exact request and audience. A committed,
      // stopped or expired request can never silently create another session.
      final share = await repository.createShare(
        _requestId!,
        _requestCircle!,
        _requestRecipients,
        _requestDuration,
      );
      return () {
        own = share;
        _requestId = _requestCircle = null;
        _requestRecipients = [];
        loaded = true;
        // Sharing consent also authorizes foreground updates for this visit.
        updating = _foreground && active;
      };
    });
    if (!_current(epoch)) return;
    if ([
      'share_recipient_unavailable',
      'invalid_request',
      'not_found',
      'rate_limited',
      'share_already_active',
    ].contains(error)) {
      _requestId = _requestCircle = null;
      _requestRecipients = [];
      _emit();
    }
    if (updating && error == null) await publish();
  }

  Future<void> stop({String? expectedId}) async {
    if (own == null || busy || !authorized) return;
    if (expectedId != null && expectedId != own!.id) return;
    updating = false;
    final id = own!.id;
    final epoch = _epoch;
    unawaited(locations.cancel());
    await _action(() async {
      // Stop native capture before waiting for the authenticated remote stop.
      // A lost native acknowledgement stays visible even if HTTP succeeds.
      String? nativeError;
      NativeShareState? stoppedState;
      if (backgroundSupported) {
        try {
          final state = await native!.state();
          if (!_current(epoch)) return () {};
          if (state.shareId == id) {
            stoppedState = await native!.stop(id);
            if (_current(epoch)) {
              nativeState = stoppedState;
              _nativeUnknown = stoppedState.active;
              _emit();
            }
          }
        } catch (e) {
          nativeError = _code(e);
        }
      }
      if (!_current(epoch)) return () {};
      final share = await repository.stopShare(id);
      return () {
        own = share;
        _nativeBound = false;
        nativeState = stoppedState;
        _nativeUnknown = nativeError != null;
        error = nativeError;
        _pendingPosition = null;
        _pendingSequence = null;
        _pendingShare = null;
      };
    });
  }

  Future<void> revoke(String userId) async {
    if (own == null || busy || !authorized) return;
    final id = own!.id;
    final epoch = _epoch;
    await _action(() async {
      await repository.revokeShareRecipient(id, userId);
      final share = await repository.currentShare();
      if (_current(epoch) && share == null && backgroundSupported) {
        final state = await native!.state();
        if (_current(epoch) && state.shareId == id) await native!.stop(id);
      }
      return () {
        own = share;
      };
    });
  }

  Future<void> pauseUpdates() async {
    updating = false;
    unawaited(locations.cancel());
    if (backgroundMode && own != null && backgroundSupported) {
      final id = own!.id;
      await _action(() async {
        final state = await native!.pause(id);
        return () {
          nativeState = state;
          _nativeUnknown = false;
        };
      });
      if (error != null) _nativeUnknown = true;
    }
    _emit();
  }

  Future<void> resumeUpdates() async {
    if (!active || busy || !_foreground || !authorized) return;
    if (backgroundMode) return;
    updating = true;
    await publish();
  }

  Future<void> publish() async {
    if (!active ||
        !updating ||
        backgroundMode ||
        !_foreground ||
        busy ||
        !authorized) {
      return;
    }
    final epoch = _epoch, id = own!.id;
    await _action(() async {
      var fix = _pendingShare == id ? _pendingPosition : null;
      var sequence = _pendingShare == id ? _pendingSequence : null;
      if (fix == null) {
        fix = await locations.acquire();
        if (!_current(epoch) || !_foreground || !updating) {
          throw const LocationFailure('location_canceled');
        }
        final problem = fix.problemAt(
          DateTime.now().toUtc(),
          allowMocked: allowMockLocations,
        );
        if (problem != null) throw LocationFailure(problem);
        if (DateTime.now().toUtc().difference(fix.capturedAt) >
                const Duration(seconds: 30) ||
            fix.accuracy < 1) {
          throw const LocationFailure('location_stale');
        }
        sequence = own!.sequence + 1;
        _pendingPosition = fix;
        _pendingSequence = sequence;
        _pendingShare = id;
      }
      await repository.publishSharePosition(id, sequence!, fix);
      final current = await repository.currentShare();
      return () {
        own = current;
        _pendingPosition = null;
        _pendingSequence = null;
        _pendingShare = null;
      };
    });
    if (!_current(epoch)) return;
    if (error != null) {
      updating = false;
      // A definitive refusal is not a lost acknowledgement. Discard the
      // rejected sample so a later explicit resume can capture a new fix.
      if ([
        'stale_position',
        'share_unavailable',
        'invalid_request',
        'native_publisher_active',
      ].contains(error)) {
        _pendingPosition = null;
        _pendingSequence = null;
        _pendingShare = null;
        await refresh();
      }
    }
    _emit();
  }

  Future<void> enableBackground({
    required String expectedId,
    required int expectedEpoch,
    String locale = 'en',
  }) async {
    if (!backgroundSupported ||
        !active ||
        busy ||
        !_foreground ||
        !authorized ||
        own!.id != expectedId ||
        _epoch != expectedEpoch) {
      return;
    }
    final epoch = _epoch;
    // This is an explicit handoff. Every uncertain result disables foreground
    // publishing; retry only follows another visible confirmation.
    updating = false;
    _nativeUnknown = true;
    await _action(() async {
      await locations.cancel();
      if (!await native!.requestNotifications()) {
        throw const ApiFailure('notifications_required');
      }
      if (!_current(epoch) || !_foreground) {
        throw const ApiFailure('account_changed');
      }
      if (!await native!.requestLocationPermission()) {
        throw const ApiFailure('location_permission');
      }
      if (!_current(epoch) || !_foreground) {
        throw const ApiFailure('account_changed');
      }
      final device = repository as ShareDeviceRepository;
      final prepared = await native!.prepare(
        _owner!,
        expectedId,
        device.sharingOrigin,
        locale: locale,
      );
      if (!_current(epoch) || !_foreground) {
        throw const ApiFailure('account_changed');
      }
      final grant = await device.bindShareDevice(
        expectedId,
        prepared.credentialHash,
      );
      if (!_current(epoch) || !_foreground) {
        throw const ApiFailure('account_changed');
      }
      if (grant.status != 'active') throw const ApiFailure('share_unavailable');
      final state = await native!.activate(prepared, grant);
      return () {
        nativeState = state;
        _nativeBound = true;
        _nativeUnknown = !state.active;
        if (!state.active) error = 'sharing_unavailable';
      };
    });
    // Read before interpreting an unknown start receipt; never start a second
    // publisher or extend the audience/deadline to recover an acknowledgement.
    if (_current(epoch) && _foreground) {
      final failure = error;
      await refresh();
      if (_current(epoch) && !backgroundActive && failure != null) {
        error = failure;
        _emit();
      }
    }
  }

  Future<void> view(String id) async {
    if (!authorized || !_foreground || _viewLoading || _disposed) return;
    final epoch = _epoch, version = ++_viewVersion;
    if (viewingId != id) {
      viewed = null;
      _viewAge = null;
    }
    viewingId = id;
    _viewLoading = true;
    final age = Stopwatch()..start();
    _emit();
    try {
      final trip = await repository.sharedTrip(id);
      if (!_current(epoch) || !_foreground || version != _viewVersion) return;
      viewed = trip;
      _viewAge = age;
      _pointLease =
          trip.position?.expiresAt.difference(trip.serverTime) ?? Duration.zero;
      _tripLease = trip.expiresAt.difference(trip.serverTime);
      if (position == null) viewed = null;
    } catch (e) {
      if (_current(epoch) && version == _viewVersion) {
        viewed = null;
        _viewAge = null;
        error = _code(e);
      }
    } finally {
      if (_current(epoch) && version == _viewVersion) {
        _viewLoading = false;
        _emit();
      }
    }
  }

  void closeView() {
    _viewVersion++;
    viewingId = null;
    viewed = null;
    _viewAge = null;
    _viewLoading = false;
    _emit();
  }

  Future<void> decline() async {
    final id = viewingId, userId = accounts.userId;
    if (id == null || userId == null || busy || !authorized) return;
    closeView();
    await _action(() async {
      await repository.revokeShareRecipient(id, userId);
      return () {
        incoming = incoming.where((trip) => trip.id != id).toList();
      };
    });
  }

  Future<void> _action(Future<VoidCallback> Function() work) async {
    if (busy || _disposed || !authorized) return;
    final epoch = _epoch;
    _readVersion++;
    busy = true;
    error = null;
    _emit();
    try {
      final apply = await work();
      if (_current(epoch)) apply();
    } catch (e) {
      if (_current(epoch)) error = _code(e);
    } finally {
      if (_current(epoch)) {
        busy = false;
        _emit();
      }
    }
  }

  String _code(Object e) => e is ApiFailure
      ? e.code
      : e is LocationFailure
      ? e.code
      : 'request_failed';
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    unawaited(_session?.cancel());
    accounts.removeListener(_accountChanged);
    unawaited(locations.cancel());
    super.dispose();
  }
}
