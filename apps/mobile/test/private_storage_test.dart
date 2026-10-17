import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:awaaz/data/command_journal.dart';
import 'package:awaaz/data/draft_store.dart';
import 'package:awaaz/data/private_values.dart';
import 'package:awaaz/domain/account_models.dart';
import 'package:awaaz/domain/models.dart';
import 'package:awaaz/domain/pending_write.dart';

import 'account_api_test.dart' show alice, bob;

void main() {
  test('journal transactions survive recreation, serialize concurrent preparation and isolate owners/backends', () async {
    final values = MemoryPrivateValues();
    final first = CommandJournal(values: values, namespace: 'backend-a');
    final second = CommandJournal(values: values, namespace: 'backend-a');
    final now = DateTime.utc(2026, 10, 13);
    final writes = await Future.wait([
      first.prepare(alice, PendingWrite.circle('Family', now)),
      second.prepare(
        alice,
        PendingWrite.circle('Family', now.add(const Duration(minutes: 1))),
      ),
    ]);
    expect(writes[0].id, writes[1].id);
    expect(await second.read(alice), hasLength(1));
    expect(await second.read(bob), isEmpty);
    expect(
      await CommandJournal(values: values, namespace: 'backend-b').read(alice),
      isEmpty,
    );
    final another = await first.prepare(
      alice,
      PendingWrite.circle('Friends', now),
    );
    await second.remove(alice, writes.first.id);
    expect((await first.read(alice)).single.id, another.id);
  });

  test(
    'journal rejects corrupt or oversized storage without overwriting it',
    () async {
      final values = MemoryPrivateValues();
      final journal = CommandJournal(values: values, namespace: 'test');
      final write = PendingWrite.circle('Family', DateTime.utc(2026, 10, 13));
      await journal.prepare(alice, write);
      final key = values.values.keys.single;
      for (final invalid in [
        'PRIVATE corrupt data',
        'x' * (64 * 1024 + 1),
        '{"version":9,"items":[]}',
      ]) {
        values.values[key] = invalid;
        await expectLater(
          journal.prepare(alice, write),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.code,
              'code',
              'storage_unavailable',
            ),
          ),
        );
        expect(values.values[key], invalid);
      }
    },
  );

  test('journal refuses arbitrary payload fields, secrets and malformed coordinates', () {
    final write = PendingWrite.circle('Family', DateTime.utc(2026, 10, 13));
    expect(
      () => PendingWrite.fromJson({
        ...write.toJson(),
        'payload': {'name': 'Family', 'token': 'PRIVATE'},
      }),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => PendingWrite.report(
        ReportCategory.other,
        'Observable test issue',
        double.nan,
        90.38,
        DateTime.utc(2026, 10, 13),
      ),
      throwsA(isA<ApiFailure>()),
    );
  });

  test('draft storage snapshots writes, removes expired data and deletes the encrypted value', () async {
    final values = MemoryPrivateValues();
    final now = DateTime.utc(2026, 10, 13);
    final store = SecureDraftStore(
      values: values,
      clearLegacy: false,
      now: () => now,
    );
    ReportDraft draft(String id, DateTime at) => ReportDraft(
      id: id,
      category: ReportCategory.lighting,
      place: 'Synthetic road',
      description: 'SYNTHETIC lighting issue',
      createdAt: at,
    );
    final drafts = [
      draft('expired', now.subtract(const Duration(days: 31))),
      draft('current', now),
    ];
    final saving = store.write(drafts);
    drafts.clear();
    await saving;
    final reopened = SecureDraftStore(
      values: values,
      clearLegacy: false,
      now: () => now,
    );
    expect((await reopened.read()).single.id, 'current');
    expect(jsonDecode(values.values[store.key]!) as List, hasLength(1));
    final writing = store.write([draft('next', now)]),
        deleting = reopened.write([]);
    await Future.wait([writing, deleting]);
    expect(await store.read(), isEmpty);
    expect(values.values.containsKey(store.key), isFalse);
  });

  test('obsolete mock preferences are discarded without copying plaintext into the new store', () async {
    SharedPreferences.setMockInitialValues({
      'awaaz.demo.drafts.v1': 'PRIVATE legacy fixture',
    });
    final values = MemoryPrivateValues();
    final store = SecureDraftStore(values: values);
    expect(await store.read(), isEmpty);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'awaaz.demo.drafts.v1',
      ),
      isFalse,
    );
    expect(values.values, isEmpty);
  });
}
