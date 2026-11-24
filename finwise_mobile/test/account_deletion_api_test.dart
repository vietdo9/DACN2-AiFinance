import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../lib/services/api_service.dart';

void main() {
  final api = ApiService();

  setUp(() {
    api.setToken('user-token');
  });

  tearDown(() async {
    await api.logout();
  });

  test(
    'requests an authenticated deletion intent and returns its server wait',
    () async {
      late http.Request request;
      final client = MockClient((incoming) async {
        request = incoming;
        return http.Response.bytes(
          utf8.encode(
            '{"success":true,"data":{"challenge":"abc123","wait_seconds":15}}',
          ),
          200,
        );
      });

      final result = await http.runWithClient(
        api.createAccountDeletionIntent,
        () => client,
      );

      expect(result.success, isTrue);
      expect(result.challenge, 'abc123');
      expect(result.waitSeconds, 15);
      expect(request.method, 'POST');
      expect(request.url.path, '/api/auth/me/delete-intent');
      expect(request.headers['authorization'], 'Bearer user-token');
    },
  );

  test('deletes only the current account with the issued challenge', () async {
    late http.Request request;
    final client = MockClient((incoming) async {
      request = incoming;
      return http.Response.bytes(utf8.encode('{"success":true}'), 200);
    });

    final result = await http.runWithClient(
      () => api.deleteMyAccount(challenge: 'abc123'),
      () => client,
    );

    expect(result.success, isTrue);
    expect(request.method, 'DELETE');
    expect(request.url.path, '/api/auth/me');
    expect(request.headers['authorization'], 'Bearer user-token');
    expect(jsonDecode(request.body), {'challenge': 'abc123'});
  });

  test('returns a structured UTF-8 server error without throwing', () async {
    final client = MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(
          '{"success":false,"error":"challenge_expired","message":"Mã xác nhận đã hết hạn"}',
        ),
        410,
      ),
    );

    final result = await http.runWithClient(
      () => api.deleteMyAccount(challenge: 'expired'),
      () => client,
    );

    expect(result.success, isFalse);
    expect(result.error, 'Mã xác nhận đã hết hạn');
  });
}
