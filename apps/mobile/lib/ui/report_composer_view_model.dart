import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/device_location.dart';
import '../domain/models.dart';
import 'account_view_model.dart';

typedef ReportComposerFactory = ReportComposerViewModel Function(
  AccountViewModel accounts,
  LocationSource locations,
);

class ReportComposerViewModel extends ChangeNotifier {
  ReportComposerViewModel({
    required this.accounts,
    required this.locations,
    this.allowMockLocations = false,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _owner = accounts.userId;
    accounts.addListener(_accountChanged);
  }
  final AccountViewModel accounts;
  final LocationSource locations;
  // Synthetic Android fixture entry points may enable this. Production defaults
  // reject mock fixes; this flag is not server-side proof of location integrity.
  final bool allowMockLocations;
  final DateTime Function() _now;
  String? _owner;
  int _version = 0;
  bool _disposed = false, _active = true;
  Timer? _expiry;
  String description = '';
  ReportCategory category = ReportCategory.obstruction;
  DeviceLocation? location;
  String? error;
  bool locating = false, submitting = false, consent = false;
  bool get authorized => accounts.signedIn && accounts.canReport;
  bool get ready =>
      authorized &&
      _active &&
      !locating &&
      !submitting &&
      !accounts.busy &&
      !accounts.loading &&
      consent &&
      description.trim().runes.length >= 10 &&
      description.trim().runes.length <= 700 &&
      location != null &&
      location!.problemAt(_now(), allowMocked: allowMockLocations) == null;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _accountChanged() {
    if (_owner != accounts.userId || !authorized) {
      _owner = accounts.userId;
      description = '';
      category = ReportCategory.obstruction;
      _invalidate();
    }
    _emit();
  }

  void _invalidate() {
    _version++;
    _expiry?.cancel();
    location = null;
    consent = false;
    locating = false;
    error = null;
    unawaited(locations.cancel());
  }

  void setDescription(String value) {
    description = value;
    consent = false;
    _emit();
  }

  void setCategory(ReportCategory value) {
    category = value;
    consent = false;
    _emit();
  }

  void setConsent(bool value) {
    consent = value && location != null && authorized;
    _emit();
  }

  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    if (!value) _invalidate();
    _emit();
  }

  Future<void> locate() async {
    if (!authorized || !_active || locating || submitting || _disposed) return;
    _invalidate();
    final version = _version, owner = _owner;
    locating = true;
    _emit();
    try {
      final fix = await locations.acquire();
      if (_disposed ||
          version != _version ||
          owner != accounts.userId ||
          !_active) {
        return;
      }
      error = fix.problemAt(_now(), allowMocked: allowMockLocations);
      if (error == null) {
        location = fix;
        final remaining =
            const Duration(minutes: 2) - _now().difference(fix.capturedAt);
        _expiry = Timer(remaining + const Duration(milliseconds: 10), () {
          location = null;
          consent = false;
          error = 'location_stale';
          _emit();
        });
      }
    } on LocationFailure catch (failure) {
      if (version == _version && !_disposed) error = failure.code;
    } catch (_) {
      if (version == _version && !_disposed) error = 'location_unavailable';
    } finally {
      if (version == _version && !_disposed) {
        locating = false;
        _emit();
      }
    }
  }

  Future<bool> submit() async {
    if (!ready || _disposed) return false;
    final version = _version, owner = _owner, fix = location!;
    submitting = true;
    error = null;
    _emit();
    try {
      final accepted = await accounts.submitReport(
        category,
        description,
        fix.latitude,
        fix.longitude,
      );
      if (_disposed || version != _version || owner != accounts.userId) {
        return false;
      }
      if (!accepted) {
        error = accounts.error ?? 'request_failed';
        return false;
      }
      description = '';
      consent = false;
      location = null;
      _expiry?.cancel();
      return true;
    } finally {
      if (!_disposed) {
        submitting = false;
        _emit();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _version++;
    _expiry?.cancel();
    accounts.removeListener(_accountChanged);
    unawaited(locations.cancel());
    super.dispose();
  }
}
