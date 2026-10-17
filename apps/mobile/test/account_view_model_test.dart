import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:awaaz/domain/account_models.dart';
import 'package:awaaz/domain/models.dart';
import 'package:awaaz/ui/account_view_model.dart';
import 'package:awaaz/data/command_journal.dart';
import 'package:awaaz/data/private_values.dart';

import 'account_api_test.dart' show TestSessions, alice, bob, circle;

const fixtureCircleId = circle;

class TestAccountRepository implements AccountRepository {
  TestAccountRepository(this.sessions);
  final TestSessions sessions;
  bool profileExists = true;
  bool failCircleOnce = false;
  bool failReportOnce = false;
  final circleIds = <String>[];
  final reportIds = <String>[];
  final reportTimes = <DateTime>[];
  final receivedStatuses = <String, String>{};
  bool failStatusLookup = false;
  Completer<CircleDetail>? heldDetail;
  Completer<OwnAccount>? heldMe;
  List<PublishedRoadEvent> published = [];
  List<CircleInvitation> pendingInvitations = [];
  List<TrustedCircle> storedCircles = [];
  @override
  Future<OwnAccount> me() async {
    final held = heldMe;
    if (held != null) {
      heldMe = null;
      return held.future;
    }
    return OwnAccount(
      userId: sessions.userId!,
      phoneVerified: true,
      profile: profileExists
          ? AccountProfile(
              id: sessions.userId!,
              displayName: 'Demo member',
              locale: 'en',
            )
          : null,
    );
  }

  @override
  Future<AccountProfile> saveProfile(String name, String locale) async {
    profileExists = true;
    return AccountProfile(
      id: sessions.userId!,
      displayName: name,
      locale: locale,
    );
  }

  @override
  Future<List<TrustedCircle>> circles() async =>
      storedCircles.where((item) => item.ownerId == sessions.userId).toList();
  @override
  Future<TrustedCircle> createCircle(String requestId, String name) async {
    circleIds.add(requestId);
    if (failCircleOnce) {
      failCircleOnce = false;
      throw const ApiFailure('network_unavailable', retryable: true);
    }
    final created = TrustedCircle(
      id: storedCircles.isEmpty ? fixtureCircleId : requestId,
      name: name,
      ownerId: sessions.userId!,
    );
    storedCircles = [...storedCircles, created];
    return created;
  }

  @override
  Future<CircleDetail> circle(String id) async {
    if (heldDetail != null) return heldDetail!.future;
    return CircleDetail(
      circle: storedCircles.firstWhere((item) => item.id == id),
      members: [],
    );
  }

  @override
  Future<CreatedInvitation> invite(
    String requestId,
    String circleId,
    String recipientId,
  ) async => CreatedInvitation(
    id: fixtureCircleId,
    token: 'a' * 43,
    expiresAt: DateTime.now().add(const Duration(days: 1)),
  );
  @override
  Future<List<CircleInvitation>> invitations() async =>
      List.of(pendingInvitations);
  @override
  Future<void> accept(String id, String token) async {}
  @override
  Future<void> revoke(String id) async {}
  @override
  Future<void> removeMember(String circleId, String memberId) async {}
  @override
  Future<void> closeCircle(String id) async {
    storedCircles = [];
  }

  ContactBlockState storedBlock = const ContactBlockState(
    userId: bob,
    blocked: false,
    version: 0,
  );
  Completer<ContactBlockState>? heldBlock;
  bool loseBlockAck = false;
  int blockWrites = 0;
  @override
  Future<BlockedContactsPage> blockedContacts({String? after}) async =>
      BlockedContactsPage(
        items: storedBlock.blocked
            ? [const BlockedContact(userId: bob, displayName: null)]
            : [],
        nextCursor: null,
      );
  @override
  Future<ContactBlockState> blockState(String userId) async => storedBlock;
  @override
  Future<ContactBlockState> setBlock(
    String userId,
    bool blocked,
    int expectedVersion,
  ) async {
    blockWrites++;
    if (heldBlock != null) return heldBlock!.future;
    if (storedBlock.version != expectedVersion) {
      throw const ApiFailure('block_changed');
    }
    storedBlock = ContactBlockState(
      userId: userId,
      blocked: blocked,
      version: expectedVersion + 1,
    );
    if (loseBlockAck) throw const ApiFailure('network_unavailable');
    return storedBlock;
  }

  @override
  Future<ReportPageResult> reports({String? cursor}) async =>
      ReportPageResult(items: [], nextCursor: null);
  @override
  Future<String> submitReport(
    String requestId,
    ReportCategory category,
    String description,
    double latitude,
    double longitude,
    DateTime observedAt,
  ) async {
    reportIds.add(requestId);
    reportTimes.add(observedAt);
    if (failReportOnce) {
      failReportOnce = false;
      throw const ApiFailure('network_unavailable', retryable: true);
    }
    return 'pending';
  }

  @override
  Future<void> withdrawReport(String id) async {}
  @override
  Future<String> reportStatus(String requestId) async {
    if (failStatusLookup) {
      throw const ApiFailure('network_unavailable', retryable: true);
    }
    return receivedStatuses[requestId] ?? (throw const ApiFailure('not_found'));
  }

  @override
  Future<List<PublishedRoadEvent>> events() async => List.of(published);
}

class FailingPrivateValues extends MemoryPrivateValues {
  bool failWrite = false, failDelete = false;
  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('PRIVATE storage error');
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw StateError('PRIVATE storage error');
    await super.delete(key);
  }
}

void main() {
  test('lost block acknowledgement reconciles without a second mutation and old approvals cannot cross login lifetimes', () async {
    final sessions = TestSessions();
    final repository = TestAccountRepository(sessions)..loseBlockAck = true;
    final vm = AccountViewModel(sessions: sessions, repository: repository);
    await vm.initialize();
    final review = (await vm.reviewBlock(bob))!;
    await vm.changeBlock(review);
    expect(repository.blockWrites, 1);
    expect(vm.contactsUnconfirmed, false);
    await vm.loadBlocks();
    expect(vm.blockedContacts.single.displayName, isNull);
    final oldApproval = (await vm.reviewBlock(bob))!;
    sessions.switchTo(null);
    sessions.switchTo(alice);
    await vm.refresh();
    expect(await vm.changeBlock(oldApproval), false);
    expect(repository.blockWrites, 1);
    vm.dispose();
    await sessions.controller.close();
  });

  test('an unchanged read after a transport failure keeps contacts hidden and never retries itself', () async {
    final sessions = TestSessions();
    final repository = TestAccountRepository(sessions);
    final vm = AccountViewModel(sessions: sessions, repository: repository);
    await vm.initialize();
    await vm.createCircle('Private circle');
    final review = (await vm.reviewBlock(bob))!;
    repository.heldBlock = Completer<ContactBlockState>();
    final changing = vm.changeBlock(review);
    expect(vm.circles, isEmpty);
    repository.heldBlock!.completeError(
      const ApiFailure('network_unavailable'),
    );
    await changing;
    expect(vm.contactsUnconfirmed, true);
    await vm.refresh();
    expect(vm.circles, isEmpty);
    expect(repository.blockWrites, 1);
    repository.heldBlock = null;
    expect(await vm.retryBlockDecision(), true);
    expect(repository.blockWrites, 2);
    expect(vm.contactsUnconfirmed, false);
    vm.dispose();
    await sessions.controller.close();
  });
  test('old and withdrawn requests reconcile without a new POST', () async {
    final sessions = TestSessions();
    final repository = TestAccountRepository(sessions)..failReportOnce = true;
    var now = DateTime.now().toUtc();
    final vm = AccountViewModel(
      sessions: sessions,
      repository: repository,
      now: () => now,
    );
    await vm.initialize();
    await vm.submitReport(
      ReportCategory.lighting,
      'Observable lighting issue',
      23.76,
      90.38,
    );
    final saved = vm.pendingWrites.single;
    now = now.add(const Duration(days: 4));
    expect(await vm.retryWrite(saved.id), isFalse);
    expect(vm.error, 'report_not_received');
    repository.failStatusLookup = true;
    expect(await vm.retryWrite(saved.id), isFalse);
    expect(vm.pendingWrites, hasLength(1));
    repository.failStatusLookup = false;
    repository.receivedStatuses[saved.id] = 'withdrawn';
    expect(await vm.retryWrite(saved.id), isTrue);
    expect(vm.reportReceipt, 'withdrawn');
    expect(vm.pendingWrites, isEmpty);
    expect(repository.reportIds, hasLength(1));
    vm.dispose();
    await sessions.controller.close();
  });
  test('a report retry survives restart without automatic sending and is hidden from another account', () async {
    final sessions = TestSessions();
    final repository = TestAccountRepository(sessions)..failReportOnce = true;
    final values = MemoryPrivateValues();
    CommandJournal journal() =>
        CommandJournal(values: values, namespace: 'backend');
    final original = AccountViewModel(
      sessions: sessions,
      repository: repository,
      journal: journal(),
    );
    await original.initialize();
    expect(
      await original.submitReport(
        ReportCategory.lighting,
        'Observable lighting issue',
        23.76,
        90.38,
      ),
      isFalse,
    );
    final saved = original.pendingWrites.single;
    original.dispose();
    final restored = AccountViewModel(
      sessions: sessions,
      repository: repository,
      journal: journal(),
    );
    await restored.initialize();
    expect(restored.pendingWrites.single.id, saved.id);
    expect(repository.reportIds, hasLength(1));
    sessions.switchTo(bob);
    expect(restored.pendingWrites, isEmpty);
    await restored.refresh();
    expect(await restored.retryWrite(saved.id), isFalse);
    expect(repository.reportIds, hasLength(1));
    sessions.switchTo(alice);
    await restored.refresh();
    expect(await restored.retryWrite(saved.id), isTrue);
    expect(repository.reportIds.toSet(), {saved.id});
    expect(repository.reportTimes.toSet(), {saved.createdAt});
    expect(restored.pendingWrites, isEmpty);
    restored.dispose();
    await sessions.controller.close();
  });

  test('storage failure prevents HTTP and failed acknowledgement cleanup retains the original ID', () async {
    final sessions = TestSessions();
    final repository = TestAccountRepository(sessions);
    final values = FailingPrivateValues()..failWrite = true;
    final vm = AccountViewModel(
      sessions: sessions,
      repository: repository,
      journal: CommandJournal(values: values, namespace: 'test'),
    );
    await vm.initialize();
    expect(
      await vm.submitReport(
        ReportCategory.lighting,
        'Observable lighting issue',
        23.76,
        90.38,
      ),
      isFalse,
    );
    expect(repository.reportIds, isEmpty);
    expect(vm.error, 'storage_unavailable');
    values.failWrite = false;
    values.failDelete = true;
    expect(
      await vm.submitReport(
        ReportCategory.lighting,
        'Observable lighting issue',
        23.76,
        90.38,
      ),
      isTrue,
    );
    final saved = vm.pendingWrites.single;
    expect(vm.error, 'retry_cleanup_pending');
    values.failDelete = false;
    expect(await vm.retryWrite(saved.id), isTrue);
    expect(repository.reportIds.toSet(), {saved.id});
    expect(vm.pendingWrites, isEmpty);
    vm.dispose();
    await sessions.controller.close();
  });
  test('leaving Circle detail ignores a late detail response', () async {
    final sessions = TestSessions();
    final repository = TestAccountRepository(sessions);
    final vm = AccountViewModel(sessions: sessions, repository: repository);
    await vm.initialize();
    await vm.createCircle('Family');
    final held = Completer<CircleDetail>();
    repository.heldDetail = held;
    final selection = vm.selectCircle(fixtureCircleId);
    vm.dismissCircle();
    held.complete(
      CircleDetail(circle: repository.storedCircles.single, members: []),
    );
    await selection;
    expect(vm.detail, isNull);
    expect(vm.createdInvite, isNull);
    vm.dispose();
    await sessions.controller.close();
  });
  test('an invitation secret is cleared when selecting another Circle or revoking it', () async {
    final sessions = TestSessions();
    final repository = TestAccountRepository(sessions);
    final vm = AccountViewModel(sessions: sessions, repository: repository);
    await vm.initialize();
    await vm.createCircle('First family');
    await vm.selectCircle(circle);
    await vm.invite(bob);
    expect(vm.createdInvite, isNotNull);
    await vm.createCircle('Second family');
    final secondId = vm.circles.last.id;
    await vm.selectCircle(secondId);
    expect(vm.createdInvite, isNull);
    await vm.invite(bob);
    final inviteId = vm.createdInvite!.id;
    await vm.revoke(inviteId);
    expect(vm.createdInvite, isNull);
    vm.dispose();
    await sessions.controller.close();
  });
  test('Bangladesh phone and code normalization supports Bengali digits without accepting arbitrary numbers', () {
    expect(bangladeshPhone('০১৭০০ ০০০০০০'), '+8801700000000');
    expect(bangladeshPhone('+880-1700-000000'), '+8801700000000');
    expect(bangladeshPhone('+1 1234567890'), isNull);
    expect(bangladeshPhone('01100000000'), isNull);
    expect(asciiDigits('১২৩৪৫৬'), '123456');
  });
  test('explicit adult attestation gates profile writes and profile absence avoids private API calls', () async {
    final sessions = TestSessions();
    final repository = TestAccountRepository(sessions);
    repository.profileExists = false;
    final vm = AccountViewModel(sessions: sessions, repository: repository);
    await vm.initialize();
    expect(vm.account!.profile, isNull);
    expect(await vm.saveProfile('Demo', 'en', false), isFalse);
    expect(repository.profileExists, isFalse);
    expect(await vm.saveProfile('Demo', 'bn', true), isTrue);
    expect(vm.account!.profile, isNotNull);
    vm.dispose();
    await sessions.controller.close();
  });
  test(
    'ambiguous circle and report retries retain IDs and observation time',
    () async {
      final sessions = TestSessions();
      final repository = TestAccountRepository(sessions);
      var now = DateTime.utc(2026, 10, 12, 12);
      repository.failCircleOnce = true;
      repository.failReportOnce = true;
      final vm = AccountViewModel(
        sessions: sessions,
        repository: repository,
        now: () => now,
      );
      await vm.initialize();
      expect(await vm.createCircle('Family'), isFalse);
      expect(await vm.createCircle('Family'), isTrue);
      expect(repository.circleIds.toSet().length, 1);
      expect(
        await vm.submitReport(
          ReportCategory.lighting,
          'Observable lighting issue',
          23.76,
          90.38,
        ),
        isFalse,
      );
      now = now.add(const Duration(minutes: 2));
      expect(
        await vm.submitReport(
          ReportCategory.lighting,
          'Observable lighting issue',
          23.76,
          90.38,
        ),
        isTrue,
      );
      expect(repository.reportIds.toSet().length, 1);
      expect(repository.reportTimes.toSet().length, 1);
      expect(vm.reportReceipt, 'pending');
      vm.dispose();
      await sessions.controller.close();
    },
  );
  test(
    'an earlier detail request cannot repopulate state after account switch',
    () async {
      final sessions = TestSessions();
      final repository = TestAccountRepository(sessions);
      final vm = AccountViewModel(sessions: sessions, repository: repository);
      await vm.initialize();
      await vm.createCircle('Private Alice family');
      repository.heldDetail = Completer<CircleDetail>();
      final selection = vm.selectCircle(circle);
      sessions.switchTo(bob);
      await Future<void>.delayed(Duration.zero);
      repository.heldDetail!.complete(
        CircleDetail(
          circle: const TrustedCircle(
            id: circle,
            name: 'PRIVATE Alice family',
            ownerId: alice,
          ),
          members: [],
        ),
      );
      await selection;
      expect(vm.detail, isNull);
      expect(vm.createdInvite, isNull);
      expect(vm.account?.userId, bob);
      vm.dispose();
      await sessions.controller.close();
    },
  );
  test('a late profile load cannot repopulate state or start private reads after account switch', () async {
    final sessions = TestSessions();
    final repository = TestAccountRepository(sessions);
    repository.heldMe = Completer<OwnAccount>();
    final held = repository.heldMe!;
    final vm = AccountViewModel(sessions: sessions, repository: repository);
    final initial = vm.initialize();
    sessions.switchTo(bob);
    await Future<void>.delayed(Duration.zero);
    held.complete(
      const OwnAccount(
        userId: alice,
        phoneVerified: true,
        profile: AccountProfile(
          id: alice,
          displayName: 'PRIVATE Alice',
          locale: 'en',
        ),
      ),
    );
    await initial;
    expect(vm.account?.userId, bob);
    expect(vm.circles, isEmpty);
    vm.dispose();
    await sessions.controller.close();
  });
  test('signout clears account, Circle detail and transient private fields immediately', () async {
    final sessions = TestSessions();
    final repository = TestAccountRepository(sessions);
    final vm = AccountViewModel(sessions: sessions, repository: repository);
    await vm.initialize();
    await vm.createCircle('Family');
    await vm.selectCircle(circle);
    expect(vm.detail, isNotNull);
    final signingOut = vm.signOut();
    expect(vm.account, isNull);
    expect(vm.detail, isNull);
    expect(vm.circles, isEmpty);
    await signingOut;
    expect(vm.signedIn, isFalse);
    expect(vm.busy, isFalse);
    vm.dispose();
    await sessions.controller.close();
  });
  test(
    'expired road evidence and invitations disappear from current actions',
    () async {
      final sessions = TestSessions();
      final repository = TestAccountRepository(sessions);
      var now = DateTime.utc(2026, 10, 12, 12);
      repository.published = [
        PublishedRoadEvent(
          id: circle,
          category: ReportCategory.lighting,
          summary: 'Demo condition',
          observedAt: now,
          expiresAt: now.add(const Duration(seconds: 10)),
        ),
      ];
      repository.pendingInvitations = [
        CircleInvitation(
          id: circle,
          circleName: 'Expiring Circle',
          inviterName: 'Fixture member',
          inviterId: bob,
          expiresAt: now.add(const Duration(seconds: 5)),
        ),
      ];
      final vm = AccountViewModel(
        sessions: sessions,
        repository: repository,
        now: () => now,
      );
      await vm.initialize();
      expect(vm.events.length, 1);
      expect(vm.invitations.length, 1);
      vm.createdInvite = CreatedInvitation(
        id: circle,
        token: 'SYNTHETIC expiring code',
        expiresAt: now.add(const Duration(seconds: 7)),
      );
      expect(vm.createdInvite, isNotNull);
      now = now.add(const Duration(seconds: 11));
      expect(vm.events, isEmpty);
      expect(vm.invitations, isEmpty);
      expect(vm.createdInvite, isNull);
      vm.dispose();
      await sessions.controller.close();
    },
  );
}
