import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/category_model.dart';
import '../models/transaction_model.dart';
import '../models/forecast_model.dart';
import '../models/user_model.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _customBaseUrl;
  String? _authToken;
  UserModel? _currentUser;

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null && _authToken != null;
  String? get currentToken => _authToken;

  // Lấy Base URL của Backend Node.js
  String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.trim().isNotEmpty) {
      return _customBaseUrl!.trim();
    }
    if (kIsWeb) return 'http://localhost:5000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    }
    return 'http://localhost:5000';
  }

  void setCustomBaseUrl(String url) async {
    _customBaseUrl = url.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('finwise_base_url', _customBaseUrl!);
    } catch (_) {}
  }

  void setToken(String token) {
    _authToken = token;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  /// Khởi tạo và khôi phục phiên đăng nhập đã lưu
  Future<bool> checkSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _customBaseUrl = prefs.getString('finwise_base_url');
      final token = prefs.getString('finwise_token');
      final userJson = prefs.getString('finwise_user');

      if (token != null && userJson != null) {
        _authToken = token;
        _currentUser = UserModel.fromJson(jsonDecode(userJson), token: token);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// 1. Đăng ký tài khoản mới
  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'full_name': fullName.trim(),
              'email': email.trim().toLowerCase(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 6));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (data['success'] == true && data['data'] != null) {
          final userData = data['data']['user'];
          final token = data['data']['token']?.toString() ?? 'token_${DateTime.now().millisecondsSinceEpoch}';

          _authToken = token;
          _currentUser = UserModel.fromJson(userData, token: token);

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('finwise_token', token);
          await prefs.setString('finwise_user', jsonEncode(_currentUser!.toJson()));

          return {'success': true, 'message': data['message'] ?? 'Đăng ký tài khoản thành công!'};
        }
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Đăng ký không thành công. Vui lòng thử lại.'
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Không thể kết nối tới máy chủ ($baseUrl). Vui lòng đảm bảo Backend đang chạy.'
      };
    }
  }

  /// 2. Đăng nhập
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim().toLowerCase(), 'password': password}),
          )
          .timeout(const Duration(seconds: 6));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final userData = data['data']?['user'] ?? {};
        final token = data['data']?['token']?.toString() ?? 'demo_token';

        _authToken = token;
        _currentUser = UserModel.fromJson(userData, token: token);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('finwise_token', token);
        await prefs.setString('finwise_user', jsonEncode(_currentUser!.toJson()));

        return {'success': true, 'message': 'Đăng nhập thành công!'};
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Email hoặc mật khẩu không chính xác.'
      };
    } catch (e) {
      if (email.trim().toLowerCase() == 'demo@finwise.vn' && password == '123456') {
        _authToken = 'demo_token';
        _currentUser = UserModel(
          id: '00000000-0000-0000-0000-000000000001',
          email: 'demo@finwise.vn',
          fullName: 'Người Dùng Demo',
          token: 'demo_token',
        );
        return {'success': true, 'message': 'Đăng nhập tài khoản Demo thành công!'};
      }

      return {
        'success': false,
        'message': 'Không thể kết nối máy chủ ($baseUrl).'
      };
    }
  }

  /// 3. Đăng xuất
  Future<void> logout() async {
    _authToken = null;
    _currentUser = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('finwise_token');
      await prefs.remove('finwise_user');
    } catch (_) {}
  }

  /// 4. Lấy dữ liệu Thống kê Tổng quan (Độc lập theo từng tài khoản)
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

    // Giá trị ban đầu sạch sẽ cho tài khoản mới (không dùng số liệu giả)
    return {
      'total_balance': 0.0,
      'this_month_income': 0.0,
      'this_month_expense': 0.0,
      'expense_by_category': []
    };
  }

  /// 5. Lấy danh mục chuẩn
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

  /// 6. Lấy lịch sử giao dịch (Độc lập của tài khoản đang đăng nhập)
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

    return [];
  }

  /// 7. Gọi PhoBERT AI để tự phân loại từ câu ghi chú
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

  /// 8. Tạo giao dịch mới
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
          ...? (categoryCode != null ? {'category_code': categoryCode} : null),
        }),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// 8.1 Cập nhật / Đổi danh mục giao dịch đã lưu
  Future<bool> updateTransaction({
    required String id,
    double? amount,
    String? note,
    String? type,
    String? categoryCode,
    String? transactionDate,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/transactions/$id'),
        headers: _headers,
        body: jsonEncode({
          ...? (amount != null ? {'amount': amount} : null),
          ...? (note != null ? {'note': note} : null),
          ...? (type != null ? {'type': type} : null),
          ...? (categoryCode != null ? {'category_code': categoryCode} : null),
          ...? (transactionDate != null ? {'transaction_date': transactionDate} : null),
        }),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 8.2 Xóa giao dịch
  Future<bool> deleteTransaction(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/transactions/$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }


  /// 9. Lấy Dự báo 7 ngày từ mạng LSTM AI (Độc lập theo dữ liệu thật của tài khoản)
  Future<ForecastModel> getAiForecast({bool isDemo = false}) async {
    try {
      final url = '$baseUrl/api/ai/user-forecast${isDemo ? '?demo=true' : ''}';
      final response = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        if (res['has_enough_data'] == false) {
          return ForecastModel.empty(message: res['message']);
        }
        return ForecastModel.fromJson(
          res['data'] ?? {},
          hasEnoughData: true,
          isDemoData: res['is_demo_data'] ?? isDemo,
        );
      }
    } catch (_) {}

    return ForecastModel.empty();
  }

  /// 10. Quét ảnh hóa đơn / Bill thanh toán bằng AI (EasyOCR + PhoBERT)
  Future<Map<String, dynamic>?> scanBill({
    required List<int> imageBytes,
    required String filename,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/transactions/scan-bill');
      final request = http.MultipartRequest('POST', uri);

      if (_authToken != null) {
        request.headers['Authorization'] = 'Bearer $_authToken';
      }

      final multipartFile = http.MultipartFile.fromBytes(
        'bill',
        imageBytes,
        filename: filename,
      );
      request.files.add(multipartFile);

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final res = jsonDecode(utf8.decode(response.bodyBytes));
        if (res['success'] == true && res['data'] != null) {
          return res['data'];
        }
      } else {
        final errJson = jsonDecode(utf8.decode(response.bodyBytes));
        debugPrint('[!] scanBill error: ${errJson['message']}');
      }
    } catch (e) {
      debugPrint('[!] Lỗi gọi API scanBill: $e');
    }
    return null;
  }
}

