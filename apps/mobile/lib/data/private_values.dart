import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PrivateStorageQueue {
  Future<void>? _tail;
  Object? _last;
  Future<T> run<T>(Future<T> Function() action) {
    final marker = Object(), prior = _tail;
    _last = marker;
    final result = (prior ?? Future<void>.value()).then((_) async {
      try {
        return await action();
      } finally {
        // Reset inside the transaction, before returning to its caller. Keeping
        // an idle Future tail can strand work across widget-test async zones.
        if (identical(_last, marker)) {
          _tail = null;
          _last = null;
        }
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

abstract interface class PrivateValues {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecurePrivateValues implements PrivateValues {
  const SecurePrivateValues({this.storage = const FlutterSecureStorage()});
  final FlutterSecureStorage storage;
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

// Web previews and injected tests retain private data only in memory.
class MemoryPrivateValues implements PrivateValues {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
