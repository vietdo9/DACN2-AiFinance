import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart';

class ExportOptions {
  final DateTime? startDate;
  final DateTime? endDate;
  final String dateFilterType; // 'all', 'this_month', 'last_month', 'this_week', 'custom'
  final String typeFilter; // 'all', 'expense', 'income'
  final Set<String> selectedCategoryCodes; // empty = all
  final Set<String> selectedColumns;

  ExportOptions({
    this.startDate,
    this.endDate,
    this.dateFilterType = 'all',
    this.typeFilter = 'all',
    this.selectedCategoryCodes = const {},
    this.selectedColumns = const {'stt', 'date', 'type', 'category', 'amount', 'note'},
  });
}

class ExcelExportService {
  static final ExcelExportService _instance = ExcelExportService._internal();
  factory ExcelExportService() => _instance;
  ExcelExportService._internal();

  final currencyFormat = NumberFormat('#,###', 'vi_VN');
  final dateFormat = DateFormat('dd/MM/yyyy');
  final timeFormat = DateFormat('dd/MM/yyyy HH:mm');

  /// Tạo và lưu file Excel chuyên nghiệp theo tùy chọn
  Future<String?> exportTransactions({
    required List<TransactionModel> allTransactions,
    required UserModel? user,
    required double currentBalance,
    required ExportOptions options,
  }) async {
    try {
      // 1. Lọc danh sách giao dịch theo tùy chọn
      final filteredList = filterTransactions(allTransactions, options);

      // 2. Tạo Workbook
      final excel = Excel.createExcel();
      final sheetName = 'Bao_Cao_Giao_Dich';
      final sheet = excel[sheetName];
      excel.delete('Sheet1');

      // Styles
      final titleStyle = CellStyle(
        bold: true,
        fontSize: 16,
        fontColorHex: ExcelColor.fromHexString('#1E1B4B'),
        horizontalAlign: HorizontalAlign.Left,
      );

      final subtitleStyle = CellStyle(
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('#64748B'),
      );

      final boldMetaStyle = CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('#1E293B'),
      );

      final headerStyle = CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('#4F46E5'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      final rowStyle = CellStyle(
        fontSize: 10,
        horizontalAlign: HorizontalAlign.Left,
        verticalAlign: VerticalAlign.Center,
      );

      final rowCenterStyle = CellStyle(
        fontSize: 10,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      final expenseStyle = CellStyle(
        fontSize: 10,
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#EF4444'),
        horizontalAlign: HorizontalAlign.Right,
        verticalAlign: VerticalAlign.Center,
      );

      final incomeStyle = CellStyle(
        fontSize: 10,
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#10B981'),
        horizontalAlign: HorizontalAlign.Right,
        verticalAlign: VerticalAlign.Center,
      );

      final summaryHeaderStyle = CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('#1E293B'),
        backgroundColorHex: ExcelColor.fromHexString('#E2E8F0'),
        horizontalAlign: HorizontalAlign.Left,
        verticalAlign: VerticalAlign.Center,
      );

      final totalRowStyle = CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('#1E1B4B'),
        backgroundColorHex: ExcelColor.fromHexString('#EEF2FF'),
        horizontalAlign: HorizontalAlign.Right,
        verticalAlign: VerticalAlign.Center,
      );

      // --- DÒNG TIÊU ĐỀ BÁO CÁO ---
      int curRow = 0;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow))
        ..value = TextCellValue('FINWISE - BÁO CÁO LỊCH SỬ GIAO DỊCH TÀI CHÍNH')
        ..cellStyle = titleStyle;
      curRow++;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow))
        ..value = TextCellValue('Thời gian xuất báo cáo: ${timeFormat.format(DateTime.now())}')
        ..cellStyle = subtitleStyle;
      curRow += 2;

      // --- THÔNG TIN TÀI KHOẢN & TÓM TẮT ---
      final ownerName = user?.fullName.isNotEmpty == true ? user!.fullName : 'Chủ tài khoản FinWise';
      final ownerEmail = user?.email.isNotEmpty == true ? user!.email : '';

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow))
        ..value = TextCellValue('Chủ tài khoản:')
        ..cellStyle = subtitleStyle;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: curRow))
        ..value = TextCellValue(ownerName)
        ..cellStyle = boldMetaStyle;
      curRow++;

      if (ownerEmail.isNotEmpty) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow))
          ..value = TextCellValue('Email tài khoản:')
          ..cellStyle = subtitleStyle;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: curRow))
          ..value = TextCellValue(ownerEmail)
          ..cellStyle = boldMetaStyle;
        curRow++;
      }

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow))
        ..value = TextCellValue('Kỳ báo cáo:')
        ..cellStyle = subtitleStyle;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: curRow))
        ..value = TextCellValue(_getFilterPeriodLabel(options))
        ..cellStyle = boldMetaStyle;
      curRow++;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow))
        ..value = TextCellValue('Số dư ví hiện tại:')
        ..cellStyle = subtitleStyle;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: curRow))
        ..value = TextCellValue('${currencyFormat.format(currentBalance)} VND')
        ..cellStyle = boldMetaStyle;
      curRow += 2;

      // --- THỐNG KÊ NHANH THU - CHI TRONG KỲ ---
      double totalExpense = 0;
      double totalIncome = 0;
      for (final t in filteredList) {
        if (t.type == 'income') {
          totalIncome += t.amount;
        } else {
          totalExpense += t.amount;
        }
      }
      final netBalance = totalIncome - totalExpense;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow))
        ..value = TextCellValue('Tổng Thu Nhập (+):')
        ..cellStyle = summaryHeaderStyle;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: curRow))
        ..value = TextCellValue('${currencyFormat.format(totalIncome)} VND')
        ..cellStyle = summaryHeaderStyle;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: curRow))
        ..value = TextCellValue('Tổng Chi Tiêu (-):')
        ..cellStyle = summaryHeaderStyle;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: curRow))
        ..value = TextCellValue('${currencyFormat.format(totalExpense)} VND')
        ..cellStyle = summaryHeaderStyle;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: curRow))
        ..value = TextCellValue('Chênh lệch (Net):')
        ..cellStyle = summaryHeaderStyle;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: curRow))
        ..value = TextCellValue('${currencyFormat.format(netBalance)} VND')
        ..cellStyle = summaryHeaderStyle;
      curRow += 2;

      // --- CỘT DỮ LIỆU ĐƯỢC CHỌN ---
      final cols = <String>[];
      final colTitles = <String>[];

      if (options.selectedColumns.contains('stt')) {
        cols.add('stt');
        colTitles.add('STT');
      }
      if (options.selectedColumns.contains('date')) {
        cols.add('date');
        colTitles.add('Ngày Giao Dịch');
      }
      if (options.selectedColumns.contains('type')) {
        cols.add('type');
        colTitles.add('Phân Loại');
      }
      if (options.selectedColumns.contains('category')) {
        cols.add('category');
        colTitles.add('Danh Mục');
      }
      if (options.selectedColumns.contains('amount')) {
        cols.add('amount');
        colTitles.add('Số Tiền (VND)');
      }
      if (options.selectedColumns.contains('note')) {
        cols.add('note');
        colTitles.add('Nội Dung / Ghi Chú');
      }

      // Ghi Header Table
      for (int c = 0; c < colTitles.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: curRow))
          ..value = TextCellValue(colTitles[c])
          ..cellStyle = headerStyle;
      }
      curRow++;

      // Ghi từng dòng dữ liệu
      for (int i = 0; i < filteredList.length; i++) {
        final t = filteredList[i];
        final isIncome = t.type == 'income';

        for (int c = 0; c < cols.length; c++) {
          final colType = cols[c];
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: curRow));

          switch (colType) {
            case 'stt':
              cell.value = IntCellValue(i + 1);
              cell.cellStyle = rowCenterStyle;
              break;
            case 'date':
              cell.value = TextCellValue(dateFormat.format(t.transactionDate));
              cell.cellStyle = rowCenterStyle;
              break;
            case 'type':
              cell.value = TextCellValue(isIncome ? 'Thu nhập' : 'Chi tiêu');
              cell.cellStyle = isIncome ? incomeStyle : expenseStyle;
              break;
            case 'category':
              cell.value = TextCellValue(t.categoryName ?? t.categoryCode);
              cell.cellStyle = rowStyle;
              break;
            case 'amount':
              final prefix = isIncome ? '+' : '-';
              cell.value = TextCellValue('$prefix${currencyFormat.format(t.amount)}');
              cell.cellStyle = isIncome ? incomeStyle : expenseStyle;
              break;
            case 'note':
              cell.value = TextCellValue(t.note);
              cell.cellStyle = rowStyle;
              break;
          }
        }
        curRow++;
      }

      // Dòng Tổng Cộng cuối bảng
      final totalLabelCol = cols.contains('category') ? cols.indexOf('category') : 0;
      final amountCol = cols.indexOf('amount');

      if (amountCol != -1) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: totalLabelCol, rowIndex: curRow))
          ..value = TextCellValue('TỔNG CỘNG:')
          ..cellStyle = totalRowStyle;

        sheet.cell(CellIndex.indexByColumnRow(columnIndex: amountCol, rowIndex: curRow))
          ..value = TextCellValue('${currencyFormat.format(netBalance)} VND')
          ..cellStyle = totalRowStyle;
      }

      // Đặt độ rộng cột tương đối
      for (int c = 0; c < cols.length; c++) {
        final col = cols[c];
        if (col == 'stt') sheet.setColumnWidth(c, 8);
        if (col == 'date') sheet.setColumnWidth(c, 16);
        if (col == 'type') sheet.setColumnWidth(c, 14);
        if (col == 'category') sheet.setColumnWidth(c, 24);
        if (col == 'amount') sheet.setColumnWidth(c, 20);
        if (col == 'note') sheet.setColumnWidth(c, 45);
      }

      // 3. Xuất file binary
      final bytes = excel.save();
      if (bytes == null) {
        throw Exception('Không thể mã hóa file Excel');
      }

      // 4. Lưu ra thư mục lưu trữ
      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
      }
      dir ??= await getApplicationDocumentsDirectory();

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '${dir.path}/FinWise_Bao_Cao_$timestamp.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      debugPrint('[ExcelExportService] ✅ Đã lưu file Excel: $filePath (${bytes.length} bytes)');
      return filePath;
    } catch (e, stack) {
      debugPrint('[ExcelExportService] ❌ Lỗi xuất Excel: $e\n$stack');
      return null;
    }
  }

  /// Bộ lọc giao dịch theo tùy chọn người dùng
  List<TransactionModel> filterTransactions(List<TransactionModel> list, ExportOptions options) {
    return list.where((t) {
      // 1. Lọc theo Loại Thu / Chi
      if (options.typeFilter == 'expense' && t.type != 'expense') return false;
      if (options.typeFilter == 'income' && t.type != 'income') return false;

      // 2. Lọc theo Danh mục
      if (options.selectedCategoryCodes.isNotEmpty &&
          !options.selectedCategoryCodes.contains(t.categoryCode)) {
        return false;
      }

      // 3. Lọc theo Thời gian
      final date = t.transactionDate;
      final now = DateTime.now();

      switch (options.dateFilterType) {
        case 'this_month':
          if (date.year != now.year || date.month != now.month) return false;
          break;
        case 'last_month':
          final lastMonth = DateTime(now.year, now.month - 1, 1);
          if (date.year != lastMonth.year || date.month != lastMonth.month) return false;
          break;
        case 'this_week':
          final dayOfWeek = now.weekday; // 1 = Thứ 2, 7 = CN
          final startOfWeek = DateTime(now.year, now.month, now.day - (dayOfWeek - 1));
          final endOfWeek = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day + 6, 23, 59, 59);
          if (date.isBefore(startOfWeek) || date.isAfter(endOfWeek)) return false;
          break;
        case 'custom':
          if (options.startDate != null) {
            final start = DateTime(options.startDate!.year, options.startDate!.month, options.startDate!.day);
            if (date.isBefore(start)) return false;
          }
          if (options.endDate != null) {
            final end = DateTime(options.endDate!.year, options.endDate!.month, options.endDate!.day, 23, 59, 59);
            if (date.isAfter(end)) return false;
          }
          break;
        case 'all':
        default:
          break;
      }

      return true;
    }).toList();
  }

  String _getFilterPeriodLabel(ExportOptions options) {
    switch (options.dateFilterType) {
      case 'this_month':
        return 'Tháng này (${DateFormat('MM/yyyy').format(DateTime.now())})';
      case 'last_month':
        final lastMonth = DateTime(DateTime.now().year, DateTime.now().month - 1, 1);
        return 'Tháng trước (${DateFormat('MM/yyyy').format(lastMonth)})';
      case 'this_week':
        return 'Tuần này';
      case 'custom':
        final s = options.startDate != null ? dateFormat.format(options.startDate!) : '...';
        final e = options.endDate != null ? dateFormat.format(options.endDate!) : '...';
        return 'Tùy chọn: $s - $e';
      case 'all':
      default:
        return 'Toàn bộ thời gian (Tất cả)';
    }
  }

  /// Mở file trực tiếp bằng ứng dụng đọc Excel trên điện thoại
  Future<void> openFile(String filePath) async {
    try {
      await OpenFilex.open(filePath);
    } catch (e) {
      debugPrint('[ExcelExportService] Lỗi mở file: $e');
    }
  }

  /// Chia sẻ file qua Zalo, Gmail, Drive, Messenger...
  Future<void> shareFile(String filePath) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: 'Báo cáo chi tiêu tài chính FinWise (Excel)',
          subject: 'Sao kê chi tiêu FinWise',
        ),
      );
    } catch (e) {
      debugPrint('[ExcelExportService] Lỗi chia sẻ file: $e');
    }
  }
}
