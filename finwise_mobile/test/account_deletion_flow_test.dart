import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/main.dart';
import '../lib/services/api_service.dart';

void main() {
  final api = ApiService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.logout();
    api.setToken('user-token');
  });

  tearDown(() async {
    await api.logout();
  });

  testWidgets(
    'cancel resets the wait, blocks submit at 14 seconds, submits once at 15',
    (tester) async {
      var intentCount = 0;
      var deleteCount = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/me/delete-intent') {
          intentCount++;
          return http.Response.bytes(
            utf8.encode(
              '{"success":true,"data":{"challenge":"challenge-$intentCount","wait_seconds":15}}',
            ),
            200,
          );
        }
        if (request.url.path == '/api/auth/me' && request.method == 'DELETE') {
          deleteCount++;
          return http.Response.bytes(utf8.encode('{"success":true}'), 200);
        }
        return http.Response.bytes(
          utf8.encode('{"success":true,"data":[]}'),
          200,
        );
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showAccountDeletionDialog(context),
                  child: const Text('Open deletion dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open deletion dialog'));
        await tester.pump();
        await tester.pump();
        expect(intentCount, 1);
        await tester.tap(find.text('Hủy'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open deletion dialog'));
        await tester.pump();
        await tester.pump();
        expect(intentCount, 2);

        final confirmButton = find.widgetWithText(
          FilledButton,
          'Xóa tài khoản',
        );
        await tester.pump(const Duration(seconds: 14));
        expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.widget<FilledButton>(confirmButton).onPressed, isNotNull);

        await tester.tap(confirmButton);
        await tester.pump();
        await tester.pump();
      await tester.pumpAndSettle();
        expect(deleteCount, 1);
        expect(find.text('Xóa tài khoản?'), findsNothing);
      }, () => client);
    },
  );
}
