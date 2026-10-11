import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/category_model.dart';
import '../models/transaction_model.dart';
import '../models/forecast_model.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // URL Backend Node.js
  // Trên Windows / Web: http://localhost:5000
  // Trên Android Emulator: http://10.0.2.2:5000
  String get baseUrl {
    if (kIsWeb) return 'http://localhost:5000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    }
    return 'http://localhost:5000';
  }

  String? _authToken = 'demo_token';

  void setToken(String token) {
    _authToken = token;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  /// 1. Đăng nhập
  Future<bool> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _authToken = data['data']?['token'];
        return true;
      }
    } catch (_) {
      // Chế độ demo
      _authToken = 'demo_token';
      return true;
    }
    return false;
  }

  /// 2. Lấy dữ liệu Thống kê Tổng quan (Dashboard Summary)
  Future<Map<String, dynamic>> getSummary() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/analytics/summary'), headers: _headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        return res['data'] ?? {};
      }
    } catch (_) {}

    // Fallback dữ liệu mẫu đẹp mắt khi chưa mở backend
    return {
      'total_balance': 15850000.0,
      'this_month_income': 22000000.0,
      'this_month_expense': 6150000.0,
      'expense_by_category': [
        {'category_code': 'AN_UONG', 'category_name': 'Ăn uống & Cà phê', 'total': 2450000.0, 'percentage': 39.8, 'color': '#F59E0B'},
        {'category_code': 'DI_LAI', 'category_name': 'Di chuyển & Đi lại', 'total': 850000.0, 'percentage': 13.8, 'color': '#3B82F6'},
        {'category_code': 'HOA_DON', 'category_name': 'Hóa đơn & Tiện ích', 'total': 1200000.0, 'percentage': 19.5, 'color': '#8B5CF6'},
        {'category_code': 'GIAI_TRI', 'category_name': 'Giải trí & Sở thích', 'total': 750000.0, 'percentage': 12.2, 'color': '#6366F1'},
        {'category_code': 'MUA_SAM', 'category_name': 'Mua sắm & Đồ dùng', 'total': 900000.0, 'percentage': 14.6, 'color': '#EC4899'},
      ]
    };
  }

  /// 3. Lấy 10 danh mục chuẩn
  Future<List<CategoryModel>> getCategories() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/transactions/categories'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        final list = res['data'] as List? ?? [];
        return list.map((e) => CategoryModel.fromJson(e)).toList();
      }
    } catch (_) {}

    // Fallback 10 danh mục chuẩn
    return [
      CategoryModel(code: 'AN_UONG', name: 'Ăn uống & Cà phê', type: 'expense', icon: 'restaurant', color: const Color(0xFFF59E0B)),
      CategoryModel(code: 'DI_LAI', name: 'Di chuyển & Đi lại', type: 'expense', icon: 'directions_car', color: const Color(0xFF3B82F6)),
      CategoryModel(code: 'MUA_SAM', name: 'Mua sắm & Đồ dùng', type: 'expense', icon: 'shopping_bag', color: const Color(0xFFEC4899)),
      CategoryModel(code: 'HOA_DON', name: 'Hóa đơn & Tiện ích', type: 'expense', icon: 'receipt_long', color: const Color(0xFF8B5CF6)),
      CategoryModel(code: 'NHA_O', name: 'Nhà ở & Tiền trọ', type: 'expense', icon: 'home', color: const Color(0xFF10B981)),
      CategoryModel(code: 'GIAI_TRI', name: 'Giải trí & Sở thích', type: 'expense', icon: 'sports_esports', color: const Color(0xFF6366F1)),
      CategoryModel(code: 'SUC_KHOE', name: 'Sức khỏe & Y tế', type: 'expense', icon: 'medical_services', color: const Color(0xFFEF4444)),
      CategoryModel(code: 'HOC_TAP', name: 'Học tập & Phát triển', type: 'expense', icon: 'school', color: const Color(0xFF14B8A6)),
      CategoryModel(code: 'TIET_KIEM_DAU_TU', name: 'Tiết kiệm & Đầu tư', type: 'expense', icon: 'savings', color: const Color(0xFF06B6D4)),
      CategoryModel(code: 'THU_NHAP', name: 'Thu nhập & Lương', type: 'income', icon: 'payments', color: const Color(0xFF22C55E)),
    ];
  }

  /// 4. Lấy lịch sử giao dịch
  Future<List<TransactionModel>> getTransactions() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/transactions'), headers: _headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        final list = res['data'] as List? ?? [];
        return list.map((e) => TransactionModel.fromJson(e)).toList();
      }
    } catch (_) {}

    return [
      TransactionModel(
        id: '1',
        amount: 45000,
        type: 'expense',
        categoryCode: 'AN_UONG',
        categoryName: 'Ăn uống & Cà phê',
        note: 'Ăn bún bò huế sáng',
        transactionDate: DateTime.now(),
        aiPredicted: true,
        aiConfidence: 0.985,
      ),
      TransactionModel(
        id: '2',
        amount: 15000000,
        type: 'income',
        categoryCode: 'THU_NHAP',
        categoryName: 'Thu nhập & Lương',
        note: 'Nhận lương tháng',
        transactionDate: DateTime.now().subtract(const Duration(days: 1)),
        aiPredicted: false,
      ),
      TransactionModel(
        id: '3',
        amount: 120000,
        type: 'expense',
        categoryCode: 'DI_LAI',
        categoryName: 'Di chuyển & Đi lại',
        note: 'Đổ xăng xe máy + grab bike',
        transactionDate: DateTime.now().subtract(const Duration(days: 2)),
        aiPredicted: true,
        aiConfidence: 0.991,
      ),
    ];
  }

  /// 5. Gọi PhoBERT AI để tự phân loại từ câu ghi chú
  Future<Map<String, dynamic>?> classifyWithAi(String note) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/ai/classify'),
        headers: _headers,
        body: jsonEncode({'text': note}),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        return res['data'];
      }
    } catch (_) {}
    return null;
  }

  /// 6. Tạo giao dịch mới
  Future<bool> createTransaction({
    required double amount,
    required String note,
    required String type,
    String? categoryCode,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/transactions'),
        headers: _headers,
        body: jsonEncode({
          'amount': amount,
          'note': note,
          'type': type,
          if (categoryCode != null) 'category_code': categoryCode,
        }),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return true; // Mô phỏng thành công
    }
  }

  /// 7. Lấy Dự báo 7 ngày từ mạng LSTM AI
  Future<ForecastModel> getAiForecast() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/ai/user-forecast'), headers: _headers)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        return ForecastModel.fromJson(res['data'] ?? {});
      }
    } catch (_) {}

    // Fallback dự báo mẫu từ LSTM
    return ForecastModel(
      predictedNext7Days: [180000, 250000, 190000, 310000, 220000, 480000, 520000],
      totalForecast: 2150000,
      averageDailyForecast: 307143,
      warningLevel: 'AN_TOAN',
      message: 'Dòng tiền 7 ngày tới ở mức ổn định. Các khoản chi lớn tập trung vào cuối tuần.',
      historicalRecentDays: [150000, 200000, 180000, 220000, 210000, 450000, 490000],
    );
  }
}
