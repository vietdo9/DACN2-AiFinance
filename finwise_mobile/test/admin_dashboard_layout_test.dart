import 'dart:convert';

import 'package:finwise_mobile/screens/admin_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  testWidgets(
    'desktop Admin filters, paging and explicit delete confirmation',
    (tester) async {
      await initializeDateFormatting('vi_VN');
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1366, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Uri? lastList;
      Uri? lastOverview;
      var createdUser = false;
      String dateKey(DateTime date) =>
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/overview')) {
          lastOverview = request.url;
          final periodType = request.url.queryParameters['period'] ?? 'all';
          final anchor = DateTime.parse(
            request.url.queryParameters['date'] ?? '2026-11-24',
          );
          final start = periodType == 'week'
              ? anchor.subtract(Duration(days: anchor.weekday - DateTime.monday))
              : DateTime(anchor.year, anchor.month);
          final end = periodType == 'week'
              ? start.add(const Duration(days: 6))
              : DateTime(anchor.year, anchor.month + 1, 0);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                if (periodType != 'all')
                  'period': {
                    'type': periodType,
                    'start_date': dateKey(start),
                    'end_date': dateKey(end),
                  },
                'metrics': {
                  'total_users': 3,
                  'active_users': 3,
                  'total_transactions': anchor.day,
                  'total_volume': anchor.day * 100.0,
                },
                'ai_service': {'status': 'offline', 'phobert_loaded': null},
                'category_distribution': [],
              },
            }),
            200,
          );
        }
        if (request.method == 'PUT' &&
            request.url.path.endsWith('/mock-user-id/profile')) {
          return http.Response(jsonEncode({'success': true}), 200);
        }
        if (request.method == 'POST' && request.url.path.endsWith('/users')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['full_name'], 'Created fixture');
          expect(body['email'], 'created@example.test');
          expect(body['password'], 'AdminPass2026');
          createdUser = true;
          return http.Response(jsonEncode({'success': true}), 201);
        }
        if (request.url.path.endsWith('/users')) {
          lastList = request.url;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'success': true,
                'total': 1,
                'page': 1,
                'per_page': 20,
                'data': [
                  {
                    'id': 'mock-user-id',
                    'email': 'fixture@example.test',
                    'full_name': 'Tài khoản mô phỏng',
                    'role': 'user',
                    'status': 'active',
                    'is_root_admin': false,
                    'can_suspend': true,
                    'can_change_role': true,
                    'can_edit': true,
                    'can_delete': true,
                  },
                ],
              }),
            ),
            200,
          );
        }
        fail('Unexpected network request for ${request.url}');
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(
          const MaterialApp(home: AdminDashboardScreen()),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(lastOverview?.queryParameters['period'], 'all');
        await tester.tap(find.text('Tháng'));
        await tester.pumpAndSettle();
        expect(lastOverview?.queryParameters['period'], 'month');
        final currentMonth = lastOverview?.queryParameters['date'];
        await tester.tap(find.byTooltip('Kỳ trước'));
        await tester.pumpAndSettle();
        expect(lastOverview?.queryParameters['date'], isNot(currentMonth));
        await tester.tap(find.byTooltip('Kỳ tiếp theo'));
        await tester.pumpAndSettle();
        expect(lastOverview?.queryParameters['date'], currentMonth);
        await tester.tap(find.text('Tuần'));
        await tester.pumpAndSettle();
        expect(lastOverview?.queryParameters['period'], 'week');
        expect(lastOverview?.queryParameters['date'], matches(r'^\d{4}-\d{2}-\d{2}$'));
        final currentWeek = lastOverview!.queryParameters['date'];
        await tester.tap(find.byTooltip('Kỳ trước'));
        await tester.pumpAndSettle();
        expect(lastOverview?.queryParameters['period'], 'week');
        expect(lastOverview?.queryParameters['date'], isNot(currentWeek));
        await tester.tap(find.byTooltip('Kỳ tiếp theo'));
        await tester.pumpAndSettle();
        expect(lastOverview?.queryParameters['date'], currentWeek);
        expect(find.text(DateTime.parse(currentWeek!).day.toString()), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton && widget.tooltip == 'Kỳ tiếp theo',
                ),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('Người Dùng'));
        await tester.pumpAndSettle();
        expect(find.byType(DataTable), findsOneWidget);
        expect(find.text('fixture@example.test'), findsOneWidget);
        expect(lastList?.queryParameters['page'], '1');
        await tester.tap(find.byTooltip('Xóa tài khoản'));
        await tester.pumpAndSettle();
        final confirm = find.widgetWithText(ElevatedButton, 'Xóa Vĩnh Viễn');
        expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);
        await tester.enterText(
          find.byType(EditableText).last,
          'fixture@example.test',
        );
        await tester.pumpAndSettle();
        expect(tester.widget<ElevatedButton>(confirm).onPressed, isNotNull);
        await tester.tap(find.text('Hủy'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Thao tác tài khoản'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sửa thông tin'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).first,
          'Updated fixture',
        );
        await tester.tap(find.text('Lưu thay đổi'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Tất cả trạng thái'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tạm khóa').last);
        await tester.pumpAndSettle();
        expect(lastList?.queryParameters['status'], 'suspended');
        await tester.tap(find.text('Thêm người dùng'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'Created fixture',
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'created@example.test',
        );
        await tester.enterText(
          find.byType(TextFormField).at(2),
          'AdminPass2026',
        );
        await tester.tap(find.text('Tạo tài khoản'));
        await tester.pumpAndSettle();
        expect(createdUser, isTrue);
        expect(tester.takeException(), isNull);
      }, () => client);
    },
  );
}
