import 'dart:convert';

import 'package:finwise_mobile/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cachedAdmin = {
    'id': 'admin-1',
    'email': 'admin@example.test',
    'full_name': 'Quản trị viên',
    'role': 'admin',
    'status': 'active',
  };

  Future<void> seedSession() async {
    SharedPreferences.setMockInitialValues({
      'finwise_token': 'fixture-token',
      'finwise_user': jsonEncode(cachedAdmin),
    });
    await ApiService().checkSavedSession();
  }

  Future<void> withClient(
    Future<void> Function() run,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    await http.runWithClient(run, () => MockClient(handler));
  }

  test('validates same admin identity and preserves admin access', () async {
    await seedSession();
    await withClient(() async {
      expect(await ApiService().validateRestoredWebAdmin(), isTrue);
      expect(ApiService().currentUser?.isAdmin, isTrue);
      expect(ApiService().currentUser?.id, 'admin-1');
    }, (_) async => http.Response.bytes(
      utf8.encode(jsonEncode({'success': true, 'data': {'user': cachedAdmin}})),
      200,
    ));
    await ApiService().logout();
  });

  test('clears an expired cached admin session', () async {
    await seedSession();
    await withClient(() async {
      expect(await ApiService().validateRestoredWebAdmin(), isFalse);
      expect(ApiService().isLoggedIn, isFalse);
    }, (_) async => http.Response('{"success":false}', 401));
  });

  test('does not enter admin during a temporary validation outage', () async {
    await seedSession();
    await withClient(() async {
      expect(await ApiService().validateRestoredWebAdmin(), isTrue);
      expect(ApiService().currentUser?.isAdmin, isFalse);
      expect(ApiService().isLoggedIn, isTrue);
    }, (_) async => throw Exception('temporary network failure'));
    await ApiService().logout();
  });
}
