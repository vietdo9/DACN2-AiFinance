import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../lib/services/api_service.dart';

void main() {
  final api = ApiService();

  setUp(() {
    api.setToken('admin-token');
  });

  tearDown(() async {
    await api.logout();
  });

  test(
    'creates an admin user with the expected payload and auth header',
    () async {
      late http.Request request;
      final client = MockClient((incoming) async {
        request = incoming;
        return http.Response.bytes(utf8.encode('{"success":true}'), 201);
      });

      final result = await http.runWithClient(
        () => api.createAdminUser(
          fullName: '  Nguyễn An  ',
          email: '  AN@example.com ',
          password: 'secret-pass',
        ),
        () => client,
      );

      expect(result.success, isTrue);
      expect(result.error, isNull);
      expect(request.method, 'POST');
      expect(request.url.path, '/api/admin/users');
      expect(request.headers['authorization'], 'Bearer admin-token');
      expect(request.headers['content-type'], contains('application/json'));
      expect(jsonDecode(request.body), {
        'full_name': 'Nguyễn An',
        'email': 'an@example.com',
        'password': 'secret-pass',
      });
    },
  );

  test(
    'updates profile with a URI-encoded user ID and returns UTF-8 API errors',
    () async {
      late http.Request request;
      final client = MockClient((incoming) async {
        request = incoming;
        return http.Response.bytes(
          utf8.encode('{"message":"Email đã được dùng"}'),
          409,
        );
      });

      final result = await http.runWithClient(
        () => api.updateAdminUserProfile(
          'user/a b',
          fullName: '  Trần Bình ',
          email: ' Binh@Example.com ',
        ),
        () => client,
      );

      expect(result.success, isFalse);
      expect(result.error, 'Email đã được dùng');
      expect(request.method, 'PUT');
      expect(request.url.pathSegments, [
        'api',
        'admin',
        'users',
        'user/a b',
        'profile',
      ]);
      expect(request.headers['authorization'], 'Bearer admin-token');
      expect(jsonDecode(request.body), {
        'full_name': 'Trần Bình',
        'email': 'binh@example.com',
      });
    },
  );
}
