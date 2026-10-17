import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/sos_journal.dart';
import '../domain/account_models.dart';
import '../domain/device_location.dart';
import '../domain/sharing.dart';
import '../domain/sos.dart';
import 'account_view_model.dart';

class SosScope {
  SosScope._(this.owner, this.epoch, this.id);
  final String owner, id;
  final int epoch;
  final age = Stopwatch()..start();
}

class SosStartReview extends SosScope {
  SosStartReview._(String owner, int epoch, this.intent, this.names, this.retry)
    : super._(owner, epoch, intent.id);
  final SosIntent intent;
  final List<String> names;
  final bool retry;
}

class SosPreferenceReview extends SosScope {
  SosPreferenceReview._(String owner, int epoch, this.state)
    : super._(owner, epoch, 'preference');
  final SosPreference state;
}

class SosResponseReview extends SosScope {
  SosResponseReview._(
    super.owner,
    super.epoch,
    super.id,
    this.version,
    this.action,
    this.name,
  ) : super._();
  final int version;
  final String action, name;
}

class SosPendingReview extends SosScope {
  SosPendingReview._(String owner, int epoch, this.intent)
    : super._(owner, epoch, intent.id);
  final SosIntent intent;
}

class SosViewModel extends ChangeNotifier {
  SosViewModel({
    required this.accounts,
    required this.repository,
    required this.locations,
    SosJournal? journal,
    this.allowMockLocations = false,
  }) : journal =
           journal ??
           SosJournal(
             values: accounts.journal.values,
             namespace: repository.sosOrigin.toString(),
           ) {
    _owner = accounts.userId;
    accounts.addListener(_accountChanged);
    _session = accounts.sessions?.userChanges.listen((_) => _reset());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }
  final AccountViewModel accounts;
  final SosRepository repository;
  final LocationSource locations;
  final SosJournal journal;
  final bool allowMockLocations;
  StreamSubscription<String?>? _session;
  Timer? _timer;
  Future<void>? _refreshTask;
  String? _owner;
  int _epoch = 0,
      _selection = 0,
      _readVersion = 0,
      _viewVersion = 0,
      _locationVersion = 0,
      _ticks = 0,
      _knownSequence = 0;
  bool _disposed = false,
      _foreground = true,
      _refreshing = false,
      _publishing = false,
      _journalReady = false;
  bool busy = false,
      loaded = false,
      contactsLoading = false,
      viewLoading = false,
      locating = false,
      updating = false;
  String? error, locationError, notice, circleId, viewingId;
  SosCapability? capability;
  SosPreference? preference;
  bool preferenceUnconfirmed = false;
  (bool, int)? _pendingPreference;
  SosIntent? pending;
  SosControl? own;
  SosView? viewed;
  List<SosContact> contacts = [];
  List<SosIncoming> incoming = [];
  String? incomingCursor;
  final selected = <String>{};
  bool allowLocation = false;
  DateTime? lastUpload;
  Stopwatch? _ownAge, _viewAge, _contactsAge;
  Duration _ownLease = Duration.zero,
      _viewLease = Duration.zero,
      _pointLease = Duration.zero;
  DeviceLocation? _pendingPoint;
  int? _pointSequence;
  bool get authorized =>
      accounts.signedIn && accounts.canReport && !accounts.contactsUnconfirmed;
  bool get active =>
      own?.status == 'active' &&
      _ownAge != null &&
      _ownAge!.elapsed < _ownLease;
  bool get canStart =>
      authorized &&
      loaded &&
      _journalReady &&
      !busy &&
      !contactsLoading &&
      capability?.storage == true &&
      pending == null &&
      own?.status != 'active' &&
      circleId != null &&
      selected.isNotEmpty &&
      _contactsAge != null &&
      _contactsAge!.elapsed < const Duration(seconds: 30);
  bool get canRetry =>
      authorized &&
      !busy &&
      pending?.phase == 'activation' &&
      _contactsAge != null &&
      _contactsAge!.elapsed < const Duration(seconds: 30) &&
      own?.status != 'active' &&
      pending!.circleId == circleId &&
      pending!.recipients.every((id) => contacts.any((c) => c.id == id));
  SharedPosition? get position =>
      _foreground &&
          _viewAge != null &&
          _viewAge!.elapsed < _viewLease &&
          _viewAge!.elapsed < _pointLease
      ? viewed?.position
      : null;
  bool _current(int epoch) =>
      !_disposed && epoch == _epoch && authorized && _owner == accounts.userId;
  void _require(int epoch) {
    if (!_current(epoch)) throw const ApiFailure('session_changed');
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _scope(SosScope review) =>
      _current(review.epoch) &&
      review.owner == _owner &&
      _foreground &&
      review.age.elapsed < const Duration(minutes: 1);
  void _accountChanged() {
    if (_owner != accounts.userId || !authorized) {
      _reset();
    } else if (!loaded) {
      unawaited(refresh());
    }
  }

  void _reset() {
    _epoch++;
    _refreshTask = null;
    _selection++;
    _readVersion++;
    _viewVersion++;
    _owner = accounts.userId;
    own = null;
    pending = null;
    viewed = null;
    viewingId = null;
    preference = null;
    capability = null;
    contacts = [];
    selected.clear();
    incoming = [];
    incomingCursor = null;
    circleId = null;
    _ownAge = _viewAge = _contactsAge = null;
    _knownSequence = 0;
    lastUpload = null;
    allowLocation = false;
    error = notice = locationError = null;
    _pendingPreference = null;
    preferenceUnconfirmed = false;
    busy = loaded = contactsLoading = viewLoading = _refreshing =
        _journalReady = false;
    pauseLocation();
    _emit();
  }

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (!value) {
      pauseLocation();
      closeView();
    } else {
      unawaited(refresh());
    }
    _emit();
  }

  void _tick() {
    if (!_foreground || !authorized || _disposed) return;
    _ticks++;
    if (!active && updating) pauseLocation();
    if (_viewAge != null && _viewAge!.elapsed >= _viewLease) {
      closeView();
    } else if (viewed?.position != null &&
        position == null &&
        _pointLease > Duration.zero) {
      // The point's lease can end before the request itself. Remove the map
      // while keeping the person's response controls available.
      _pointLease = Duration.zero;
      _emit();
    }
    if (_ticks % 15 == 0 && updating) unawaited(publish());
    if (_ticks % 10 == 0 && !busy) {
      unawaited(refresh());
      if (viewingId != null) unawaited(view(viewingId!));
    }
  }

  void _applyOwn(SosControl? value, Stopwatch age) {
    if (value?.id != own?.id) {
      pauseLocation();
      _knownSequence = 0;
      lastUpload = null;
    }
    own = value;
    _ownAge = age;
    _ownLease = value?.expiresAt.difference(value.serverTime) ?? Duration.zero;
    _knownSequence = math.max(_knownSequence, value?.sequence ?? 0);
    if (!active) pauseLocation();
  }

  Future<void> refresh() {
    final existing = _refreshTask;
    if (existing != null) return existing;
    late final Future<void> task;
    task = _refreshOnce().whenComplete(() {
      if (identical(_refreshTask, task)) _refreshTask = null;
    });
    _refreshTask = task;
    return task;
  }

  Future<void> _refreshOnce() async {
    if (!authorized || !_foreground || busy || _refreshing || _disposed) return;
    final epoch = _epoch, version = _readVersion, actor = _owner!;
    final age = Stopwatch()..start();
    _refreshing = true;
    try {
      final saved = await journal.read(actor);
      _require(epoch);
      final (status, current, receiving, page) = await (
        repository.sosCapability(),
        repository.currentSos(),
        repository.sosPreference(),
        repository.incomingSos(),
      ).wait;
      if (!_current(epoch) || version != _readVersion || !_foreground) return;
      pending = saved;
      _journalReady = true;
      capability = status;
      preference = receiving;
      final decision = _pendingPreference;
      if (decision != null &&
          receiving.allowed == decision.$1 &&
          receiving.version == decision.$2 + 1) {
        _pendingPreference = null;
        preferenceUnconfirmed = false;
      }
      _applyOwn(current, age);
      incoming = page.items;
      incomingCursor = page.nextCursor;
      loaded = true;
      error = null;
      if (saved != null) {
        final requestAge = Stopwatch()..start();
        try {
          final receipt = await repository.sosRequest(saved.id);
          _require(epoch);
          if (version != _readVersion || !_foreground) return;
          if (saved.phase == 'activation' || receipt.status != 'active') {
            final cleared = await journal.acknowledge(
              actor,
              saved.id,
              saved.phase,
            );
            _require(epoch);
            if (version != _readVersion) return;
            pending = cleared ? null : await journal.read(actor);
            _require(epoch);
            _applyOwn(receipt, requestAge);
          }
        } on ApiFailure catch (failure) {
          if (failure.code != 'not_found') rethrow;
        }
      }
      if (!_current(epoch) || version != _readVersion) return;
      circleId ??= pending?.circleId ?? own?.circleId;
      if (pending != null) {
        circleId = pending!.circleId;
        selected
          ..clear()
          ..addAll(pending!.recipients);
      }
      if (circleId != null) await _contacts(circleId!, epoch, _selection);
    } catch (e) {
      if (_current(epoch)) {
        error = _code(e);
        closeView();
      }
    } finally {
      if (_current(epoch)) {
        _refreshing = false;
        _emit();
      }
    }
  }

  Future<void> _contacts(String id, int epoch, int selection) async {
    final age = Stopwatch()..start();
    try {
      final values = await repository.sosContacts(id);
      if (_current(epoch) && _selection == selection && circleId == id) {
        contacts = values;
        _contactsAge = age;
        if (pending == null) {
          selected.removeWhere((id) => !contacts.any((c) => c.id == id));
        }
      }
    } catch (_) {
      if (_current(epoch) && _selection == selection) {
        contacts = [];
        _contactsAge = null;
      }
      rethrow;
    }
  }

  Future<void> chooseCircle(String id) async {
    if (!authorized || busy || pending != null || own?.status == 'active') {
      return;
    }
    final epoch = _epoch, selection = ++_selection;
    circleId = id;
    contacts = [];
    selected.clear();
    contactsLoading = true;
    error = null;
    _emit();
    try {
      await _contacts(id, epoch, selection);
    } catch (e) {
      if (_current(epoch)) error = _code(e);
    } finally {
      if (_current(epoch) && _selection == selection) {
        contactsLoading = false;
        _emit();
      }
    }
  }

  void chooseRecipient(String id, bool value) {
    if (busy ||
        pending != null ||
        own?.status == 'active' ||
        !contacts.any((c) => c.id == id)) {
      return;
    }
    if (value && selected.length < 10) selected.add(id);
    if (!value) selected.remove(id);
    _emit();
  }

  void chooseLocation(bool value) {
    if (busy || pending != null || own?.status == 'active') return;
    allowLocation = value;
    _emit();
  }

  SosStartReview? reviewStart({bool retry = false}) {
    if (retry ? !canRetry : !canStart) return null;
    final intent = retry
        ? pending!
        : SosIntent.create(circleId!, selected, allowLocation);
    if (!intent.recipients.every((id) => contacts.any((c) => c.id == id))) {
      return null;
    }
    return SosStartReview._(
      _owner!,
      _epoch,
      intent,
      List.unmodifiable(
        intent.recipients.map(
          (id) => contacts.firstWhere((c) => c.id == id).name,
        ),
      ),
      retry,
    );
  }

  Future<void> start(SosStartReview review) async {
    if (!_scope(review) || busy || own?.status == 'active') return;
    final intent = review.intent, actor = review.owner;
    final age = Stopwatch()..start();
    final result = await _action((epoch) async {
      if (!review.retry) await journal.prepare(actor, intent);
      _require(epoch);
      pending = await journal.read(actor);
      _require(epoch);
      if (!_foreground ||
          pending?.id != intent.id ||
          pending?.phase != 'activation') {
        throw const ApiFailure('sos_pending_intent');
      }
      final receipt = await repository.createSos(pending!);
      _require(epoch);
      _applyOwn(receipt, age);
      final cleared = await journal.acknowledge(actor, intent.id, 'activation');
      _require(epoch);
      pending = cleared ? null : await journal.read(actor);
      _require(epoch);
      return receipt;
    });
    if (result != null && _scope(review) && pending == null) {
      updating = result.status == 'active' && result.shareLocation;
      if (updating) unawaited(publish());
    }
    _emit();
  }

  SosPendingReview? reviewPending() => pending == null || !authorized
      ? null
      : SosPendingReview._(_owner!, _epoch, pending!);
  Future<void> withdraw(SosPendingReview review) async {
    if (!_scope(review) ||
        (pending != null && pending!.id != review.id) ||
        busy) {
      return;
    }
    pauseLocation();
    await _action((epoch) async {
      pending = await journal.withdraw(review.owner, review.intent);
      _require(epoch);
      await repository.withdrawSos(review.id);
      _require(epoch);
      final cleared = await journal.acknowledge(
        review.owner,
        review.id,
        'withdrawal',
      );
      _require(epoch);
      pending = cleared ? null : await journal.read(review.owner);
      _require(epoch);
      final age = Stopwatch()..start();
      final current = await repository.currentSos();
      _require(epoch);
      _applyOwn(current, age);
      notice = 'withdrawn';
      return true;
    });
  }

  SosScope? reviewOwn() =>
      own == null || !authorized ? null : SosScope._(_owner!, _epoch, own!.id);
  Future<void> end(SosScope review, String outcome) async {
    if (!_scope(review) || own?.id != review.id || busy) return;
    pauseLocation();
    await _action((epoch) async {
      final age = Stopwatch()..start();
      final receipt = await repository.endSos(review.id, outcome);
      _require(epoch);
      _applyOwn(receipt, age);
      notice = 'ended';
      return true;
    });
  }

  Future<SosPreferenceReview?> reviewPreference() async {
    final result = await _action((epoch) async {
      final value = await repository.sosPreference();
      _require(epoch);
      preference = value;
      return SosPreferenceReview._(_owner!, epoch, value);
    });
    return result;
  }

  Future<void> setPreference(SosPreferenceReview review, bool allowed) async {
    if (!_scope(review) || busy) return;
    _pendingPreference = (allowed, review.state.version);
    preferenceUnconfirmed = true;
    if (!allowed) {
      closeView();
      incoming = [];
    }
    await _action((epoch) async {
      final value = await repository.setSosPreference(
        allowed,
        review.state.version,
      );
      _require(epoch);
      preference = value;
      _pendingPreference = null;
      preferenceUnconfirmed = false;
      notice = 'preference';
      return true;
    });
  }

  Future<void> more() async {
    final cursor = incomingCursor;
    if (cursor == null || busy || !_foreground) return;
    await _action((epoch) async {
      final page = await repository.incomingSos(after: cursor);
      _require(epoch);
      final ids = incoming.map((i) => i.id).toSet();
      incoming = [...incoming, ...page.items.where((i) => ids.add(i.id))];
      incomingCursor = page.nextCursor;
      return true;
    });
  }

  Future<void> view(String id) async {
    if (!authorized ||
        !_foreground ||
        viewLoading ||
        _disposed ||
        (_pendingPreference?.$1 == false)) {
      return;
    }
    final epoch = _epoch, version = ++_viewVersion;
    if (viewingId != id) {
      viewed = null;
      _viewAge = null;
    }
    viewingId = id;
    viewLoading = true;
    final age = Stopwatch()..start();
    _emit();
    try {
      final value = await repository.viewSos(id);
      if (!_current(epoch) || !_foreground || version != _viewVersion) return;
      viewed = value;
      _viewAge = age;
      _viewLease = value.expiresAt.difference(value.serverTime);
      _pointLease =
          value.position?.expiresAt.difference(value.serverTime) ??
          Duration.zero;
      if (_viewAge!.elapsed >= _viewLease) closeView();
    } catch (e) {
      if (_current(epoch) && version == _viewVersion) {
        closeView();
        error = _code(e);
      }
    } finally {
      if (_current(epoch) && version == _viewVersion) {
        viewLoading = false;
        _emit();
      }
    }
  }

  void closeView() {
    _viewVersion++;
    viewed = null;
    viewingId = null;
    _viewAge = null;
    viewLoading = false;
    _emit();
  }

  SosResponseReview? reviewResponse(String action) {
    final value = viewed;
    if (value == null ||
        value.status != 'active' ||
        busy ||
        !sosResponses.contains(action)) {
      return null;
    }
    return SosResponseReview._(
      _owner!,
      _epoch,
      value.id,
      value.responseVersion,
      action,
      value.name,
    );
  }

  Future<void> respond(SosResponseReview review) async {
    if (!_scope(review) || viewingId != review.id || busy) return;
    closeView();
    final result = await _action((epoch) async {
      await repository.respondSos(review.id, review.action, review.version);
      _require(epoch);
      notice = 'response';
      return true;
    });
    if (result == true && _current(review.epoch) && _foreground) {
      await view(review.id);
    }
  }

  SosScope? reviewViewed() => viewed == null || !authorized
      ? null
      : SosScope._(_owner!, _epoch, viewed!.id);
  Future<void> decline(SosScope review) async {
    if (!_scope(review) || viewingId != review.id || busy) return;
    closeView();
    await _action((epoch) async {
      await repository.declineSos(review.id);
      _require(epoch);
      incoming = incoming.where((i) => i.id != review.id).toList();
      notice = 'declined';
      return true;
    });
  }

  void pauseLocation() {
    _locationVersion++;
    updating = false;
    locating = false;
    _pendingPoint = null;
    _pointSequence = null;
    unawaited(locations.cancel());
    _emit();
  }

  Future<void> resumeLocation(SosScope review) async {
    if (!_scope(review) ||
        !active ||
        own?.id != review.id ||
        own?.shareLocation != true) {
      return;
    }
    final version = _locationVersion, age = Stopwatch()..start();
    try {
      final current = await repository.currentSos();
      if (!_scope(review) ||
          _locationVersion != version ||
          current?.id != review.id) {
        return;
      }
      _applyOwn(current, age);
      if (!active || current?.shareLocation != true) return;
      updating = true;
      unawaited(publish());
    } catch (e) {
      if (_current(review.epoch)) locationError = _code(e);
    }
    _emit();
  }

  Future<void> publish() async {
    if (!authorized ||
        !_foreground ||
        busy ||
        !active ||
        !updating ||
        _publishing) {
      return;
    }
    final epoch = _epoch, version = _locationVersion, id = own!.id;
    _publishing = true;
    locating = true;
    locationError = null;
    _emit();
    try {
      var fix = _pendingPoint;
      if (fix == null) {
        fix = await locations.acquire();
        if (!_current(epoch) ||
            !_foreground ||
            version != _locationVersion ||
            !updating ||
            own?.id != id) {
          return;
        }
        final issue = fix.problemAt(
          DateTime.now().toUtc(),
          allowMocked: allowMockLocations,
        );
        if (issue != null) throw LocationFailure(issue);
        if (DateTime.now().toUtc().difference(fix.capturedAt) >
            const Duration(seconds: 30)) {
          throw const LocationFailure('location_stale');
        }
        _pendingPoint = fix;
        _pointSequence = _knownSequence + 1;
      }
      final time = await repository.publishSosPosition(
        id,
        _pointSequence!,
        fix,
      );
      if (_current(epoch) && version == _locationVersion && own?.id == id) {
        _knownSequence = math.max(_knownSequence, _pointSequence!);
        lastUpload = time;
        _pendingPoint = null;
        _pointSequence = null;
      }
    } catch (e) {
      if (_current(epoch) && version == _locationVersion) {
        updating = false;
        locationError = _code(e);
        _pendingPoint = null;
        _pointSequence = null;
      }
    } finally {
      _publishing = false;
      if (_current(epoch) && version == _locationVersion) {
        locating = false;
        _emit();
      }
    }
  }

  Future<T?> _action<T>(Future<T> Function(int epoch) work) async {
    if (busy || !authorized || _disposed) return null;
    final epoch = _epoch;
    _readVersion++;
    busy = true;
    error = notice = null;
    _emit();
    try {
      final result = await work(epoch);
      return _current(epoch) ? result : null;
    } catch (e) {
      if (_current(epoch)) error = _code(e);
      return null;
    } finally {
      if (_current(epoch)) {
        busy = false;
        _emit();
      }
    }
  }

  String _code(Object error) => error is ApiFailure
      ? error.code
      : error is LocationFailure
      ? error.code
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
