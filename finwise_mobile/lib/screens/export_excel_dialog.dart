import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/category_model.dart';
import '../models/transaction_model.dart';
import '../services/api_service.dart';
import '../services/excel_export_service.dart';

class ExportExcelDialog extends StatefulWidget {
  final double currentBalance;
  const ExportExcelDialog({super.key, required this.currentBalance});

  static Future<void> show(BuildContext context, {required double currentBalance}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExportExcelDialog(currentBalance: currentBalance),
    );
  }

  @override
  State<ExportExcelDialog> createState() => _ExportExcelDialogState();
}

class _ExportExcelDialogState extends State<ExportExcelDialog> {
  bool _isLoading = true;
  bool _isExporting = false;
  List<TransactionModel> _allTransactions = [];
  List<CategoryModel> _categories = [];

  // Tùy chọn xuất
  String _dateFilterType = 'all'; // 'all', 'this_month', 'last_month', 'this_week', 'custom'
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String _typeFilter = 'all'; // 'all', 'expense', 'income'
  final Set<String> _selectedCategoryCodes = {}; // rỗng = tất cả

  final Map<String, bool> _columns = {
    'stt': true,
    'date': true,
    'type': true,
    'category': true,
    'amount': true,
    'note': true,
  };

  final Map<String, String> _columnLabels = {
    'stt': 'STT',
    'date': 'Ngày giao dịch',
    'type': 'Phân loại (Thu/Chi)',
    'category': 'Danh mục',
    'amount': 'Số tiền (VND)',
    'note': 'Nội dung ghi chú',
  };

  final dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final txs = await ApiService().getTransactions();
    final cats = await ApiService().getCategories();

    if (mounted) {
      setState(() {
        _allTransactions = txs;
        _categories = cats;
        _isLoading = false;
      });
    }
  }

  ExportOptions _buildOptions() {
    final chosenCols = _columns.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toSet();

    return ExportOptions(
      startDate: _customStartDate,
      endDate: _customEndDate,
      dateFilterType: _dateFilterType,
      typeFilter: _typeFilter,
      selectedCategoryCodes: Set.from(_selectedCategoryCodes),
      selectedColumns: chosenCols,
    );
  }

  List<TransactionModel> _getFilteredTransactions() {
    final options = _buildOptions();
    return ExcelExportService().filterTransactions(_allTransactions, options);
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final initialRange = DateTimeRange(
      start: _customStartDate ?? DateTime(now.year, now.month, 1),
      end: _customEndDate ?? now,
    );

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF4F46E5),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dateFilterType = 'custom';
        _customStartDate = picked.start;
        _customEndDate = picked.end;
      });
    }
  }

  Future<void> _handleExport() async {
    final filtered = _getFilteredTransactions();
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có giao dịch nào thỏa mãn bộ lọc để xuất!')),
      );
      return;
    }

    setState(() => _isExporting = true);

    final options = _buildOptions();
    final filePath = await ExcelExportService().exportTransactions(
      allTransactions: _allTransactions,
      user: ApiService().currentUser,
      currentBalance: widget.currentBalance,
      options: options,
    );

    setState(() => _isExporting = false);

    if (filePath != null && mounted) {
      Navigator.pop(context); // Đóng dialog tùy chọn
      _showSuccessDialog(filePath, filtered.length);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Xuất file Excel thất bại. Vui lòng thử lại!'),
        ),
      );
    }
  }

  void _showSuccessDialog(String filePath, int count) {
    final fileName = filePath.split(Platform.pathSeparator).last;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'Xuất File Excel Thành Công!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 6),
            Text(
              'Đã tạo báo cáo gồm $count giao dịch:',
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.table_view_rounded, size: 16, color: Color(0xFF10B981)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          fileName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    filePath.contains('/Download')
                        ? '📁 Đã lưu vào: Thư mục Tải xuống (Download)'
                        : '📁 Đã lưu tại: $filePath',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Nút Mở File
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  ExcelExportService().openFile(filePath);
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                label: const Text('Mở File Excel Ngay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Nút Chia Sẻ File
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  ExcelExportService().shareFile(filePath);
                },
                icon: const Icon(Icons.share_rounded, size: 20, color: Color(0xFF4F46E5)),
                label: const Text('Chia Sẻ File (Zalo, Gmail, Drive...)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF4F46E5))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFC7D2FE)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 250,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
        ),
      );
    }

    final filtered = _getFilteredTransactions();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Header kéo
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Tiêu đề
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.table_view_rounded, color: Color(0xFF10B981), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Tùy Chọn Xuất Báo Cáo Excel',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1E293B)),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Nội dung cuộn được
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. KHOẢNG THỜI GIAN
                  _buildSectionTitle('1. Khoảng Thời Gian', Icons.date_range_rounded),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChoiceChip('Tất cả', 'all', _dateFilterType, (val) => setState(() => _dateFilterType = val)),
                      _buildChoiceChip('Tháng này', 'this_month', _dateFilterType, (val) => setState(() => _dateFilterType = val)),
                      _buildChoiceChip('Tháng trước', 'last_month', _dateFilterType, (val) => setState(() => _dateFilterType = val)),
                      _buildChoiceChip('Tuần này', 'this_week', _dateFilterType, (val) => setState(() => _dateFilterType = val)),
                      ChoiceChip(
                        label: Text(
                          _dateFilterType == 'custom' && _customStartDate != null
                              ? '${dateFormat.format(_customStartDate!)} - ${dateFormat.format(_customEndDate!)}'
                              : 'Tùy chọn ngày...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _dateFilterType == 'custom' ? FontWeight.bold : FontWeight.normal,
                            color: _dateFilterType == 'custom' ? Colors.white : const Color(0xFF334155),
                          ),
                        ),
                        selected: _dateFilterType == 'custom',
                        selectedColor: const Color(0xFF4F46E5),
                        backgroundColor: const Color(0xFFF1F5F9),
                        onSelected: (_) => _pickCustomDateRange(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 2. LOẠI GIAO DỊCH
                  _buildSectionTitle('2. Loại Giao Dịch', Icons.swap_horiz_rounded),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildChoiceChip('Tất cả (Thu & Chi)', 'all', _typeFilter, (val) => setState(() => _typeFilter = val)),
                      _buildChoiceChip('Chỉ Chi tiêu (-)', 'expense', _typeFilter, (val) => setState(() => _typeFilter = val)),
                      _buildChoiceChip('Chỉ Thu nhập (+)', 'income', _typeFilter, (val) => setState(() => _typeFilter = val)),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 3. DANH MỤC
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle('3. Lọc Theo Danh Mục', Icons.category_rounded),
                      if (_selectedCategoryCodes.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() => _selectedCategoryCodes.clear()),
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          child: const Text('Bỏ chọn tất cả', style: TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Tất cả danh mục', style: TextStyle(fontSize: 12)),
                        selected: _selectedCategoryCodes.isEmpty,
                        selectedColor: const Color(0xFFEEF2FF),
                        checkmarkColor: const Color(0xFF4F46E5),
                        labelStyle: TextStyle(
                          color: _selectedCategoryCodes.isEmpty ? const Color(0xFF4F46E5) : const Color(0xFF334155),
                          fontWeight: _selectedCategoryCodes.isEmpty ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (_) => setState(() => _selectedCategoryCodes.clear()),
                      ),
                      ..._categories.map((c) {
                        final isSel = _selectedCategoryCodes.contains(c.code);
                        return FilterChip(
                          label: Text(c.name, style: const TextStyle(fontSize: 12)),
                          selected: isSel,
                          selectedColor: const Color(0xFFEEF2FF),
                          checkmarkColor: const Color(0xFF4F46E5),
                          labelStyle: TextStyle(
                            color: isSel ? const Color(0xFF4F46E5) : const Color(0xFF334155),
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedCategoryCodes.add(c.code);
                              } else {
                                _selectedCategoryCodes.remove(c.code);
                              }
                            });
                          },
                        );
                      }),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 4. CÁC CỘT HIỂN THỊ
                  _buildSectionTitle('4. Các Cột Muốn Xuất Trong File Excel', Icons.view_column_rounded),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: _columns.keys.map((key) {
                        return CheckboxListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text(_columnLabels[key] ?? key, style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B))),
                          activeColor: const Color(0xFF4F46E5),
                          value: _columns[key],
                          onChanged: (val) {
                            if (val != null) {
                              // Ít nhất phải giữ 1 cột
                              final checkedCount = _columns.values.where((v) => v).length;
                              if (!val && checkedCount <= 1) return;
                              setState(() => _columns[key] = val);
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Thanh Footer: Preview số lượng & Nút Xuất Excel
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -3)),
              ],
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Giao dịch thỏa mãn:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    Text(
                      '${filtered.length} giao dịch',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF10B981)),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isExporting ? null : _handleExport,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.file_download_rounded, size: 20),
                      label: Text(
                        _isExporting ? 'Đang tạo file...' : 'Xuất File Excel (.xlsx)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 17, color: const Color(0xFF4F46E5)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
        ),
      ],
    );
  }

  Widget _buildChoiceChip(String label, String value, String currentVal, Function(String) onSelected) {
    final isSel = currentVal == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
          color: isSel ? Colors.white : const Color(0xFF334155),
        ),
      ),
      selected: isSel,
      selectedColor: const Color(0xFF4F46E5),
      backgroundColor: const Color(0xFFF1F5F9),
      onSelected: (_) => onSelected(value),
    );
  }
}
