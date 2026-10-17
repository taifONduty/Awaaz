import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import 'private_values.dart';

abstract interface class DraftStore {
  Future<List<ReportDraft>> read();
  Future<void> write(List<ReportDraft> drafts);
}

// Anonymous preview drafts remain separate from account-bound live commands.
// Old prototype preferences are discarded; the user requested no mock migration.
class SecureDraftStore implements DraftStore {
  SecureDraftStore({
    this.values = const SecurePrivateValues(),
    this.key = 'awaaz.preview.drafts.encrypted.v1',
    this.clearLegacy = true,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final PrivateValues values;
  final String key;
  final bool clearLegacy;
  final DateTime Function() _now;
  static final _queue = PrivateStorageQueue();
  Future<T> _serialized<T>(Future<T> Function() action) => _queue.run(action);

  Future<void> _clearLegacy() async {
    if (!clearLegacy) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('awaaz.demo.drafts.v1') &&
        !await prefs.remove('awaaz.demo.drafts.v1')) {
      throw StateError('Draft cleanup failed');
    }
  }

  List<ReportDraft> _decode(String raw) {
    if (utf8.encode(raw).length > 64 * 1024) {
      throw const FormatException('Draft limit');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List<Object?> || decoded.length > 20) {
      throw const FormatException('Draft limit');
    }
    final items = decoded
        .map((item) => ReportDraft.fromJson(item! as Map<String, Object?>))
        .toList();
    for (final draft in items) {
      if (draft.id.isEmpty ||
          draft.id.length > 80 ||
          draft.place.trim().isEmpty ||
          draft.place.runes.length > 120 ||
          draft.description.trim().runes.length < 10 ||
          draft.description.runes.length > 700 ||
          draft.createdAt.isAfter(_now().add(const Duration(minutes: 5)))) {
        throw const FormatException('Invalid draft');
      }
    }
    if (items.map((item) => item.id).toSet().length != items.length) {
      throw const FormatException('Duplicate draft');
    }
    return items;
  }

  @override
  Future<List<ReportDraft>> read() => _serialized(() async {
    await _clearLegacy();
    final raw = await values.read(key);
    if (raw == null) return [];
    final items = _decode(raw);
    final active = items
        .where(
          (item) =>
              item.createdAt.isAfter(_now().subtract(const Duration(days: 30))),
        )
        .toList();
    if (active.length != items.length) await _write(active);
    return List.unmodifiable(active);
  });

  @override
  Future<void> write(List<ReportDraft> drafts) {
    final snapshot = List<ReportDraft>.of(drafts);
    return _serialized(() async {
      await _clearLegacy();
      await _write(snapshot);
    });
  }

  Future<void> _write(List<ReportDraft> drafts) async {
    if (drafts.isEmpty) {
      await values.delete(key);
      return;
    }
    final raw = jsonEncode(drafts.map((item) => item.toJson()).toList());
    _decode(raw);
    await values.write(key, raw);
  }
}

class MemoryDraftStore implements DraftStore {
  List<ReportDraft> _drafts = [];
  @override
  Future<List<ReportDraft>> read() async => List.of(_drafts);
  @override
  Future<void> write(List<ReportDraft> drafts) async {
    _drafts = List.of(drafts);
  }
}
