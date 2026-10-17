import 'dart:convert';

import '../domain/account_models.dart';
import '../domain/pending_write.dart';
import '../domain/sos.dart';
import 'private_values.dart';

class SosJournal {
  SosJournal({required this.values, required this.namespace});
  final PrivateValues values;
  final String namespace;
  static final _queue = PrivateStorageQueue();
  String _key(String owner) =>
      'awaaz.sos.v1.${base64Url.encode(utf8.encode(namespace))}.${PendingWrite.checkedId(owner)}';
  Future<T> _run<T>(Future<T> Function() action) => _queue.run(() async {
    try {
      return await action();
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure('storage_unavailable');
    }
  });
  Future<SosIntent?> _read(String owner) async {
    final raw = await values.read(_key(owner));
    if (raw == null) return null;
    if (utf8.encode(raw).length > 12 * 1024) {
      throw const ApiFailure('storage_unavailable');
    }
    return SosIntent.fromJson(jsonObject(jsonDecode(raw)));
  }

  Future<SosIntent?> read(String owner) => _run(() => _read(owner));
  Future<void> prepare(String owner, SosIntent candidate) => _run(() async {
    final saved = await _read(owner);
    if (saved != null) throw const ApiFailure('sos_pending_intent');
    await values.write(_key(owner), jsonEncode(candidate.toJson()));
  });
  Future<SosIntent> withdraw(String owner, SosIntent approved) =>
      _run(() async {
        final saved = await _read(owner);
        if (saved != null && saved.id != approved.id) {
          throw const ApiFailure('sos_pending_intent');
        }
        final next = (saved ?? approved).withdrawing();
        await values.write(_key(owner), jsonEncode(next.toJson()));
        return next;
      });
  Future<bool> acknowledge(String owner, String id, String phase) =>
      _run(() async {
        final saved = await _read(owner);
        if (saved == null) return true;
        // An old activation acknowledgement cannot erase a newer withdrawal.
        if (saved.id != id || saved.phase != phase) return false;
        await values.delete(_key(owner));
        return true;
      });
}
