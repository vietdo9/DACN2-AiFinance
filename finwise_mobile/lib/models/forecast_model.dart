class ForecastModel {
  final List<double> predictedNext7Days;
  final double totalForecast;
  final double averageDailyForecast;
  final String warningLevel; // 'AN_TOAN', 'TRUNG_BINH', 'CAO'
  final String message;
  final List<double>? historicalRecentDays;
  final bool hasEnoughData;
  final bool isDemoData;

  ForecastModel({
    required this.predictedNext7Days,
    required this.totalForecast,
    required this.averageDailyForecast,
    required this.warningLevel,
    required this.message,
    this.historicalRecentDays,
    this.hasEnoughData = true,
    this.isDemoData = false,
  });

  factory ForecastModel.empty({String? message}) {
    return ForecastModel(
      predictedNext7Days: [],
      totalForecast: 0.0,
      averageDailyForecast: 0.0,
      warningLevel: 'CHUA_CO_DU_LIEU',
      message: message ?? 'Chưa có đủ dữ liệu giao dịch để AI học thói quen chi tiêu của bạn.',
      historicalRecentDays: [],
      hasEnoughData: false,
      isDemoData: false,
    );
  }

  factory ForecastModel.fromJson(Map<String, dynamic> json, {bool hasEnoughData = true, bool isDemoData = false}) {
    final list = (json['predicted_next_7_days'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        [];
    final hist = (json['historical_recent_days'] as List?)
        ?.map((e) => (e as num).toDouble())
        .toList();

    return ForecastModel(
      predictedNext7Days: list,
      totalForecast: (json['total_forecast'] as num?)?.toDouble() ?? 0.0,
      averageDailyForecast: (json['average_daily_forecast'] as num?)?.toDouble() ?? 0.0,
      warningLevel: json['warning_level'] ?? 'AN_TOAN',
      message: json['message'] ?? 'Dòng tiền dự kiến ổn định.',
      historicalRecentDays: hist,
      hasEnoughData: hasEnoughData,
      isDemoData: isDemoData,
    );
  }
}
