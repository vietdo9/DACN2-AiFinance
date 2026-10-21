import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import '../services/notification_sync_service.dart';
import '../models/transaction_model.dart';
import 'add_transaction_screen.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int) onNavigateTab;
  const DashboardScreen({super.key, required this.onNavigateTab});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  bool _isLoading = true;
  Map<String, dynamic> _summary = {};
  List<TransactionModel> _recentTransactions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData(showLoading: true);
    NotificationSyncService().checkPermission();
    NotificationSyncService().dataRefreshTrigger.addListener(_onAutoRefresh);
    NotificationSyncService().lastCapturedMessage.addListener(_onAutoRefresh);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationSyncService().dataRefreshTrigger.removeListener(_onAutoRefresh);
    NotificationSyncService().lastCapturedMessage.removeListener(_onAutoRefresh);
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

  Future<void> _loadData({bool showLoading = false}) async {
    if (showLoading && _summary.isEmpty) {
      setState(() => _isLoading = true);
    }
    final results = await Future.wait([
      ApiService().getSummary(),
      ApiService().getTransactions(),
    ]);
    if (mounted) {
      setState(() {
        final summaryData = results[0] as Map<String, dynamic>;
        if (summaryData.isNotEmpty) {
          _summary = summaryData;
        }
        final txs = results[1] as List<TransactionModel>;
        _recentTransactions = txs.take(5).toList();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    double totalBalance = (_summary['total_balance'] as num?)?.toDouble() ?? 0.0;
    final income = (_summary['this_month_income'] as num?)?.toDouble() ?? 0.0;
    final expense = (_summary['this_month_expense'] as num?)?.toDouble() ?? 0.0;
    final categoryBreakdown = (_summary['expense_by_category'] as List?) ?? [];

    // Tự động tính số dư ròng (Net Balance) nếu API chưa kịp cập nhật số dư
    if (totalBalance == 0.0 && (income > 0 || expense > 0)) {
      totalBalance = income - expense;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome, color: Color(0xFF4F46E5), size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('FinWise AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B))),
                Text('Quản lý tài chính cá nhân', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Color(0xFF4F46E5)),
            tooltip: 'Đồng bộ ngay',
            onPressed: () => _loadData(showLoading: false),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(showLoading: false),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Thẻ Số Dư Cao Cấp (Gradient Card)
              _buildBalanceCard(totalBalance, income, expense),

              const SizedBox(height: 16),

              // Banner Trạng Thái Bắt Thông Báo Tự Động (ShopeePay, MoMo, Bank)
              _buildNotificationListenerBanner(),

              const SizedBox(height: 16),

              // 2. Banner Trí Tuệ Nhân Tạo (AI Smart Insight)
              _buildAiInsightBanner(),

              const SizedBox(height: 20),

              // 3. Phân bổ chi tiêu theo Danh mục (Pie Chart)
              if (categoryBreakdown.isNotEmpty) ...[
                const Text('Phân Bổ Chi Tiêu', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                const SizedBox(height: 12),
                _buildCategoryChart(categoryBreakdown),
                const SizedBox(height: 24),
              ],

              // 4. Lịch sử giao dịch gần đây
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Giao Dịch Gần Đây', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  TextButton(
                    onPressed: () => widget.onNavigateTab(1),
                    child: const Text('Xem tất cả', style: TextStyle(color: Color(0xFF4F46E5))),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildRecentTransactionsList(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF4F46E5),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Thêm Thu/Chi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddTransactionScreen()),
          );
          if (result == true) {
            NotificationSyncService().dataRefreshTrigger.value++;
            _loadData(showLoading: false);
          }
        },
      ),
    );
  }

  Widget _buildBalanceCard(double balance, double income, double expense) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF3730A3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tổng số dư hiện tại', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            currencyFormat.format(balance),
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_downward, color: Color(0xFF10B981), size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Thu tháng này', style: TextStyle(color: Colors.white70, fontSize: 11)),
                            Text(currencyFormat.format(income), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_upward, color: Color(0xFFEF4444), size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Chi tháng này', style: TextStyle(color: Colors.white70, fontSize: 11)),
                            Text(currencyFormat.format(expense), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAiInsightBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.psychology, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dự Báo Tài Chính AI (LSTM)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                const SizedBox(height: 3),
                const Text('AI đang tính toán dòng tiền 7 ngày tới dựa trên 30 ngày lịch sử chi tiêu của bạn.', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => widget.onNavigateTab(2), // Chuyển sang Tab AI
            child: const Text('Xem', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChart(List<dynamic> categories) {
    final colors = [
      const Color(0xFFF59E0B),
      const Color(0xFF3B82F6),
      const Color(0xFF8B5CF6),
      const Color(0xFF6366F1),
      const Color(0xFFEC4899),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 40,
                sections: List.generate(categories.length, (i) {
                  final cat = categories[i];
                  final pct = (cat['percentage'] as num?)?.toDouble() ?? 10.0;
                  final color = colors[i % colors.length];
                  return PieChartSectionData(
                    color: color,
                    value: pct,
                    title: '${pct.toStringAsFixed(0)}%',
                    radius: 45,
                    titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: List.generate(categories.length, (i) {
              final cat = categories[i];
              final color = colors[i % colors.length];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('${cat['category_name']}: ${currencyFormat.format(cat['total'])}', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactionsList() {
    if (_recentTransactions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Column(
          children: [
            const Icon(Icons.receipt_long_outlined, size: 36, color: Color(0xFF94A3B8)),
            const SizedBox(height: 8),
            const Text(
              'Chưa có giao dịch nào',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Hãy bấm nút "Thêm Thu/Chi" góc dưới để ghi lại khoản tiền đầu tiên của bạn!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _recentTransactions.map((tx) {
        final isIncome = tx.type == 'income';
        final color = isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444);
        final dateStr = DateFormat('dd/MM/yyyy').format(tx.transactionDate);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.note.isNotEmpty ? tx.note : (tx.categoryName ?? tx.categoryCode),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                              color: const Color(0xFF4F46E5).withOpacity(0.12),
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
              Text(
                '${isIncome ? '+' : '-'}${currencyFormat.format(tx.amount)}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Banner hiển thị trạng thái lắng nghe thông báo biến động số dư
  Widget _buildNotificationListenerBanner() {
    return ValueListenableBuilder<bool>(
      valueListenable: NotificationSyncService().isPermissionEnabled,
      builder: (context, isEnabled, child) {
        if (!isEnabled) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFEF3C7), Color(0xFFFFFBEB)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFDE68A)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF59E0B).withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.notifications_active, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tự Động Bắt Thông Báo Biến Động',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E)),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Cấp quyền để FinWise tự động lưu giao dịch từ ShopeePay, MoMo, VCB, MB...',
                        style: TextStyle(fontSize: 11, color: Color(0xFF78350F)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    await NotificationSyncService().requestPermission();
                  },
                  child: const Text('Bật Ngay', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Tự động bắt thông báo ShopeePay & Ngân hàng: Đang hoạt động',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF065F46)),
                ),
              ),
              const Icon(Icons.check_circle, size: 16, color: Color(0xFF10B981)),
            ],
          ),
        );
      },
    );
  }
}

