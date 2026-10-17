import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/forecast_model.dart';
import '../services/api_service.dart';
import 'add_transaction_screen.dart';

class AiForecastScreen extends StatefulWidget {
  const AiForecastScreen({super.key});

  @override
  State<AiForecastScreen> createState() => _AiForecastScreenState();
}

class _AiForecastScreenState extends State<AiForecastScreen> {
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  bool _isLoading = true;
  ForecastModel? _forecast;
  bool _isDemoMode = false;

  @override
  void initState() {
    super.initState();
    _loadForecast();
  }

  Future<void> _loadForecast({bool isDemo = false}) async {
    setState(() {
      _isLoading = true;
      _isDemoMode = isDemo;
    });

    final data = await ApiService().getAiForecast(isDemo: isDemo);

    if (mounted) {
      setState(() {
        _forecast = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF4F46E5)),
              SizedBox(height: 16),
              Text(
                'Mạng nơ-ron LSTM đang phân tích chuỗi thời gian...',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final forecast = _forecast ?? ForecastModel.empty();

    // Nếu tài khoản mới chưa có dữ liệu và không ở chế độ Demo
    if (!forecast.hasEnoughData && !_isDemoMode) {
      return _buildEmptyState();
    }

    final warningColor = _getWarningColor(forecast.warningLevel);
    final warningText = _getWarningText(forecast.warningLevel);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Dự Báo Chi Tiêu AI',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B)),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
            onPressed: () => _loadForecast(isDemo: _isDemoMode),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner báo hiệu nếu đang xem dữ liệu mô phỏng
            if (_isDemoMode || forecast.isDemoData) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.science_outlined, color: Color(0xFFD97706), size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Đang xem mô phỏng thử nghiệm AI (Demo). Dữ liệu này không ảnh hưởng đến số dư thật.',
                        style: TextStyle(color: Color(0xFF92400E), fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _loadForecast(isDemo: false),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: const Text('Thoát Demo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],

            // 1. Thẻ Cảnh Báo Rủi Ro Ngân Sách
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: warningColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: warningColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: warningColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.insights, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Mức cảnh báo:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: warningColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                warningText,
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          forecast.message,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 2. Thống Kê Tổng Dự Báo
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tổng dự chi 7 ngày tới', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          currencyFormat.format(forecast.totalForecast),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF4F46E5)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Chi tiêu TB/ngày', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          currencyFormat.format(forecast.averageDailyForecast),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 3. Biểu Đồ Xu Hướng 7 Ngày Tiếp Theo
            const Text(
              'Biểu Đồ Xu Hướng 7 Ngày Tiếp Theo',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 24, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: SizedBox(
                height: 220,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(color: const Color(0xFFF1F5F9), strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          getTitlesWidget: (val, meta) {
                            final idx = val.toInt();
                            if (idx >= 0 && idx < 7) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text('N+${idx + 1}', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 42,
                          getTitlesWidget: (val, meta) {
                            if (val == 0) return const SizedBox.shrink();
                            return Text('${(val / 1000).toStringAsFixed(0)}k', style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8)));
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: List.generate(forecast.predictedNext7Days.length, (i) {
                          return FlSpot(i.toDouble(), forecast.predictedNext7Days[i]);
                        }),
                        isCurved: true,
                        color: const Color(0xFF4F46E5),
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 4. Danh Sách Chi Tiết Từng Ngày
            const Text(
              'Chi Tiết Từng Ngày',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 12),
            Column(
              children: List.generate(forecast.predictedNext7Days.length, (i) {
                final amt = forecast.predictedNext7Days[i];
                final date = DateTime.now().add(Duration(days: i + 1));
                const weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
                final dayName = weekdays[date.weekday - 1];
                final dateStr = '$dayName, ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('Ngày ${i + 1}', style: const TextStyle(color: Color(0xFF4F46E5), fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(dateStr, style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
                      ),
                      Text(
                        currencyFormat.format(amt),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // Màn hình Empty State khi tài khoản mới toanh chưa có chi tiêu
  Widget _buildEmptyState() {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Dự Báo Chi Tiêu AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B))),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
            onPressed: () => _loadForecast(isDemo: false),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.auto_awesome, color: Color(0xFF4F46E5), size: 48),
              ),
              const SizedBox(height: 20),
              const Text(
                'Tài Khoản Mới Đang Chờ Dữ Liệu',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Mô hình AI (LSTM) của FinWise phân tích chuỗi thời gian độc lập cho từng tài khoản riêng biệt. Bạn chưa có giao dịch chi tiêu nào để AI phân tích thói quen dòng tiền.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.5),
              ),
              const SizedBox(height: 28),

              // Thẻ lợi ích
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 2))
                  ],
                ),
                child: const Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lock_outline, color: Color(0xFF10B981), size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('Dữ liệu phân tích hoàn toàn riêng tư cho tài khoản của bạn', style: TextStyle(fontSize: 12, color: Color(0xFF334155))),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.electric_bolt_outlined, color: Color(0xFFF59E0B), size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('AI tự động học sau mỗi lần bạn thêm chi tiêu mới', style: TextStyle(fontSize: 12, color: Color(0xFF334155))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Nút thêm giao dịch đầu tiên
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
                    );
                    _loadForecast();
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  label: const Text('Thêm Giao Dịch Đầu Tiên', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Nút xem demo mô phỏng cho thuyết trình đồ án
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () => _loadForecast(isDemo: true),
                  icon: const Icon(Icons.science_outlined, size: 18, color: Color(0xFF64748B)),
                  label: const Text(
                    'Xem Thử Nghiệm Mô Phỏng AI (Demo)',
                    style: TextStyle(fontSize: 13, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getWarningColor(String level) {
    switch (level) {
      case 'CAO':
        return const Color(0xFFEF4444);
      case 'TRUNG_BINH':
        return const Color(0xFFF59E0B);
      case 'AN_TOAN':
      default:
        return const Color(0xFF10B981);
    }
  }

  String _getWarningText(String level) {
    switch (level) {
      case 'CAO':
        return 'NGUY CƠ BỘI CHI';
      case 'TRUNG_BINH':
        return 'CẦN LƯU Ý';
      case 'AN_TOAN':
      default:
        return 'AN TOÀN & ỔN ĐỊNH';
    }
  }
}
