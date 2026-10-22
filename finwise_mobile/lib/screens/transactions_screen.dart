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

class _TransactionsScreenState extends State<TransactionsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  late TabController _tabController;
  List<TransactionModel> _allTransactions = [];
  List<CategoryModel> _categories = [];
  bool _isLoading = true;

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
      setState(() {
        _allTransactions = results[0] as List<TransactionModel>;
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

                                if (confirm == true) {
                                  setModalState(() => isSaving = true);
                                  final nav = Navigator.of(ctx);
                                  final scaffoldMessenger = ScaffoldMessenger.of(context);
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

  @override
  Widget build(BuildContext context) {
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF4F46E5),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: const Color(0xFF4F46E5),
          tabs: const [
            Tab(text: 'Tất cả'),
            Tab(text: 'Khoản chi'),
            Tab(text: 'Thu nhập'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_allTransactions),
                _buildList(_allTransactions.where((t) => t.type == 'expense').toList()),
                _buildList(_allTransactions.where((t) => t.type == 'income').toList()),
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

  Widget _buildList(List<TransactionModel> items) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadData(showLoading: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFF94A3B8)),
                  SizedBox(height: 12),
                  Text(
                    'Chưa có giao dịch nào',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF334155)),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Vuốt xuống để làm mới hoặc đồng bộ dữ liệu.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
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
                            Text(dateStr, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
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
