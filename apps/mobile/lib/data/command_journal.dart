import 'dart:convert';

import '../domain/account_models.dart';
import '../domain/pending_write.dart';
import 'private_values.dart';

class CommandJournal {
  CommandJournal({required this.values, required this.namespace});
  final PrivateValues values;
  final String namespace;
  // Serialize whole read/modify/write transactions, including across adapters.
  // HTTP calls are never made under this lock.
  static final _queue = PrivateStorageQueue();
  Future<T> _transaction<T>(Future<T> Function() action) {
    return _queue.run(() async {
      try {
        return await action();
      } on ApiFailure catch (failure) {
        if (failure.code == 'retry_limit') rethrow;
        throw const ApiFailure('storage_unavailable');
      } catch (_) {
        throw const ApiFailure('storage_unavailable');
      }
    });
  }

  String _key(String owner) =>
      'awaaz.commands.v1.${base64Url.encode(utf8.encode(namespace))}.${PendingWrite.checkedId(owner)}';
  Future<List<PendingWrite>> _read(String owner) async {
    final raw = await values.read(_key(owner));
    if (raw == null) return [];
    if (utf8.encode(raw).length > 64 * 1024) {
      throw const FormatException('Oversized journal');
    }
    final decoded = jsonObject(jsonDecode(raw));
    if (decoded['version'] != 1 || decoded.length != 2) {
      throw const FormatException('Invalid journal');
    }
    final items = decoded['items'];
    if (items is! List<Object?> || items.length > 32) {
      throw const FormatException('Invalid journal');
    }
    final writes = items
        .map((item) => PendingWrite.fromJson(jsonObject(item)))
        .toList();
    if (writes.map((write) => write.id).toSet().length != writes.length) {
      throw const FormatException('Duplicate journal IDs');
    }
    return writes;
  }

  Future<void> _write(String owner, List<PendingWrite> writes) async {
    if (writes.isEmpty) {
      await values.delete(_key(owner));
      return;
    }
    final raw = jsonEncode({
      'version': 1,
      'items': writes.map((write) => write.toJson()).toList(),
    });
    if (utf8.encode(raw).length > 64 * 1024) {
      throw const ApiFailure('retry_limit');
    }
    await values.write(_key(owner), raw);
  }

  Future<List<PendingWrite>> read(String owner) =>
      _transaction(() async => List.unmodifiable(await _read(owner)));
  Future<PendingWrite> prepare(String owner, PendingWrite candidate) =>
      _transaction(() async {
        final writes = await _read(owner);
        for (final saved in writes) {
          if (saved.intent == candidate.intent) return saved;
        }
        if (writes.length >= 32) throw const ApiFailure('retry_limit');
        await _write(owner, [...writes, candidate]);
        return candidate;
      });
  // An acknowledgement or explicit user removal clears only that request.
  Future<void> remove(String owner, String id) => _transaction(() async {
    final writes = await _read(owner);
    await _write(owner, writes.where((write) => write.id != id).toList());
  });
}
