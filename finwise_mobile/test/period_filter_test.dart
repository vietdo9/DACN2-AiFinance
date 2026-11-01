import 'package:flutter_test/flutter_test.dart';
import 'package:finwise_mobile/models/transaction_model.dart';

void main() {
  group('Transaction Period Filter Logic Tests', () {
    final t1 = TransactionModel(
      id: 'tx1',
      categoryCode: 'AN_UONG',
      categoryName: 'Ăn uống',
      amount: 50000,
      type: 'expense',
      transactionDate: DateTime(2026, 10, 26, 8, 30), // Thứ hai trong tuần 26/10 - 01/11/2026
      note: 'Phở bò',
      aiPredicted: false,
    );

    final t2 = TransactionModel(
      id: 'tx2',
      categoryCode: 'THU_NHAP',
      categoryName: 'Lương',
      amount: 15000000,
      type: 'income',
      transactionDate: DateTime(2026, 10, 31, 19, 0), // Thứ bảy trong tuần 26/10 - 01/11/2026 (Tháng 10)
      note: 'Nhận lương tháng',
      aiPredicted: false,
    );

    final t3 = TransactionModel(
      id: 'tx3',
      categoryCode: 'AN_UONG',
      categoryName: 'Ăn uống',
      amount: 120000,
      type: 'expense',
      transactionDate: DateTime(2026, 11, 1, 12, 0), // Chủ nhật trong tuần 26/10 - 01/11/2026 (Tháng 11)
      note: 'Pizza Chủ Nhật',
      aiPredicted: false,
    );

    final t4 = TransactionModel(
      id: 'tx4',
      categoryCode: 'MUA_SAM',
      categoryName: 'Mua sắm',
      amount: 350000,
      type: 'expense',
      transactionDate: DateTime(2026, 11, 2, 10, 0), // Thứ hai tuần kế tiếp (02/11/2026)
      note: 'Mua sắm đầu tuần mới',
      aiPredicted: false,
    );

    final allTxs = [t1, t2, t3, t4];

    test('Weekly filter includes Monday through Sunday of selected date', () {
      final selectedWeekDate = DateTime(2026, 10, 28); // Thứ tư
      final startOfWeek = DateTime(selectedWeekDate.year, selectedWeekDate.month, selectedWeekDate.day)
          .subtract(Duration(days: selectedWeekDate.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

      final weekFiltered = allTxs.where((tx) {
        final d = tx.transactionDate;
        return !d.isBefore(startOfWeek) && !d.isAfter(endOfWeek);
      }).toList();

      expect(weekFiltered.length, 3);
      expect(weekFiltered.map((t) => t.id), containsAll(['tx1', 'tx2', 'tx3']));
      expect(weekFiltered.map((t) => t.id), isNot(contains('tx4')));
    });

    test('Monthly filter correctly isolates month 10 vs month 11', () {
      final octMonth = DateTime(2026, 10, 1);
      final octFiltered = allTxs.where((tx) {
        return tx.transactionDate.year == octMonth.year && tx.transactionDate.month == octMonth.month;
      }).toList();

      expect(octFiltered.length, 2);
      expect(octFiltered.map((t) => t.id), containsAll(['tx1', 'tx2']));

      final novMonth = DateTime(2026, 11, 1);
      final novFiltered = allTxs.where((tx) {
        return tx.transactionDate.year == novMonth.year && tx.transactionDate.month == novMonth.month;
      }).toList();

      expect(novFiltered.length, 2);
      expect(novFiltered.map((t) => t.id), containsAll(['tx3', 'tx4']));
    });

    test('Summary calculations for period', () {
      final selectedWeekDate = DateTime(2026, 10, 28);
      final startOfWeek = DateTime(selectedWeekDate.year, selectedWeekDate.month, selectedWeekDate.day)
          .subtract(Duration(days: selectedWeekDate.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

      final weekFiltered = allTxs.where((tx) {
        final d = tx.transactionDate;
        return !d.isBefore(startOfWeek) && !d.isAfter(endOfWeek);
      }).toList();

      double totalIncome = 0;
      double totalExpense = 0;
      for (final tx in weekFiltered) {
        if (tx.type == 'income') {
          totalIncome += tx.amount;
        } else {
          totalExpense += tx.amount;
        }
      }
      final net = totalIncome - totalExpense;

      expect(totalIncome, 15000000);
      expect(totalExpense, 170000); // 50,000 + 120,000
      expect(net, 14830000);
    });
  });
}
