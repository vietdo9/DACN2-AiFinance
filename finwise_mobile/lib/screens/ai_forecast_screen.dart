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
  int _selectedViewTab = 0; // 0: Theo Tuần (7 Ngày), 1: Theo Tháng

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

            // 1. Bộ chuyển đổi chế độ xem: Theo Tuần vs Theo Tháng
            _buildViewSegment(),
            const SizedBox(height: 16),

            // 2. Nội dung hiển thị theo chế độ đã chọn
            if (_selectedViewTab == 0)
              _buildWeekView(forecast)
            else
              _buildMonthView(forecast),
          ],
        ),
      ),
    );
  }

  // Segment chọn xem Theo Tuần / Theo Tháng
  Widget _buildViewSegment() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedViewTab = 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _selectedViewTab == 0 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _selectedViewTab == 0
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.date_range_rounded,
                      size: 16,
                      color: _selectedViewTab == 0 ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Theo Tuần',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _selectedViewTab == 0 ? FontWeight.bold : FontWeight.w500,
                        color: _selectedViewTab == 0 ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedViewTab = 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _selectedViewTab == 1 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _selectedViewTab == 1
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 16,
                      color: _selectedViewTab == 1 ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Theo Tháng',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _selectedViewTab == 1 ? FontWeight.bold : FontWeight.w500,
                        color: _selectedViewTab == 1 ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // VIEW 1: DỰ BÁO THEO TUẦN (7 NGÀY TỚI)
  // ==========================================
  Widget _buildWeekView(ForecastModel forecast) {
    final warningColor = _getWarningColor(forecast.warningLevel);
    final warningText = _getWarningText(forecast.warningLevel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Thẻ Cảnh Báo Rủi Ro
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: warningColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: warningColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: warningColor, shape: BoxShape.circle),
                child: const Icon(Icons.insights, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Đánh giá AI:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: warningColor, borderRadius: BorderRadius.circular(6)),
                          child: Text(warningText, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(forecast.message, style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 2. Thẻ So Sánh Tuần (Tuần Trước vs Tuần Tới)
        _buildWeekComparisonCard(forecast),

        const SizedBox(height: 20),

        // 3. Biểu Đồ Chi Tiêu Tuần Này
        const Text(
          'Biểu Đồ Chi Tiêu Tuần Này',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 24, 20, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
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
                      reservedSize: 34,
                      interval: 1,
                      getTitlesWidget: (val, meta) {
                        final idx = val.toInt();
                        if (forecast.weekDaysDetail.isNotEmpty && idx >= 0 && idx < forecast.weekDaysDetail.length) {
                          final item = forecast.weekDaysDetail[idx];
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.dayName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: item.isPastOrToday ? FontWeight.bold : FontWeight.w500,
                                    color: item.isPastOrToday ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                  ),
                                ),
                                Text(
                                  item.dayLabel,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: item.isPastOrToday ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          );
                        } else if (idx >= 0 && idx < 7) {
                          final date = DateTime.now().add(Duration(days: idx + 1));
                          final dayStr = DateFormat('dd/MM').format(date);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(dayStr, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
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
                    spots: forecast.weekDaysDetail.isNotEmpty
                        ? List.generate(forecast.weekDaysDetail.length, (i) {
                            return FlSpot(i.toDouble(), forecast.weekDaysDetail[i].amount);
                          })
                        : List.generate(forecast.predictedNext7Days.length, (i) {
                            return FlSpot(i.toDouble(), forecast.predictedNext7Days[i]);
                          }),
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: const Color(0xFF4F46E5),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        final isPast = (forecast.weekDaysDetail.isNotEmpty && index < forecast.weekDaysDetail.length)
                            ? forecast.weekDaysDetail[index].isPastOrToday
                            : false;
                        return FlDotCirclePainter(
                          radius: 4,
                          color: Colors.white,
                          strokeWidth: 2.5,
                          strokeColor: isPast ? const Color(0xFF10B981) : const Color(0xFF4F46E5),
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF4F46E5).withValues(alpha: 0.25),
                          const Color(0xFF4F46E5).withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // 4. Danh sách chi tiết từng ngày trong tuần
        const Text(
          'Chi Tiết Từng Ngày Trong Tuần',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 10),
        _buildDailyList(forecast),
      ],
    );
  }

  // Thẻ So Sánh Tuần (Tuần Trước vs Tuần Này)
  Widget _buildWeekComparisonCard(ForecastModel forecast) {
    final diffPct = forecast.weekDiffPercent;
    final isIncrease = diffPct > 0;
    final isDecrease = diffPct < 0;

    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    if (isIncrease) {
      badgeColor = diffPct > 20 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
      badgeText = '+$diffPct% so với tuần trước';
      badgeIcon = Icons.trending_up;
    } else if (isDecrease) {
      badgeColor = const Color(0xFF10B981);
      badgeText = 'Tiết kiệm ${diffPct.abs()}%';
      badgeIcon = Icons.trending_down;
    } else {
      badgeColor = const Color(0xFF4F46E5);
      badgeText = 'Ổn định';
      badgeIcon = Icons.trending_flat;
    }

    final lastWeekSub = forecast.lastWeekLabel.isNotEmpty ? forecast.lastWeekLabel : '';
    final thisWeekSub = forecast.thisWeekLabel.isNotEmpty ? forecast.thisWeekLabel : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Cột Tuần trước
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tuần trước', style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600)),
                    if (lastWeekSub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(lastWeekSub, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      currencyFormat.format(forecast.last7DaysTotal),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF334155)),
                    ),
                  ],
                ),
              ),

              // Mũi tên & Huy hiệu so sánh ở giữa
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 14, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(
                      badgeText,
                      style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Cột Tuần này
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Tuần này', style: TextStyle(color: Color(0xFF4F46E5), fontSize: 12, fontWeight: FontWeight.w600)),
                    if (thisWeekSub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(thisWeekSub, style: const TextStyle(color: Color(0xFF818CF8), fontSize: 10.5)),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      currencyFormat.format(forecast.totalForecast),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF4F46E5)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 1, color: Color(0xFFF1F5F9)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Mức chi trung bình / ngày:', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              Text(
                '~ ${currencyFormat.format(forecast.averageDailyForecast)} / ngày',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Danh sách chi tiết từng ngày trong tuần
  Widget _buildDailyList(ForecastModel forecast) {
    if (forecast.weekDaysDetail.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          children: List.generate(forecast.weekDaysDetail.length, (i) {
            final day = forecast.weekDaysDetail[i];
            final isPastOrToday = day.isPastOrToday;
            final isWeekend = day.dayName == 'T7' || day.dayName == 'CN';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: i < forecast.weekDaysDetail.length - 1
                    ? const Border(bottom: BorderSide(color: Color(0xFFF8FAFC), width: 1.5))
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isPastOrToday
                          ? const Color(0xFFECFDF5)
                          : (isWeekend ? const Color(0xFFFEF3C7) : const Color(0xFFEEF2FF)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      day.dayName,
                      style: TextStyle(
                        color: isPastOrToday
                            ? const Color(0xFF059669)
                            : (isWeekend ? const Color(0xFFD97706) : const Color(0xFF4F46E5)),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          day.date,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isWeekend ? FontWeight.bold : FontWeight.w500,
                            color: const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isPastOrToday ? 'Đã chi thực tế' : 'Dự kiến AI',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: isPastOrToday ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    currencyFormat.format(day.amount),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isPastOrToday
                          ? const Color(0xFF0F172A)
                          : (isWeekend ? const Color(0xFFD97706) : const Color(0xFF4F46E5)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: List.generate(forecast.predictedNext7Days.length, (i) {
          final amt = forecast.predictedNext7Days[i];
          final date = DateTime.now().add(Duration(days: i + 1));
          final dateStr = DateFormat('EEEE, dd/MM', 'vi_VN').format(date);
          final isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: i < forecast.predictedNext7Days.length - 1
                  ? const Border(bottom: BorderSide(color: Color(0xFFF8FAFC), width: 1.5))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isWeekend ? const Color(0xFFFEF3C7) : const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Ngày ${i + 1}',
                    style: TextStyle(
                      color: isWeekend ? const Color(0xFFD97706) : const Color(0xFF4F46E5),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isWeekend ? FontWeight.bold : FontWeight.normal,
                      color: const Color(0xFF334155),
                    ),
                  ),
                ),
                Text(
                  currencyFormat.format(amt),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isWeekend ? const Color(0xFFD97706) : const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ==========================================
  // VIEW 2: DỰ BÁO THEO THÁNG (THÁNG NÀY VS THÁNG TRƯỚC)
  // ==========================================
  Widget _buildMonthView(ForecastModel forecast) {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysPassed = now.day;
    final progress = (daysPassed / daysInMonth).clamp(0.0, 1.0);

    final monthDiff = forecast.monthDiffPercent;
    final isIncrease = monthDiff > 0;
    final isDecrease = monthDiff < 0;

    Color badgeColor;
    String badgeText;
    if (isIncrease) {
      badgeColor = monthDiff > 15 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
      badgeText = 'Dự kiến tăng +$monthDiff% so với tháng trước';
    } else if (isDecrease) {
      badgeColor = const Color(0xFF10B981);
      badgeText = 'Dự kiến tiết kiệm ${monthDiff.abs()}% so với tháng trước';
    } else {
      badgeColor = const Color(0xFF4F46E5);
      badgeText = 'Dự kiến ngang bằng tháng trước';
    }

    final remainingProjected = (forecast.thisMonthProjected - forecast.thisMonthSpent).clamp(0.0, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Thẻ So Sánh Tháng
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tháng ${now.month}/${now.year}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(badgeText, style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // So sánh 3 cột: Tháng trước vs Đã chi tháng này vs Dự kiến cả tháng
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Tháng trước', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              currencyFormat.format(forecast.lastMonthTotal),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Đã chi đến nay', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              currencyFormat.format(forecast.thisMonthSpent),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF10B981)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Dự kiến cả tháng', style: TextStyle(color: Color(0xFF4F46E5), fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              currencyFormat.format(forecast.thisMonthProjected),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF4F46E5)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Thanh tiến độ thời gian & ngân sách
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tiến độ tháng: Ngày $daysPassed / $daysInMonth', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  Text('${(progress * 100).toInt()}% thời gian', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
                  minHeight: 8,
                ),
              ),

              const SizedBox(height: 14),

              // Dự kiến các ngày còn lại
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dự kiến chi trong các ngày còn lại:', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                    Text(
                      currencyFormat.format(remainingProjected),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 2. Thẻ Lời Khuyên Tài Chính Cho Tháng
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.lightbulb_outline_rounded, color: Color(0xFFF59E0B), size: 20),
                  SizedBox(width: 8),
                  Text('Gợi ý quản lý chi tiêu tháng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                monthDiff <= 0
                    ? 'Tuyệt vời! Theo tốc độ hiện tại, chi tiêu tháng này của bạn dự kiến sẽ tiết kiệm hơn hoặc bằng tháng trước. Hãy duy trì thói quen chi tiêu kỷ luật này đến cuối tháng.'
                    : 'Lưu ý: Tốc độ chi tiêu hiện tại đang dự phóng cao hơn tháng trước $monthDiff%. Hãy rà soát lại các khoản chi không thiết yếu (mua sắm, giải trí) để giữ ngân sách an toàn.',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.45),
              ),
            ],
          ),
        ),
      ],
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
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
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
        return 'CẦN THẮT CHẶT';
      case 'TRUNG_BINH':
        return 'CẦN LƯU Ý';
      case 'AN_TOAN':
      default:
        return 'AN TOÀN & ỔN ĐỊNH';
    }
  }
}
