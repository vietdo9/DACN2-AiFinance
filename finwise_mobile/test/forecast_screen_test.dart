import 'dart:convert';

import 'package:finwise_mobile/screens/ai_forecast_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('server error is distinct from insufficient history', (tester) async {
    var requests = 0;
    const message = 'Cần thêm lịch sử chi tiêu.';
    final client = MockClient((request) async {
      expect(request.url.path, '/api/ai/user-forecast');
      if (++requests == 1) return http.Response('{}', 500);
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'success': true,
          'has_enough_data': false,
          'message': message,
          'data': null,
        })),
        200,
      );
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: AiForecastScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Chưa tải được dự báo'), findsOneWidget);
      expect(find.text('Chưa đủ lịch sử chi tiêu'), findsNothing);

      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa đủ lịch sử chi tiêu'), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(requests, 2);
    }, () => client);
  });
}
