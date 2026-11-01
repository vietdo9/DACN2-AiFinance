import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction_model.dart';
import '../models/category_model.dart';
import '../services/api_service.dart';
import '../services/notification_sync_service.dart';
import 'add_transaction_screen.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

enum TimePeriodFilter { all, week, month }

class _TransactionsScreenState extends State<TransactionsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  late TabController _tabController;
  List<TransactionModel> _allTransactions = [];
  List<CategoryModel> _categories = [];
  bool _isLoading = true;

  // Bộ lọc mốc thời gian: Mặc định lọc theo Tháng
  TimePeriodFilter _periodFilter = TimePeriodFilter.month;
  DateTime _selectedWeekDate = DateTime.now();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  DateTime get _startOfWeek {
    final d = DateTime(_selectedWeekDate.year, _selectedWeekDate.month, _selectedWeekDate.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  DateTime get _endOfWeek {
    return _startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
  }

  bool get _isCurrentWeek {
    final now = DateTime.now();
    final nowStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    return nowStart.year == _startOfWeek.year &&
        nowStart.month == _startOfWeek.month &&
        nowStart.day == _startOfWeek.day;
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return now.year == _selectedMonth.year && now.month == _selectedMonth.month;
  }

  String get _weekTitle {
    final startStr = DateFormat('dd/MM').format(_startOfWeek);
    final endStr = DateFormat('dd/MM/yyyy').format(_endOfWeek);
    if (_isCurrentWeek) {
      return 'Tuần này ($startStr - $endStr)';
    }
    return 'Tuần $startStr - $endStr';
  }

  String get _monthTitle {
    final mStr = DateFormat('MM/yyyy').format(_selectedMonth);
    if (_isCurrentMonth) {
      return 'Tháng này (Tháng $mStr)';
    }
    return 'Tháng $mStr';
  }

  List<TransactionModel> get _periodTransactions {
    if (_periodFilter == TimePeriodFilter.all) {
      return _allTransactions;
    } else if (_periodFilter == TimePeriodFilter.week) {
      final s = DateTime(_startOfWeek.year, _startOfWeek.month, _startOfWeek.day);
      final e = DateTime(_endOfWeek.year, _endOfWeek.month, _endOfWeek.day, 23, 59, 59);
      return _allTransactions.where((tx) {
        final d = tx.transactionDate;
        return !d.isBefore(s) && !d.isAfter(e);
      }).toList();
    } else {
      return _allTransactions.where((tx) {
        return tx.transactionDate.year == _selectedMonth.year &&
            tx.transactionDate.month == _selectedMonth.month;
      }).toList();
    }
  }

  void _onPreviousPeriod() {
    setState(() {
      if (_periodFilter == TimePeriodFilter.week) {
        _selectedWeekDate = _selectedWeekDate.subtract(const Duration(days: 7));
      } else if (_periodFilter == TimePeriodFilter.month) {
        _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
      }
    });
  }

  void _onNextPeriod() {
    setState(() {
      if (_periodFilter == TimePeriodFilter.week) {
        _selectedWeekDate = _selectedWeekDate.add(const Duration(days: 7));
      } else if (_periodFilter == TimePeriodFilter.month) {
        _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
      }
    });
  }

  void _onResetToCurrent() {
    setState(() {
      _selectedWeekDate = DateTime.now();
      _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    });
  }

  Future<void> _showPickWeekDialog() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedWeekDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'CHỌN NGÀY ĐỂ XEM TUẦN ĐÓ',
    );
    if (picked != null) {
      setState(() => _selectedWeekDate = picked);
    }
  }

  Future<void> _showPickMonthDialog() async {
    int tempYear = _selectedMonth.year;
    int tempMonth = _selectedMonth.month;

    await showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF4F46E5)),
                onPressed: () => setDialogState(() => tempYear--),
              ),
              Text(
                'Năm $tempYear',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF4F46E5)),
                onPressed: () => setDialogState(() => tempYear++),
              ),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.6,
              ),
              itemCount: 12,
              itemBuilder: (ctx, idx) {
                final m = idx + 1;
                final isSelected = m == tempMonth && tempYear == _selectedMonth.year;
                final isCurrent = m == DateTime.now().month && tempYear == DateTime.now().year;

                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _selectedMonth = DateTime(tempYear, m, 1);
                    });
                    Navigator.pop(dCtx);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF4F46E5)
                          : (isCurrent ? const Color(0xFFEEF2FF) : Colors.white),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF4F46E5)
                            : (isCurrent ? const Color(0xFF818CF8) : const Color(0xFFE2E8F0)),
                        width: isCurrent ? 1.5 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Tháng $m',
                      style: TextStyle(
                        fontWeight: isSelected || isCurrent ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                        color: isSelected
                            ? Colors.white
                            : (isCurrent ? const Color(0xFF4F46E5) : const Color(0xFF334155)),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Đóng'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                setState(() {
                  _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
                });
                Navigator.pop(dCtx);
              },
              child: const Text('Về Tháng Này', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    NotificationSyncService().dataRefreshTrigger.addListener(_onAutoRefresh);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationSyncService().dataRefreshTrigger.removeListener(_onAutoRefresh);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadData(showLoading: false);
    }
  }

  void _onAutoRefresh() {
    if (mounted) {
      _loadData(showLoading: false);
    }
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    final results = await Future.wait([
      ApiService().getTransactions(),
      ApiService().getCategories(),
    ]);

    if (mounted) {
      final txs = results[0] as List<TransactionModel>;
      txs.sort((a, b) => a.compareToTime(b));
      setState(() {
        _allTransactions = txs;
        _categories = results[1] as List<CategoryModel>;
        _isLoading = false;
      });
    }
  }

  // Mở BottomSheet Chi tiết & Chỉnh sửa giao dịch
  void _showEditTransactionModal(TransactionModel tx) {
    String editType = tx.type;
    String editCategoryCode = tx.categoryCode;
    DateTime editDate = tx.transactionDate;

    // Phân tách ghi chú và người nhận/gửi nếu đã có sẵn
    String initialNote = tx.note;
    String initialCounterparty = '';
    final partyInNote = RegExp(r'\((?:Đến|Từ|den|tu|to|from)[:\s]+([^)]+)\)', caseSensitive: false).firstMatch(tx.note);
    if (partyInNote != null) {
      initialCounterparty = partyInNote.group(1)!.trim();
      initialNote = tx.note.replaceAll(partyInNote.group(0)!, '').trim();
    }

    final amountController = TextEditingController(text: tx.amount.toInt().toString());
    final noteController = TextEditingController(text: initialNote);
    final counterpartyController = TextEditingController(text: initialCounterparty);
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isIncome = editType == 'income';
          final currentColor = isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444);

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thanh kéo xám
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Header: Tiêu đề + Huy hiệu AI (nếu có)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Chi Tiết Giao Dịch',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      if (tx.aiPredicted)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFC7D2FE)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome, color: Color(0xFF4F46E5), size: 12),
                              SizedBox(width: 4),
                              Text('AI PhoBERT', style: TextStyle(color: Color(0xFF4F46E5), fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 1. Chuyển đổi Loại: Chi tiêu / Thu nhập
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setModalState(() {
                                editType = 'expense';
                                final expenseCats = _categories.where((c) => c.type == 'expense').toList();
                                editCategoryCode = expenseCats.isNotEmpty ? expenseCats.first.code : 'AN_UONG';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: editType == 'expense' ? const Color(0xFFEF4444) : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Khoản Chi',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: editType == 'expense' ? Colors.white : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setModalState(() {
                                editType = 'income';
                                final incomeCats = _categories.where((c) => c.type == 'income').toList();
                                editCategoryCode = incomeCats.isNotEmpty ? incomeCats.first.code : 'THU_NHAP';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: editType == 'income' ? const Color(0xFF10B981) : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Thu Nhập',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: editType == 'income' ? Colors.white : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Ô nhập số tiền
                  const Text('Số tiền (VNĐ)', style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: currentColor),
                    decoration: InputDecoration(
                      prefixText: '₫ ',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3. Ô nhập ghi chú
                  const Text('Ghi chú giao dịch', style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: noteController,
                    decoration: InputDecoration(
                      hintText: 'Nhập món ăn, mua sắm hoặc lý do (ví dụ: tiền ăn hủ tiếu)...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3.1. Ô nhập Người nhận / Người gửi
                  Text(
                    isIncome ? 'Nhận Từ Ai / Người Gửi (Tùy chọn)' : 'Gửi Cho Ai / Người Nhận (Tùy chọn)',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: counterpartyController,
                    decoration: InputDecoration(
                      hintText: isIncome ? 'Ví dụ: Công ty, Anh Nam, Bố mẹ...' : 'Ví dụ: Quán hủ tiếu Cô Ba, Anh Tuấn...',
                      prefixIcon: Icon(
                        isIncome ? Icons.person_add_alt_1_rounded : Icons.person_outline_rounded,
                        color: isIncome ? const Color(0xFF10B981) : const Color(0xFF4F46E5),
                        size: 20,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 4. Chọn ngày giao dịch
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Color(0xFF64748B)),
                      const SizedBox(width: 8),
                      Text(
                        'Ngày: ${DateFormat('dd/MM/yyyy').format(editDate)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: editDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setModalState(() => editDate = picked);
                          }
                        },
                        child: const Text('Đổi ngày', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 5. Chọn Danh Mục Phân Loại (Lọc chính xác theo Thu hoặc Chi)
                  Text(
                    editType == 'income' ? 'Phân Loại Thu Nhập' : 'Phân Loại Khoản Chi',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      List<CategoryModel> displayedCategories = _categories.where((c) => c.type == editType).toList();
                      if (displayedCategories.isEmpty) {
                        if (editType == 'income') {
                          displayedCategories = [
                            CategoryModel(code: 'THU_NHAP', name: 'Thu Nhập & Lương', type: 'income', icon: 'payments', color: const Color(0xFF10B981)),
                          ];
                        } else {
                          displayedCategories = [
                            CategoryModel(code: 'AN_UONG', name: 'Ăn Uống', type: 'expense', icon: 'restaurant', color: const Color(0xFFF59E0B)),
                          ];
                        }
                      }
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: editType == 'income' ? 3 : 5,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                          childAspectRatio: editType == 'income' ? 1.1 : 0.9,
                        ),
                        itemCount: displayedCategories.length,
                        itemBuilder: (context, index) {
                          final cat = displayedCategories[index];
                          final isSelected = cat.code == editCategoryCode;

                          return GestureDetector(
                            onTap: () => setModalState(() => editCategoryCode = cat.code),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected ? cat.color.withValues(alpha: 0.15) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? cat.color : const Color(0xFFE2E8F0),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(cat.iconData, color: cat.color, size: 20),
                                  const SizedBox(height: 4),
                                  Text(
                                    cat.name,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? cat.color : const Color(0xFF334155),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // 6. Nút Cập Nhật & Nút Xóa
                  Row(
                    children: [
                      // Nút Xóa
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFFEE2E2),
                          foregroundColor: const Color(0xFFEF4444),
                          padding: const EdgeInsets.all(12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 22),
                        onPressed: isSaving
                            ? null
                            : () async {
                                final nav = Navigator.of(ctx);
                                final scaffoldMessenger = ScaffoldMessenger.of(context);
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (dCtx) => AlertDialog(
                                    title: const Text('Xác nhận xóa'),
                                    content: const Text('Bạn có chắc chắn muốn xóa giao dịch này không? Số dư ví sẽ được hoàn lại tương ứng.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Hủy')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                        onPressed: () => Navigator.pop(dCtx, true),
                                        child: const Text('Xóa', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true && mounted) {
                                  setModalState(() => isSaving = true);
                                  final success = await ApiService().deleteTransaction(tx.id);
                                  nav.pop();
                                  if (mounted) {
                                    if (success) {
                                      scaffoldMessenger.showSnackBar(
                                        const SnackBar(content: Text('Đã xóa giao dịch thành công!')),
                                      );
                                      NotificationSyncService().dataRefreshTrigger.value++;
                                      _loadData();
                                    }
                                  }
                                }
                              },
                      ),
                      const SizedBox(width: 12),
                      // Nút Lưu thay đổi
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final amtText = amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
                                  final amt = double.tryParse(amtText);
                                  if (amt == null || amt <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Vui lòng nhập số tiền hợp lệ!')),
                                    );
                                    return;
                                  }

                                  setModalState(() => isSaving = true);
                                  final nav = Navigator.of(ctx);
                                  final scaffoldMessenger = ScaffoldMessenger.of(context);

                                  const knownExpenseCodes = {
                                    'AN_UONG', 'DI_LAI', 'MUA_SAM', 'HOA_DON', 'NHA_O',
                                    'GIAI_TRI', 'SUC_KHOE', 'HOC_TAP', 'TIET_KIEM_DAU_TU'
                                  };
                                  const knownIncomeCodes = {'THU_NHAP', 'TIEN_CHUYEN_DEN', 'THU_KHAC'};

                                  String finalCatCode = editCategoryCode;
                                  if (editType == 'income') {
                                    if (!knownIncomeCodes.contains(finalCatCode)) {
                                      finalCatCode = 'THU_NHAP';
                                    }
                                  } else {
                                    if (!knownExpenseCodes.contains(finalCatCode)) {
                                      finalCatCode = 'AN_UONG';
                                    }
                                  }

                                  final rawNote = noteController.text.trim();
                                  final party = counterpartyController.text.trim();
                                  String finalNote = rawNote;
                                  if (party.isNotEmpty) {
                                    finalNote = editType == 'income'
                                        ? (rawNote.isNotEmpty ? '$rawNote (Từ: $party)' : 'Nhận từ $party')
                                        : (rawNote.isNotEmpty ? '$rawNote (Đến: $party)' : 'Chuyển cho $party');
                                  }

                                  final success = await ApiService().updateTransaction(
                                    id: tx.id,
                                    amount: amt,
                                    note: finalNote,
                                    type: editType,
                                    categoryCode: finalCatCode,
                                    transactionDate: DateFormat('yyyy-MM-dd').format(editDate),
                                  );

                                  nav.pop();
                                  if (mounted) {
                                    if (success) {
                                      scaffoldMessenger.showSnackBar(
                                        const SnackBar(
                                          backgroundColor: Color(0xFF10B981),
                                          content: Text('✨ Đã cập nhật giao dịch & lưu thói quen cá nhân!'),
                                        ),
                                      );
                                      NotificationSyncService().dataRefreshTrigger.value++;
                                      _loadData();
                                    } else {
                                      scaffoldMessenger.showSnackBar(
                                        const SnackBar(content: Text('Lỗi cập nhật giao dịch.')),
                                      );
                                    }
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Lưu Thay Đổi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterSegment() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _buildSegmentButton('Theo Tháng', TimePeriodFilter.month),
            _buildSegmentButton('Theo Tuần', TimePeriodFilter.week),
            _buildSegmentButton('Tất cả', TimePeriodFilter.all),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentButton(String label, TimePeriodFilter filter) {
    final isSelected = _periodFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_periodFilter != filter) {
            setState(() {
              _periodFilter = filter;
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodNavigator() {
    final isWeek = _periodFilter == TimePeriodFilter.week;
    final isCurrent = isWeek ? _isCurrentWeek : _isCurrentMonth;
    final title = isWeek ? _weekTitle : _monthTitle;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Nút Lùi kỳ trước
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF4F46E5), size: 24),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFEEF2FF),
              padding: const EdgeInsets.all(6),
              minimumSize: const Size(36, 36),
            ),
            tooltip: isWeek ? 'Tuần trước' : 'Tháng trước',
            onPressed: _onPreviousPeriod,
          ),
          const SizedBox(width: 8),

          // Nút Chọn kỳ ở giữa (Click để mở lịch chọn nhanh)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: isWeek ? _showPickWeekDialog : _showPickMonthDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isWeek ? Icons.date_range_rounded : Icons.calendar_month_rounded,
                      size: 16,
                      color: const Color(0xFF4F46E5),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF1E293B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B), size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Nút Sang kỳ sau
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF4F46E5), size: 24),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFEEF2FF),
              padding: const EdgeInsets.all(6),
              minimumSize: const Size(36, 36),
            ),
            tooltip: isWeek ? 'Tuần sau' : 'Tháng sau',
            onPressed: _onNextPeriod,
          ),

          // Nút Reset về hiện tại nếu đang xem kỳ quá khứ / tương lai
          if (!isCurrent) ...[
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _onResetToCurrent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Hiện tại',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCard(List<TransactionModel> periodTxs) {
    double totalIncome = 0;
    double totalExpense = 0;
    for (final tx in periodTxs) {
      if (tx.type == 'income') {
        totalIncome += tx.amount;
      } else {
        totalExpense += tx.amount;
      }
    }
    final net = totalIncome - totalExpense;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Tổng thu
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.arrow_downward_rounded, size: 14, color: Color(0xFF10B981)),
                    SizedBox(width: 4),
                    Text('Tổng Thu', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '+${currencyFormat.format(totalIncome)}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 28, width: 1, color: const Color(0xFFE2E8F0)),
          // Tổng chi
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.arrow_upward_rounded, size: 14, color: Color(0xFFEF4444)),
                      SizedBox(width: 4),
                      Text('Tổng Chi', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '-${currencyFormat.format(totalExpense)}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(height: 28, width: 1, color: const Color(0xFFE2E8F0)),
          // Chênh lệch (Thuần)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, size: 14, color: Color(0xFF4F46E5)),
                      SizedBox(width: 4),
                      Text('Chênh Lệch', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${net >= 0 ? '+' : ''}${currencyFormat.format(net)}',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: net >= 0 ? const Color(0xFF1E293B) : const Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final periodTxs = _periodTransactions;
    final expenseTxs = periodTxs.where((t) => t.type == 'expense').toList();
    final incomeTxs = periodTxs.where((t) => t.type == 'income').toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Lịch Sử Thu Chi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B))),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Color(0xFF4F46E5)),
            tooltip: 'Đồng bộ ngay',
            onPressed: () => _loadData(showLoading: false),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilterSegment(),
                if (_periodFilter != TimePeriodFilter.all) _buildPeriodNavigator(),
                _buildSummaryCard(periodTxs),
                Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFF4F46E5),
                    unselectedLabelColor: const Color(0xFF64748B),
                    indicatorColor: const Color(0xFF4F46E5),
                    indicatorWeight: 2.5,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
                    tabs: [
                      Tab(text: 'Tất cả (${periodTxs.length})'),
                      Tab(text: 'Khoản chi (${expenseTxs.length})'),
                      Tab(text: 'Thu nhập (${incomeTxs.length})'),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildList(periodTxs, 'Không có giao dịch nào trong khoảng thời gian này'),
                      _buildList(expenseTxs, 'Không có khoản chi nào trong khoảng thời gian này'),
                      _buildList(incomeTxs, 'Không có thu nhập nào trong khoảng thời gian này'),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF4F46E5),
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () async {
          final res = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddTransactionScreen()),
          );
          if (res == true) {
            NotificationSyncService().dataRefreshTrigger.value++;
            _loadData();
          }
        },
      ),
    );
  }

  Widget _buildList(List<TransactionModel> items, [String emptyMessage = 'Chưa có giao dịch nào']) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadData(showLoading: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.receipt_long_outlined, size: 42, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    emptyMessage,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _periodFilter != TimePeriodFilter.all
                        ? 'Thử chuyển sang tuần/tháng khác hoặc thêm giao dịch mới.'
                        : 'Vuốt xuống để làm mới hoặc đồng bộ dữ liệu.',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(showLoading: false),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
      itemBuilder: (context, index) {
        final tx = items[index];
        final isIncome = tx.type == 'income';
        final color = isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444);
        final dateStr = DateFormat('dd/MM/yyyy').format(tx.transactionDate);
        final timeSuffix = tx.createdAt != null
            ? ' • ${DateFormat('HH:mm').format(tx.createdAt!.toLocal())}'
            : '';

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _showEditTransactionModal(tx),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF1F5F9)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(isIncome ? Icons.arrow_downward : Icons.arrow_upward, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tx.note.isNotEmpty ? tx.note : (tx.categoryName ?? tx.categoryCode),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text('$dateStr$timeSuffix', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                            if (tx.aiPredicted) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('AI PhoBERT', style: TextStyle(color: Color(0xFF4F46E5), fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '${isIncome ? '+' : '-'}${currencyFormat.format(tx.amount)}',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 16, color: Color(0xFFCBD5E1)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
}
