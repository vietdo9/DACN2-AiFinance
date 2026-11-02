class WeekDayForecast {
  final String date;
  final String dayName;
  final String dayLabel;
  final bool isPastOrToday;
  final double amount;
  final bool isPredicted;

  WeekDayForecast({
    required this.date,
    required this.dayName,
    required this.dayLabel,
    required this.isPastOrToday,
    required this.amount,
    required this.isPredicted,
  });

  factory WeekDayForecast.fromJson(Map<String, dynamic> json) {
    return WeekDayForecast(
      date: json['date'] ?? '',
      dayName: json['day_name'] ?? '',
      dayLabel: json['day_label'] ?? '',
      isPastOrToday: json['is_past_or_today'] == true,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      isPredicted: json['is_predicted'] == true,
    );
  }
}

class ForecastModel {
  final List<double> predictedNext7Days;
  final List<WeekDayForecast> weekDaysDetail;
  final double totalForecast;
  final double averageDailyForecast;
  final String warningLevel; // 'AN_TOAN', 'TRUNG_BINH', 'CAO'
  final String message;
  final List<double> historicalRecentDays;
  final bool hasEnoughData;
  final bool isDemoData;

  // So sánh theo Tuần
  final double last7DaysTotal;
  final double weekDiffAmount;
  final int weekDiffPercent;
  final String thisWeekLabel;
  final String lastWeekLabel;

  // So sánh theo Tháng
  final double thisMonthSpent;
  final double thisMonthProjected;
  final double lastMonthTotal;
  final int monthDiffPercent;
  final String thisMonthLabel;
  final String lastMonthLabel;

  ForecastModel({
    required this.predictedNext7Days,
    List<WeekDayForecast>? weekDaysDetail,
    required this.totalForecast,
    required this.averageDailyForecast,
    required this.warningLevel,
    required this.message,
    List<double>? historicalRecentDays,
    this.hasEnoughData = true,
    this.isDemoData = false,
    this.last7DaysTotal = 0.0,
    this.weekDiffAmount = 0.0,
    this.weekDiffPercent = 0,
    this.thisWeekLabel = 'Tuần này',
    this.lastWeekLabel = 'Tuần trước',
    this.thisMonthSpent = 0.0,
    this.thisMonthProjected = 0.0,
    this.lastMonthTotal = 0.0,
    this.monthDiffPercent = 0,
    this.thisMonthLabel = 'Tháng này',
    this.lastMonthLabel = 'Tháng trước',
  })  : historicalRecentDays = historicalRecentDays ?? [],
        weekDaysDetail = weekDaysDetail ?? [];

  factory ForecastModel.empty({String? message}) {
    return ForecastModel(
      predictedNext7Days: [],
      weekDaysDetail: [],
      totalForecast: 0.0,
      averageDailyForecast: 0.0,
      warningLevel: 'CHUA_CO_DU_LIEU',
      message: message ?? 'Chưa có đủ dữ liệu giao dịch để AI học thói quen chi tiêu của bạn.',
      historicalRecentDays: [],
      hasEnoughData: false,
      isDemoData: false,
      last7DaysTotal: 0.0,
      weekDiffAmount: 0.0,
      weekDiffPercent: 0,
      thisWeekLabel: 'Tuần này',
      lastWeekLabel: 'Tuần trước',
      thisMonthSpent: 0.0,
      thisMonthProjected: 0.0,
      lastMonthTotal: 0.0,
      monthDiffPercent: 0,
      thisMonthLabel: 'Tháng này',
      lastMonthLabel: 'Tháng trước',
    );
  }

  factory ForecastModel.fromJson(Map<String, dynamic> json, {bool hasEnoughData = true, bool isDemoData = false}) {
    final list = (json['predicted_next_7_days'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [];
    final hist = (json['historical_recent_days'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [];
    final weekDetail = (json['week_days_detail'] as List?)
            ?.map((e) => WeekDayForecast.fromJson(e))
            .toList() ??
        [];

    final totalForecast = (json['total_forecast'] as num?)?.toDouble() ?? 0.0;
    final last7DaysTotal = (json['last_7_days_total'] as num?)?.toDouble() ??
        hist.fold<double>(0.0, (sum, val) => sum + val);

    final weekDiffAmount = (json['week_diff_amount'] as num?)?.toDouble() ??
        (totalForecast - last7DaysTotal);

    final weekDiffPercent = (json['week_diff_percent'] as num?)?.toInt() ??
        (last7DaysTotal > 0 ? ((weekDiffAmount / last7DaysTotal) * 100).round() : 0);

    return ForecastModel(
      predictedNext7Days: list,
      weekDaysDetail: weekDetail,
      totalForecast: totalForecast,
      averageDailyForecast: (json['average_daily_forecast'] as num?)?.toDouble() ?? 0.0,
      warningLevel: json['warning_level'] ?? 'AN_TOAN',
      message: json['message'] ?? 'Dòng tiền dự kiến ổn định.',
      historicalRecentDays: hist,
      hasEnoughData: hasEnoughData,
      isDemoData: isDemoData,
      last7DaysTotal: last7DaysTotal,
      weekDiffAmount: weekDiffAmount,
      weekDiffPercent: weekDiffPercent,
      thisWeekLabel: json['this_week_label'] ?? 'Tuần này',
      lastWeekLabel: json['last_week_label'] ?? 'Tuần trước',
      thisMonthSpent: (json['this_month_spent'] as num?)?.toDouble() ?? 0.0,
      thisMonthProjected: (json['this_month_projected'] as num?)?.toDouble() ?? 0.0,
      lastMonthTotal: (json['last_month_total'] as num?)?.toDouble() ?? 0.0,
      monthDiffPercent: (json['month_diff_percent'] as num?)?.toInt() ?? 0,
      thisMonthLabel: json['this_month_label'] ?? 'Tháng này',
      lastMonthLabel: json['last_month_label'] ?? 'Tháng trước',
    );
  }
}
