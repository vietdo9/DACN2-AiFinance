import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'api_service.dart';

/// Dịch vụ tự động bắt thông báo biến động số dư từ ShopeePay, MoMo, Ngân hàng
class NotificationSyncService {
  static final NotificationSyncService _instance = NotificationSyncService._internal();
  factory NotificationSyncService() => _instance;
  NotificationSyncService._internal();

  StreamSubscription? _subscription;
  final Set<String> _processedNotificationHashes = {};
  
  // Thông báo tới UI khi vừa tự động bắt và lưu thành công một giao dịch
  final ValueNotifier<String?> lastCapturedMessage = ValueNotifier<String?>(null);
  final ValueNotifier<bool> isPermissionEnabled = ValueNotifier<bool>(false);

  // Danh sách package ứng dụng Ngân hàng & Ví điện tử phổ biến tại Việt Nam
  static const Set<String> _knownBankingPackages = {
    'com.shopee.vn',
    'com.airpay.consumer',
    'com.mservice.momopay',
    'vn.com.vng.zalopay',
    'com.bplus.vtpay',
    'com.VCB',
    'com.mbmobile',
    'com.techcombank.mobile',
    'com.techcombank.retail.mb',
    'vn.com.techcombank.bb.app',
    'com.vietinbank.ipay',
    'com.vnpay.bidv',
    'com.tpb.mb.gprsandroid',
    'com.vnpay.vpbankonline',
    'com.vpbank.neo',
    'mobile.acb.com.vn',
    'com.sacombank.mplus',
    'com.vnpay.agribank',
    'vn.timo',
    'vn.be.cake',
    'vnpay.smartacccount',
    'com.vnpay',
  };

  /// Kiểm tra xem người dùng đã cấp quyền Notification Access chưa
  Future<bool> checkPermission() async {
    try {
      final granted = await NotificationListenerService.isPermissionGranted();
      isPermissionEnabled.value = granted;
      return granted;
    } catch (e) {
      debugPrint('[NotificationSyncService] Lỗi kiểm tra quyền: $e');
      return false;
    }
  }

  /// Mở màn hình cài đặt Android để người dùng bật quyền Đọc thông báo cho FinWise
  Future<bool> requestPermission() async {
    try {
      final result = await NotificationListenerService.requestPermission();
      await checkPermission();
      return result;
    } catch (e) {
      debugPrint('[NotificationSyncService] Lỗi yêu cầu quyền: $e');
      return false;
    }
  }

  /// Bắt đầu lắng nghe thông báo hệ thống theo thời gian thực
  void startListening({VoidCallback? onNewTransaction}) {
    if (_subscription != null) return; // Đang chạy

    debugPrint('[NotificationSyncService] Khởi động luồng lắng nghe thông báo...');

    _subscription = NotificationListenerService.notificationsStream.listen((event) async {
      try {
        // Bỏ qua sự kiện xóa thông báo (dismiss)
        if (event.hasRemoved == true) return;

        final packageName = event.packageName.toLowerCase();
        final title = event.title.trim();
        final content = event.content.trim();

        if (title.isEmpty && content.isEmpty) return;

        final combinedText = '$title $content';
        final lower = combinedText.toLowerCase();

        // 1. Kiểm tra xem có phải thông báo ngân hàng / ví điện tử không
        final isKnownPackage = _knownBankingPackages.any((pkg) => packageName.contains(pkg.toLowerCase()));
        final hasFinancialKeywords = lower.contains('số dư') ||
            lower.contains('so du') ||
            lower.contains('biến động') ||
            lower.contains('thanh toán') ||
            lower.contains('giao dịch') ||
            lower.contains('chuyển tiền') ||
            lower.contains('nạp tiền') ||
            lower.contains('nhận tiền') ||
            lower.contains('shopeepay') ||
            lower.contains('shopee') ||
            lower.contains('momo') ||
            lower.contains('zalopay') ||
            lower.contains('vietcombank') ||
            lower.contains('mbbank') ||
            lower.contains('techcombank') ||
            lower.contains('vnpay') ||
            lower.contains('vn pay');

        if (!isKnownPackage && !hasFinancialKeywords) {
          return; // Không phải thông báo tài chính
        }

        // 2. Chống lặp (Deduplication) - Tránh bắt 2 lần cùng một thông báo trong vòng 3 phút
        final timeKey = DateTime.now().millisecondsSinceEpoch ~/ (1000 * 180);
        final notifHash = '$packageName|$title|$content|$timeKey';
        if (_processedNotificationHashes.contains(notifHash)) {
          return;
        }
        _processedNotificationHashes.add(notifHash);

        debugPrint('[NotificationSyncService] 🔔 Phát hiện thông báo biến động: [$title] - $content');

        // 3. Bóc tách thông tin giao dịch
        final parsedTx = _parseNotification(combinedText, packageName);
        if (parsedTx == null) {
          debugPrint('[NotificationSyncService] Không thể bóc tách số tiền từ thông báo.');
          return;
        }

        // 4. Nếu chưa đăng nhập thì không thể lưu
        if (!ApiService().isLoggedIn) {
          debugPrint('[NotificationSyncService] Bỏ qua vì chưa đăng nhập FinWise.');
          return;
        }

        // 5. Tự động gọi PhoBERT AI phân loại danh mục nếu có ghi chú
        String finalCategory = parsedTx['categoryCode'] ?? 'AN_UONG';
        try {
          final aiRes = await ApiService().classifyWithAi(parsedTx['note']);
          if (aiRes != null && aiRes['category_code'] != null) {
            finalCategory = aiRes['category_code'];
          }
        } catch (_) {}

        // 6. Tự động lưu giao dịch vào FinWise qua API
        final success = await ApiService().createTransaction(
          amount: parsedTx['amount'],
          note: parsedTx['note'],
          type: parsedTx['type'],
          categoryCode: finalCategory,
        );

        if (success) {
          final amtStr = NumberFormat('#,###', 'vi_VN').format(parsedTx['amount']);
          final sign = parsedTx['type'] == 'income' ? '+' : '-';
          final msg = '⚡ Tự động ghi nhận: $sign$amtStrđ (${parsedTx['source']})';
          
          debugPrint('[NotificationSyncService] ✅ ĐÃ LƯU THÀNH CÔNG: $msg');
          lastCapturedMessage.value = msg;
          onNewTransaction?.call();
        }
      } catch (e, stack) {
        debugPrint('[NotificationSyncService] Lỗi xử lý thông báo: $e\n$stack');
      }
    });
  }

  /// Ngừng lắng nghe
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Thuật toán bóc tách thông báo ngân hàng / ShopeePay / MoMo
  Map<String, dynamic>? _parseNotification(String text, String packageName) {
    final lower = text.toLowerCase();

    // Xác định tên nguồn
    String source = 'Ngân hàng';
    if (packageName.contains('shopee') || lower.contains('shopee') || lower.contains('airpay')) {
      source = 'ShopeePay';
    } else if (packageName.contains('momo') || lower.contains('momo')) {
      source = 'Ví MoMo';
    } else if (packageName.contains('zalopay') || lower.contains('zalopay')) {
      source = 'ZaloPay';
    } else if (packageName.contains('vcb') || lower.contains('vietcombank')) {
      source = 'Vietcombank';
    } else if (packageName.contains('mb') || lower.contains('mbbank')) {
      source = 'MB Bank';
    } else if (packageName.contains('techcombank')) {
      source = 'Techcombank';
    } else if (packageName.contains('vnpay') || lower.contains('vnpay') || lower.contains('vn pay')) {
      source = 'Ví VNPAY';
    }

    // 1. Phân loại Thu / Chi
    String type = 'expense';
    if (text.contains('+') ||
        lower.contains('cong') ||
        lower.contains('cộng') ||
        lower.contains('nhận được') ||
        lower.contains('nhan duoc') ||
        lower.contains('nạp thành công') ||
        lower.contains('nap thanh cong') ||
        lower.contains('nạp tiền vào') ||
        lower.contains('hoàn tiền') ||
        lower.contains('credit')) {
      type = 'income';
    }

    // 2. Tách số tiền (Ưu tiên tìm số tiền đứng sau dấu + / - hoặc sau từ khóa biến động)
    double detectedAmount = 0;

    // Loại bỏ phần số dư cuối (tránh nhận nhầm số dư tài khoản thành số tiền giao dịch)
    String textWithoutBalance = text;
    final balanceIndex = lower.indexOf('số dư:');
    final balanceIndex2 = lower.indexOf('so du:');
    final balanceIndex3 = lower.indexOf('số dư cuối:');
    final balanceIndex4 = lower.indexOf('balance:');
    final cutIndex = [balanceIndex, balanceIndex2, balanceIndex3, balanceIndex4].where((i) => i >= 0).fold<int>(-1, (min, i) => min == -1 || i < min ? i : min);
    if (cutIndex > 0) {
      textWithoutBalance = text.substring(0, cutIndex);
    }

    // Regex 1: Số tiền có dấu + hoặc - rõ ràng (ví dụ: +50,000VND, -45.000đ)
    final signedMatch = RegExp(r'(?:[+-])\s*([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})\s*(?:vnd|vnđ|d|đ)?\b', caseSensitive: false)
        .firstMatch(textWithoutBalance);
    
    if (signedMatch != null) {
      final rawNum = signedMatch.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
      detectedAmount = double.tryParse(rawNum) ?? 0;
    } else {
      // Regex 2: Số tiền sau các từ khóa "thanh toán", "nhận", "số tiền", "gd"
      final keywordMatch = RegExp(r'(?:thanh toán|chuyển|nhận|nạp|gd|số tiền|so tien|gia)[:\s]+(?:thành công\s+)?([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})\s*(?:vnd|vnđ|d|đ)?\b', caseSensitive: false)
          .firstMatch(textWithoutBalance);

      if (keywordMatch != null) {
        final rawNum = keywordMatch.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
        detectedAmount = double.tryParse(rawNum) ?? 0;
      } else {
        // Regex 3: Tìm bất kỳ số tiền nào có định dạng tiền tệ (từ 1.000đ trở lên)
        final anyMatch = RegExp(r'\b([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})\s*(?:vnd|vnđ|d|đ)\b', caseSensitive: false)
            .firstMatch(textWithoutBalance);
        if (anyMatch != null) {
          final rawNum = anyMatch.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
          detectedAmount = double.tryParse(rawNum) ?? 0;
        }
      }
    }

    if (detectedAmount < 1000) {
      return null; // Không trích xuất được số tiền hợp lệ
    }

    // 3. Trích xuất nội dung / ghi chú
    String note = '';
    final refMatch = RegExp(r'(?:nd|ref|lời nhắn|nội dung|noi dung|cho|tại|tai)[:\s]+([^.\n]+)', caseSensitive: false).firstMatch(text);
    if (refMatch != null) {
      note = '$source: ${refMatch.group(1)!.trim()}';
    } else {
      // Tóm tắt tiêu đề & nguồn
      note = '$source: ${type == 'income' ? 'Nhận tiền' : 'Thanh toán'}';
    }

    if (note.length > 60) {
      note = note.substring(0, 60);
    }

    // 4. Gợi ý Danh mục mặc định
    String categoryCode = type == 'income' ? 'THU_NHAP' : 'AN_UONG';
    if (source == 'ShopeePay' || source == 'Ví VNPAY') {
      categoryCode = type == 'income' ? 'THU_NHAP' : 'MUA_SAM';
    }

    return {
      'amount': detectedAmount,
      'type': type,
      'note': note,
      'categoryCode': categoryCode,
      'source': source,
    };
  }
}
