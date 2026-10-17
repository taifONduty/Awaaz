import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:awaaz/data/account_api.dart';
import 'package:awaaz/data/backend_config.dart';
import 'package:awaaz/domain/account_models.dart';
import 'package:awaaz/domain/models.dart';

const alice = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const bob = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const circle = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const command = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

class TestSessions implements SessionRepository {
  TestSessions([this.id = alice]);
  String? id;
  final controller = StreamController<String?>.broadcast(sync: true);
  String? requestedPhone;
  String? verifiedCode;
  @override
  String? get userId => id;
  @override
  Stream<String?> get userChanges => controller.stream;
  void switchTo(String? value) {
    id = value;
    controller.add(value);
  }

  @override
  Future<String?> accessToken({bool forceRefresh = false}) async =>
      id == null ? null : 'token-for-$id';
  @override
  Future<void> requestCode(String phone) async {
    requestedPhone = phone;
  }

  @override
  Future<void> verifyCode(String phone, String code) async {
    verifiedCode = code;
    switchTo(alice);
  }

  @override
  Future<void> signOut() async {
    switchTo(null);
  }
}

Map<String, Object?> me(String id) => {
  'userId': id,
  'phoneVerified': true,
  'profile': {
    'id': id,
    'displayName': 'Demo user',
    'locale': 'en',
    'adultAttested': true,
  },
};

void main() {
  test(
    'status reconciliation uses authenticated GET and validates receipt states',
    () async {
      final sessions = TestSessions();
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('{"status":"withdrawn"}', 200);
      });
      final api = AccountApi(
        baseUrl: Uri.parse('https://api.example'),
        sessions: sessions,
        client: client,
      );
      expect(await api.reportStatus(command), 'withdrawn');
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/v1/report-requests/$command');
      expect(requests.single.body, isEmpty);
      expect(requests.single.headers['Authorization'], isNotNull);
      client.close();
      await sessions.controller.close();
    },
  );
  test('client config rejects partial, secret-key and remote plaintext configurations', () {
    expect(BackendConfig.parse(api: '', supabase: '', key: ''), isNull);
    for (final values in [
      ('https://api.example', '', 'sb_publishable_test'),
      (
        'https://api.example',
        'https://fresh.supabase.co',
        'sb_secret_do_not_expose',
      ),
      (
        'http://api.example',
        'https://fresh.supabase.co',
        'sb_publishable_test',
      ),
      (
        'https://user:password@api.example',
        'https://fresh.supabase.co',
        'sb_publishable_test',
      ),
      (
        'https://api.example?redirect=other',
        'https://fresh.supabase.co',
        'sb_publishable_test',
      ),
    ]) {
      expect(
        () => BackendConfig.parse(
          api: values.$1,
          supabase: values.$2,
          key: values.$3,
          release: false,
        ),
        throwsFormatException,
      );
    }
    expect(
      BackendConfig.parse(
        api: 'http://10.0.2.2:3030',
        supabase: 'https://fresh.supabase.co',
        key: 'sb_publishable_test',
        release: false,
      ),
      isNotNull,
    );
    expect(
      () => BackendConfig.parse(
        api: 'http://10.0.2.2:3030',
        supabase: 'https://fresh.supabase.co',
        key: 'sb_publishable_test',
      ),
      throwsFormatException,
    );
  });

  test('authenticated profile calls contain only session token and explicit adult consent', () async {
    final sessions = TestSessions();
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(request.method == 'PUT' ? me(alice)['profile'] : me(alice)),
        200,
      );
    });
    final api = AccountApi(
      baseUrl: Uri.parse('https://api.example'),
      sessions: sessions,
      client: client,
    );
    expect((await api.me()).userId, alice);
    await api.saveProfile(' Demo user ', 'bn');
    expect(requests.last.headers['Authorization'], 'Bearer token-for-$alice');
    expect(jsonDecode(requests.last.body), {
      'displayName': 'Demo user',
      'locale': 'bn',
      'adultAttested': true,
    });
    expect(requests.last.url.path, '/v1/me');
    expect(requests.last.followRedirects, isFalse);
    client.close();
    await sessions.controller.close();
  });

  test('unauthenticated, spoofed identity and late prior-account responses cannot enter client state', () async {
    final sessions = TestSessions(null);
    var calls = 0;
    final response = Completer<http.Response>();
    final client = MockClient((_) {
      calls++;
      return response.future;
    });
    final api = AccountApi(
      baseUrl: Uri.parse('https://api.example'),
      sessions: sessions,
      client: client,
    );
    await expectLater(
      api.me(),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.code,
          'code',
          'unauthenticated',
        ),
      ),
    );
    expect(calls, 0);
    sessions.switchTo(alice);
    final pending = api.me();
    await Future<void>.delayed(Duration.zero);
    sessions.switchTo(bob);
    response.complete(http.Response(jsonEncode(me(alice)), 200));
    await expectLater(
      pending,
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.code,
          'code',
          'session_changed',
        ),
      ),
    );
    final wrong = AccountApi(
      baseUrl: Uri.parse('https://api.example'),
      sessions: sessions,
      client: MockClient(
        (_) async => http.Response(jsonEncode(me(alice)), 200),
      ),
    );
    await expectLater(
      wrong.me(),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.code,
          'code',
          'invalid_response',
        ),
      ),
    );
    wrong.client.close();
    client.close();
    await sessions.controller.close();
  });

  test('writes preserve caller idempotency IDs and never send ownership or publication fields', () async {
    final sessions = TestSessions();
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(
          request.url.path == '/v1/circles'
              ? {
                  'circle': {'id': circle, 'name': 'Family', 'ownerId': alice},
                  'replayed': false,
                }
              : {'id': command, 'status': 'pending', 'replayed': false},
        ),
        201,
      );
    });
    final api = AccountApi(
      baseUrl: Uri.parse('https://api.example'),
      sessions: sessions,
      client: client,
    );
    await api.createCircle(command, 'Family');
    await api.submitReport(
      command,
      ReportCategory.lighting,
      'An observable lighting issue',
      23.76,
      90.38,
      DateTime.utc(2026, 10, 12),
    );
    for (final request in requests) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['clientRequestId'], command);
      expect(body.containsKey('ownerId'), isFalse);
      expect(body.containsKey('status'), isFalse);
    }
    await expectLater(api.circle('../v1/me'), throwsA(isA<ApiFailure>()));
    expect(requests.length, 2);
    client.close();
    await sessions.controller.close();
  });

  test('unknown server errors, invalid JSON and oversized responses are bounded and sanitized', () async {
    final sessions = TestSessions();
    for (final sample in [
      http.Response('{"code":"PRIVATE database password and stack"}', 503),
      http.Response('<html>PRIVATE upstream detail</html>', 200),
      http.Response('x' * (256 * 1024 + 1), 200),
    ]) {
      final client = MockClient((_) async => sample);
      final api = AccountApi(
        baseUrl: Uri.parse('https://api.example'),
        sessions: sessions,
        client: client,
      );
      try {
        await api.me();
        fail('must reject unsafe response');
      } on ApiFailure catch (error) {
        expect(error.toString().contains('PRIVATE'), isFalse);
      }
      client.close();
    }
    await sessions.controller.close();
  });

  test('network timeout aborts the request and reports an ambiguous retryable result', () async {
    final sessions = TestSessions();
    final client = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return http.Response(jsonEncode(me(alice)), 200);
    });
    final api = AccountApi(
      baseUrl: Uri.parse('https://api.example'),
      sessions: sessions,
      client: client,
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(
      api.me(),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.retryable,
          'retryable',
          true,
        ),
      ),
    );
    client.close();
    await sessions.controller.close();
  });

  test('report receipts reject unrecognized publication statuses', () async {
    final sessions = TestSessions();
    final client = MockClient(
      (_) async => http.Response('{"status":"published"}', 201),
    );
    final api = AccountApi(
      baseUrl: Uri.parse('https://api.example'),
      sessions: sessions,
      client: client,
    );
    await expectLater(
      api.submitReport(
        command,
        ReportCategory.lighting,
        'Observable lighting issue',
        23.76,
        90.38,
        DateTime.utc(2026, 10, 13),
      ),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.code,
          'code',
          'invalid_response',
        ),
      ),
    );
    client.close();
    await sessions.controller.close();
  });
  test(
    'a withdrawn replay receipt is accepted without restoring a report',
    () async {
      final sessions = TestSessions();
      final client = MockClient(
        (_) async =>
            http.Response('{"status":"withdrawn","replayed":true}', 200),
      );
      final api = AccountApi(
        baseUrl: Uri.parse('https://api.example'),
        sessions: sessions,
        client: client,
      );
      expect(
        await api.submitReport(
          command,
          ReportCategory.lighting,
          'Observable lighting issue',
          23.76,
          90.38,
          DateTime.utc(2026, 10, 13),
        ),
        'withdrawn',
      );
      client.close();
      await sessions.controller.close();
    },
  );
}
