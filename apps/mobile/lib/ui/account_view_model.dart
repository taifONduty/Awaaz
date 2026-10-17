import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/command_journal.dart';
import '../data/private_values.dart';
import '../domain/account_models.dart';
import '../domain/models.dart';
import '../domain/pending_write.dart';

String asciiDigits(String text) => String.fromCharCodes(
  text.runes.map(
    (rune) => rune >= 0x09e6 && rune <= 0x09ef ? rune - 0x09e6 + 0x30 : rune,
  ),
);

String? bangladeshPhone(String input) {
  final value = asciiDigits(input).replaceAll(RegExp(r'[\s()-]'), '');
  if (RegExp(r'^01[3-9]\d{8}$').hasMatch(value)) {
    return '+880${value.substring(1)}';
  }
  return RegExp(r'^\+8801[3-9]\d{8}$').hasMatch(value) ? value : null;
}

/// A read of one decision, bound to this exact account lifetime. Dialogs cannot
/// carry approval across logout/login, even when the same account returns.
class BlockReview {
  BlockReview._(this.state, this._owner, this._epoch);
  final ContactBlockState state;
  final String _owner;
  final int _epoch;
}

class AccountViewModel extends ChangeNotifier {
  AccountViewModel({
    this.sessions,
    this.repository,
    this.configurationProblem = false,
    this.onClose,
    CommandJournal? journal,
    DateTime Function()? now,
  }) : journal =
           journal ??
           CommandJournal(values: MemoryPrivateValues(), namespace: 'injected'),
       _now = now ?? DateTime.now {
    _identity = sessions?.userId;
    _subscription = sessions?.userChanges.listen(_sessionChanged);
  }
  final SessionRepository? sessions;
  final AccountRepository? repository;
  final CommandJournal journal;
  final bool configurationProblem;
  final VoidCallback? onClose;
  final DateTime Function() _now;
  StreamSubscription<String?>? _subscription;
  Timer? _expiryTimer;
  Timer? _resendTimer;
  String? _identity;
  bool _disposed = false;
  bool _signingOut = false;
  int _epoch = 0;
  int _loadVersion = 0;
  int _selectionVersion = 0;
  List<PendingWrite> _pendingWrites = [];
  DateTime? _codeSentAt;
  OwnAccount? account;
  List<TrustedCircle> _circles = [];
  List<CircleInvitation> _invites = [];
  List<PrivateRoadReport> _reports = [];
  List<PublishedRoadEvent> _events = [];
  List<BlockedContact> _blockedContacts = [];
  String? blocksCursor;
  bool blocksLoaded = false;
  BlockReview? _pendingBlock;
  bool get contactsUnconfirmed => _pendingBlock != null;
  List<BlockedContact> get blockedContacts =>
      List.unmodifiable(_blockedContacts);
  CircleDetail? detail;
  CreatedInvitation? _createdInvite;
  CreatedInvitation? get createdInvite =>
      _createdInvite?.expiresAt.isAfter(_now()) == true ? _createdInvite : null;
  set createdInvite(CreatedInvitation? value) => _createdInvite = value;
  String? nextCursor;
  String? error;
  String? reportReceipt;
  String? codePhone;
  bool busy = false;
  bool loading = false;
  bool initialized = false;
  bool get configured => sessions != null && repository != null;
  bool get signedIn => configured && _identity != null;
  String? get userId => _identity;
  bool get canReport => account?.profile != null && account!.phoneVerified;
  bool get canResend =>
      _codeSentAt == null ||
      _now().difference(_codeSentAt!) >= const Duration(seconds: 60);
  List<TrustedCircle> get circles => List.unmodifiable(_circles);
  List<CircleInvitation> get invitations => List.unmodifiable(
    _invites.where((invitation) => invitation.expiresAt.isAfter(_now())),
  );
  List<PrivateRoadReport> get reports => List.unmodifiable(_reports);
  List<PendingWrite> get pendingWrites => List.unmodifiable(_pendingWrites);
  List<PublishedRoadEvent> get events => List.unmodifiable(
    _events.where((event) => event.expiresAt.isAfter(_now())),
  );
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int epoch) =>
      !_disposed && epoch == _epoch && sessions?.userId == _identity;
  void _clearPrivate() {
    _expiryTimer?.cancel();
    _resendTimer?.cancel();
    account = null;
    _circles = [];
    _invites = [];
    _reports = [];
    _events = [];
    _blockedContacts = [];
    blocksCursor = null;
    blocksLoaded = false;
    _pendingBlock = null;
    detail = null;
    _selectionVersion++;
    createdInvite = null;
    nextCursor = null;
    reportReceipt = null;
    _pendingWrites = [];
    codePhone = null;
    _codeSentAt = null;
    error = null;
  }

  void _sessionChanged(String? id) {
    if (_disposed || id == _identity) return;
    _identity = id;
    _epoch++;
    _loadVersion++;
    _clearPrivate();
    busy = _signingOut;
    loading = false;
    _emit();
    if (id != null && !_signingOut) unawaited(refresh());
  }

  Future<void> initialize() async {
    initialized = true;
    await refresh();
  }

  void _expiry() {
    _expiryTimer?.cancel();
    final invite = createdInvite;
    final active = [
      ...events.map((event) => event.expiresAt),
      ...invitations.map((invitation) => invitation.expiresAt),
      if (invite != null) invite.expiresAt,
    ];
    if (active.isEmpty) return;
    final first = active.reduce((a, b) => a.isBefore(b) ? a : b);
    _expiryTimer = Timer(
      first.difference(_now()) + const Duration(milliseconds: 10),
      () {
        if (_createdInvite != null &&
            !_createdInvite!.expiresAt.isAfter(_now())) {
          _createdInvite = null;
        }
        _emit();
        _expiry();
      },
    );
  }

  Future<void> _load(int epoch) async {
    final version = ++_loadVersion;
    loading = true;
    _emit();
    try {
      final me = await repository!.me();
      if (!_current(epoch) || version != _loadVersion) return;
      var circles = <TrustedCircle>[];
      var invites = <CircleInvitation>[];
      var events = <PublishedRoadEvent>[];
      var page = ReportPageResult(items: [], nextCursor: null);
      var pending = <PendingWrite>[];
      CircleDetail? selected;
      final selectionVersion = _selectionVersion;
      if (me.profile != null) {
        final values = await Future.wait<Object>([
          repository!.circles(),
          repository!.invitations(),
          repository!.reports(),
          repository!.events(),
          journal.read(me.userId),
        ]);
        circles = values[0] as List<TrustedCircle>;
        invites = values[1] as List<CircleInvitation>;
        page = values[2] as ReportPageResult;
        events = values[3] as List<PublishedRoadEvent>;
        pending = values[4] as List<PendingWrite>;
        final selectedId = detail?.circle.id;
        if (selectedId != null &&
            circles.any((circle) => circle.id == selectedId)) {
          selected = await repository!.circle(selectedId);
        }
      }
      if (!_current(epoch) || version != _loadVersion) return;
      account = me;
      _circles = contactsUnconfirmed ? [] : circles;
      _invites = contactsUnconfirmed ? [] : invites;
      _reports = page.items;
      nextCursor = page.nextCursor;
      _events = events;
      _pendingWrites = pending;
      if (selectionVersion == _selectionVersion) {
        detail = contactsUnconfirmed ? null : selected;
        if (selected == null) createdInvite = null;
      }
      _expiry();
    } on ApiFailure catch (failure) {
      if (_current(epoch) && version == _loadVersion) {
        if ([
          'unauthenticated',
          'session_changed',
          'not_found',
        ].contains(failure.code)) {
          _clearPrivate();
        }
        error = failure.code;
      }
    } catch (_) {
      if (_current(epoch) && version == _loadVersion) error = 'request_failed';
    } finally {
      if (_current(epoch) && version == _loadVersion) {
        loading = false;
        _emit();
      }
    }
  }

  Future<void> refresh() async {
    if (!signedIn || _disposed || busy) {
      _emit();
      return;
    }
    error = null;
    await _load(_epoch);
  }

  Future<bool> _command(
    Future<void> Function() action, {
    bool reload = true,
  }) async {
    if (!signedIn || busy || loading || _disposed) return false;
    final epoch = _epoch;
    busy = true;
    error = null;
    _emit();
    try {
      await action();
      if (!_current(epoch)) return false;
      if (reload) await _load(epoch);
      return _current(epoch);
    } on ApiFailure catch (failure) {
      if (_current(epoch)) {
        if (['unauthenticated', 'session_changed'].contains(failure.code)) {
          _clearPrivate();
        }
        error = failure.code;
      }
      return false;
    } catch (_) {
      if (_current(epoch)) error = 'request_failed';
      return false;
    } finally {
      if (_current(epoch)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<bool> requestCode(String input) async {
    if (!configured || busy || !canResend || signedIn) return false;
    final phone = bangladeshPhone(input);
    if (phone == null) {
      error = 'invalid_phone';
      _emit();
      return false;
    }
    final epoch = _epoch;
    busy = true;
    error = null;
    _emit();
    try {
      await sessions!.requestCode(phone);
      if (!_current(epoch)) return false;
      codePhone = phone;
      _codeSentAt = _now();
      _resendTimer?.cancel();
      _resendTimer = Timer(const Duration(seconds: 60), _emit);
      return true;
    } on ApiFailure catch (failure) {
      if (_current(epoch)) error = failure.code;
      return false;
    } catch (_) {
      if (_current(epoch)) error = 'auth_unavailable';
      return false;
    } finally {
      if (_current(epoch)) {
        busy = false;
        _emit();
      }
    }
  }

  void changePhone() {
    if (!busy) {
      codePhone = null;
      error = null;
      _emit();
    }
  }

  Future<bool> verifyCode(String input) async {
    if (!configured || busy || codePhone == null) return false;
    final code = asciiDigits(input.trim());
    if (!RegExp(r'^\d{6,10}$').hasMatch(code)) {
      error = 'invalid_code';
      _emit();
      return false;
    }
    final epoch = _epoch;
    busy = true;
    error = null;
    _emit();
    try {
      await sessions!.verifyCode(codePhone!, code);
      return !_disposed && sessions!.userId != null;
    } on ApiFailure catch (failure) {
      if (_current(epoch)) error = failure.code;
      return false;
    } catch (_) {
      if (_current(epoch)) error = 'auth_unavailable';
      return false;
    } finally {
      if (_current(epoch)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> signOut() async {
    if (!configured || busy) return;
    _signingOut = true;
    _epoch++;
    _loadVersion++;
    _clearPrivate();
    busy = true;
    loading = false;
    _emit();
    try {
      await sessions!.signOut();
    } on ApiFailure catch (failure) {
      if (!_disposed) error = failure.code;
    } catch (_) {
      if (!_disposed) error = 'signout_local_only';
    } finally {
      if (!_disposed) {
        _signingOut = false;
        _identity = sessions!.userId;
        busy = false;
        _emit();
      }
    }
  }

  Future<bool> saveProfile(String name, String locale, bool adult) async {
    if (!adult || name.trim().isEmpty || name.trim().runes.length > 80) {
      error = 'invalid_request';
      _emit();
      return false;
    }
    return _command(() async {
      await repository!.saveProfile(name.trim(), locale);
    });
  }

  Future<bool> createCircle(String name) async {
    if (!signedIn || busy || loading || contactsUnconfirmed) return false;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.runes.length > 80) {
      error = 'invalid_request';
      _emit();
      return false;
    }
    return _journaled(() => PendingWrite.circle(trimmed, _now()));
  }

  Future<bool> selectCircle(String id) {
    if (contactsUnconfirmed) return Future.value(false);
    final epoch = _epoch;
    final selectionVersion = ++_selectionVersion;
    return _command(() async {
      final selected = await repository!.circle(id);
      if (_current(epoch) && selectionVersion == _selectionVersion) {
        if (detail?.circle.id != id) createdInvite = null;
        detail = selected;
      }
    }, reload: false);
  }

  void dismissCircle() {
    _selectionVersion++;
    detail = null;
    createdInvite = null;
    _emit();
  }

  Future<bool> invite(String recipientId) async {
    if (!signedIn || busy || loading || contactsUnconfirmed) return false;
    if (detail == null || detail!.circle.ownerId != _identity) return false;
    final circleId = detail!.circle.id,
        recipient = recipientId.trim().toLowerCase();
    return _journaled(
      () => PendingWrite.invitation(circleId, recipient, _now()),
    );
  }

  Future<bool> accept(String id, String token) => contactsUnconfirmed
      ? Future.value(false)
      : _command(() => repository!.accept(id, token.trim()));
  Future<bool> revoke(String id) {
    final epoch = _epoch;
    return _command(() async {
      await repository!.revoke(id);
      if (_current(epoch) && createdInvite?.id == id) createdInvite = null;
    });
  }

  Future<bool> removeMember(String memberId) {
    final circleId = detail?.circle.id;
    if (circleId == null) return Future.value(false);
    return _command(() => repository!.removeMember(circleId, memberId));
  }

  Future<bool> closeCircle() {
    final id = detail?.circle.id;
    if (id == null) return Future.value(false);
    return _command(() => repository!.closeCircle(id));
  }

  Future<bool> loadBlocks({bool more = false}) {
    final epoch = _epoch, cursor = more ? blocksCursor : null;
    if (more && cursor == null) return Future.value(false);
    return _command(() async {
      final page = await repository!.blockedContacts(after: cursor);
      if (!_current(epoch)) return;
      final ids = <String>{};
      _blockedContacts = [
        if (more) ..._blockedContacts,
        ...page.items,
      ].where((entry) => ids.add(entry.userId)).toList();
      blocksCursor = page.nextCursor;
      blocksLoaded = true;
    }, reload: false);
  }

  Future<BlockReview?> reviewBlock(String target) async {
    if (target == userId || contactsUnconfirmed) return null;
    final epoch = _epoch, owner = _identity;
    BlockReview? review;
    await _command(() async {
      final state = await repository!.blockState(target);
      if (_current(epoch) && owner != null) {
        review = BlockReview._(state, owner, epoch);
      }
    }, reload: false);
    return review;
  }

  void _hideContacts() {
    _loadVersion++;
    _selectionVersion++;
    _circles = [];
    _invites = [];
    detail = null;
    createdInvite = null;
    // The list is reloaded explicitly; never leave a changed entry looking current.
    _blockedContacts = [];
    blocksCursor = null;
    blocksLoaded = false;
  }

  bool isBlockReviewCurrent(BlockReview review) =>
      _current(review._epoch) && review._owner == _identity;

  Future<bool> changeBlock(BlockReview review) async {
    if (!_current(review._epoch) ||
        review._owner != _identity ||
        busy ||
        loading ||
        (contactsUnconfirmed && !identical(_pendingBlock, review))) {
      return false;
    }
    final desired = !review.state.blocked;
    _pendingBlock = review;
    _hideContacts();
    final confirmed = await _command(() async {
      final receipt = await repository!.setBlock(
        review.state.userId,
        desired,
        review.state.version,
      );
      if (receipt.userId != review.state.userId ||
          receipt.blocked != desired ||
          receipt.version != review.state.version + 1) {
        throw const ApiFailure('invalid_response');
      }
      if (_current(review._epoch)) _pendingBlock = null;
    });
    if (!_current(review._epoch)) return false;
    if (!confirmed && contactsUnconfirmed) {
      // An ordinary rejection is definitive. Transport/parse/server failures may
      // follow a committed write, so keep those visibly unresolved until read.
      if ([
        'invalid_request',
        'not_found',
        'blocks_limit_reached',
        'block_version_exhausted',
        'profile_required',
      ].contains(error)) {
        _pendingBlock = null;
        _emit();
      } else {
        await checkBlockDecision();
      }
    }
    return confirmed;
  }

  Future<bool> retryBlockDecision() async {
    final pending = _pendingBlock;
    return pending != null && await changeBlock(pending);
  }

  Future<bool> checkBlockDecision() async {
    final pending = _pendingBlock;
    if (pending == null) return false;
    final epoch = _epoch;
    return _command(() async {
      final state = await repository!.blockState(pending.state.userId);
      if (!_current(epoch) || !identical(pending, _pendingBlock)) return;
      if (state.version > pending.state.version) {
        _pendingBlock = null;
        if (state.blocked != !pending.state.blocked) error = 'block_changed';
        await _load(epoch);
      }
      // An unchanged read cannot prove a timed-out request will never commit.
      // Only the same complete versioned intent may be retried explicitly.
    }, reload: false);
  }

  Future<bool> loadMoreReports() async {
    final cursor = nextCursor, epoch = _epoch;
    if (cursor == null) return false;
    return _command(() async {
      final page = await repository!.reports(cursor: cursor);
      if (_current(epoch)) {
        final ids = _reports.map((report) => report.id).toSet();
        _reports = [
          ..._reports,
          ...page.items.where((report) => ids.add(report.id)),
        ];
        nextCursor = page.nextCursor;
      }
    }, reload: false);
  }

  Future<bool> submitReport(
    ReportCategory category,
    String description,
    double latitude,
    double longitude,
  ) async {
    if (!signedIn || busy || loading) return false;
    if (!canReport) {
      error = 'verification_required';
      _emit();
      return false;
    }
    final text = description.trim();
    if (text.runes.length < 10 ||
        text.runes.length > 700 ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < 23.62 ||
        latitude > 24.02 ||
        longitude < 90.2 ||
        longitude > 90.58) {
      error = 'invalid_report';
      _emit();
      return false;
    }
    return _journaled(
      () => PendingWrite.report(category, text, latitude, longitude, _now()),
    );
  }

  void _requireCurrent(int epoch) {
    if (!_current(epoch)) throw const ApiFailure('session_changed');
  }

  Future<bool> _journaled(PendingWrite Function() create) => _command(() async {
    final epoch = _epoch, owner = _identity!;
    final write = await journal.prepare(owner, create());
    _requireCurrent(epoch);
    _pendingWrites = await journal.read(owner);
    _requireCurrent(epoch);
    _emit();
    await _sendWrite(write, owner, epoch);
  });

  Future<void> _sendWrite(PendingWrite write, String owner, int epoch) async {
    if (contactsUnconfirmed && write.kind != WriteKind.report) {
      throw const ApiFailure('block_changed');
    }
    final payload = write.payload;
    switch (write.kind) {
      case WriteKind.circle:
        await repository!.createCircle(write.id, payload['name']! as String);
      case WriteKind.invitation:
        final circleId = payload['circleId']! as String;
        final selectionVersion = _selectionVersion;
        if (detail?.circle.id != circleId) {
          final recovered = await repository!.circle(circleId);
          _requireCurrent(epoch);
          if (recovered.circle.ownerId != owner) {
            throw const ApiFailure('invalid_request');
          }
          if (selectionVersion == _selectionVersion) {
            detail = recovered;
            createdInvite = null;
          }
        }
        _requireCurrent(epoch);
        final created = await repository!.invite(
          write.id,
          circleId,
          payload['recipientId']! as String,
        );
        _requireCurrent(epoch);
        if (selectionVersion == _selectionVersion &&
            detail?.circle.id == circleId) {
          createdInvite = created;
        }
      case WriteKind.report:
        if (!canReport) throw const ApiFailure('verification_required');
        final status = await repository!.submitReport(
          write.id,
          ReportCategory.values.byName(payload['category']! as String),
          payload['description']! as String,
          payload['latitude']! as double,
          payload['longitude']! as double,
          DateTime.parse(payload['observedAt']! as String),
        );
        _requireCurrent(epoch);
        reportReceipt = status;
    }
    _requireCurrent(epoch);
    try {
      await journal.remove(owner, write.id);
      if (_current(epoch)) {
        _pendingWrites = _pendingWrites
            .where((item) => item.id != write.id)
            .toList();
      }
    } catch (_) {
      // The server acknowledged this write. Retain its ID for a safe replay;
      // a failed local cleanup must never create a replacement request.
      if (_current(epoch)) error = 'retry_cleanup_pending';
    }
  }

  Future<bool> retryWrite(String id) => _command(() async {
    final epoch = _epoch, owner = _identity!;
    final saved = await journal.read(owner);
    _requireCurrent(epoch);
    final matches = saved.where((write) => write.id == id);
    if (matches.isEmpty) throw const ApiFailure('not_found');
    _pendingWrites = saved;
    final write = matches.single;
    if (write.kind == WriteKind.report) {
      try {
        final status = await repository!.reportStatus(write.id);
        _requireCurrent(epoch);
        reportReceipt = status;
        await journal.remove(owner, write.id);
        if (_current(epoch)) {
          _pendingWrites = _pendingWrites
              .where((item) => item.id != id)
              .toList();
        }
        return;
      } on ApiFailure catch (failure) {
        if (failure.code != 'not_found') rethrow;
        if (_now().difference(write.createdAt) > const Duration(hours: 72)) {
          throw const ApiFailure('report_not_received');
        }
      }
    }
    await _sendWrite(matches.single, owner, epoch);
  });

  Future<bool> forgetWrite(String id) => _command(() async {
    final epoch = _epoch, owner = _identity!;
    if (!_pendingWrites.any((write) => write.id == id)) {
      throw const ApiFailure('not_found');
    }
    await journal.remove(owner, id);
    if (_current(epoch)) {
      _pendingWrites = _pendingWrites.where((write) => write.id != id).toList();
    }
  }, reload: false);

  Future<bool> withdrawReport(String id) =>
      _command(() => repository!.withdrawReport(id));
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    unawaited(_subscription?.cancel());
    _expiryTimer?.cancel();
    _resendTimer?.cancel();
    onClose?.call();
    super.dispose();
  }
}
