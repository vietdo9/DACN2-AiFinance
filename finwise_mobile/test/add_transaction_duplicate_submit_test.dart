import 'dart:async';
import 'dart:convert';

import 'package:finwise_mobile/screens/add_transaction_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('rapid save callbacks create only one transaction', (tester) async {
    var createRequests = 0;
    final response = Completer<http.Response>();
    final observer = _PopObserver();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/transactions/categories')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {'code': 'AN_UONG', 'name': 'Food', 'type': 'expense'},
              {'code': 'THU_NHAP', 'name': 'Income', 'type': 'income'},
            ],
          }),
          200,
        );
      }
      if (request.method == 'POST' && request.url.path.endsWith('/api/transactions')) {
        createRequests++;
        return response.future;
      }
      return http.Response('{}', 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: Builder(builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
            ),
            child: const Text('Open entry'),
          )),
        ),
      ));
      await tester.tap(find.text('Open entry'));
      await tester.pumpAndSettle();
      final popsBeforeSave = observer.popCount;

      await tester.enterText(find.byType(TextField).first, '12500');
      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Lưu Giao Dịch'),
      );
      final staleCallback = saveButton.onPressed!;

      // Simulate two taps delivered before Flutter rebuilds the button.
      staleCallback();
      staleCallback();
      await tester.pump();
      expect(createRequests, 1);

      response.complete(http.Response('{"success":true}', 201));
      await tester.pumpAndSettle();
      expect(createRequests, 1);
      expect(observer.popCount, popsBeforeSave + 1);
    }, () => client);
  });

  testWidgets('income save unlocks after failure and can be retried', (tester) async {
    var createRequests = 0;
    Map<String, dynamic>? lastCreateBody;
    final observer = _PopObserver();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/transactions/categories')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {'code': 'AN_UONG', 'name': 'Food', 'type': 'expense'},
              {'code': 'THU_NHAP', 'name': 'Income', 'type': 'income'},
            ],
          }),
          200,
        );
      }
      if (request.method == 'POST' && request.url.path.endsWith('/api/transactions')) {
        createRequests++;
        lastCreateBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', createRequests == 1 ? 500 : 201);
      }
      return http.Response('{}', 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: Builder(builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
            ),
            child: const Text('Open entry'),
          )),
        ),
      ));
      await tester.tap(find.text('Open entry'));
      await tester.pumpAndSettle();
      final popsBeforeSave = observer.popCount;
      await tester.enterText(find.byType(TextField).first, '50000');
      await tester.tap(find.text('Thu Nhập'));
      await tester.pump();

      final saveFinder = find.widgetWithText(ElevatedButton, 'Lưu Giao Dịch');
      await tester.ensureVisible(saveFinder);
      await tester.tap(saveFinder);
      await tester.pumpAndSettle();
      expect(createRequests, 1);
      expect(lastCreateBody?['type'], 'income');
      expect(lastCreateBody?['category_code'], 'THU_NHAP');
      expect(observer.popCount, popsBeforeSave);

      final retryCallback = tester.widget<ElevatedButton>(saveFinder).onPressed;
      expect(retryCallback, isNotNull, reason: 'failed save must unlock the form');
      retryCallback!();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(createRequests, 2);
      expect(observer.popCount, popsBeforeSave + 1);
    }, () => client);
  });
}

class _PopObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}
