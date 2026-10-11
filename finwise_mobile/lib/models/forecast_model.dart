class ForecastModel {
  final List<double> predictedNext7Days;
  final double totalForecast;
  final double averageDailyForecast;
  final String warningLevel; // 'AN_TOAN', 'TRUNG_BINH', 'CAO'
  final String message;
  final List<double>? historicalRecentDays;

  ForecastModel({
    required this.predictedNext7Days,
    required this.totalForecast,
    required this.averageDailyForecast,
    required this.warningLevel,
    required this.message,
    this.historicalRecentDays,
  });

  factory ForecastModel.fromJson(Map<String, dynamic> json) {
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
    );
  }
}
