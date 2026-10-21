import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'api_service.dart';

/// Dịch vụ tự động bắt thông báo biến động số dư từ ShopeePay, MoMo, VNPAY, Ngân hàng
class NotificationSyncService {
  static final NotificationSyncService _instance = NotificationSyncService._internal();
  factory NotificationSyncService() => _instance;
  NotificationSyncService._internal();

  StreamSubscription? _subscription;
  final Set<String> _processedNotificationHashes = {};
  
  // Thông báo tới UI khi vừa tự động bắt và lưu thành công một giao dịch
  final ValueNotifier<String?> lastCapturedMessage = ValueNotifier<String?>(null);
  final ValueNotifier<bool> isPermissionEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<int> dataRefreshTrigger = ValueNotifier<int>(0);

  // Danh sách package ứng dụng Ngân hàng & Ví điện tử phổ biến tại Việt Nam
  static const Set<String> _knownBankingPackages = {
    // VIB (Ngân hàng Quốc tế)
    'com.vib.myvib2',
    'com.vn.vib.mobileapp',
    'com.vib.corp',
    // Ví điện tử & TMĐT
    'com.shopee.vn',
    'com.airpay.consumer',
    'com.mservice.momopay',
    'vn.com.vng.zalopay',
    'com.bplus.vtpay',
    // Ngân hàng TMCP lớn
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
    'com.hdbank.mplus',
    'com.ocb.omni',
    'com.msb.smartbanking',
    'com.vnpay.msb',
    'com.shb.mobilebanking',
    'com.seabank.mb',
    'com.lpbank.mobilebanking',
    // Ngân hàng số thế hệ mới
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
            lower.contains('cộng tiền') ||
            lower.contains('cong tien') ||
            lower.contains('shopeepay') ||
            lower.contains('shopee') ||
            lower.contains('momo') ||
            lower.contains('zalopay') ||
            lower.contains('vietcombank') ||
            lower.contains('mbbank') ||
            lower.contains('techcombank') ||
            lower.contains('vib') ||
            lower.contains('myvib') ||
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

        // 5. Tự động gọi PhoBERT AI phân loại danh mục nếu là KHOẢN CHI
        // NGUYÊN TẮC: 2 mục lớn Thu Nhập và Chi Tiêu là ưu tiên cao nhất!
        // Nếu là Thu Nhập -> Bắt buộc giữ nguyên danh mục THU_NHAP, tuyệt đối không gọi PhoBERT gán vào Ăn uống/Mua sắm!
        String finalCategory = 'THU_NHAP';
        if (parsedTx['type'] == 'expense') {
          finalCategory = parsedTx['categoryCode'] ?? 'AN_UONG';
          try {
            final aiRes = await ApiService().classifyWithAi(parsedTx['note']);
            if (aiRes != null && aiRes['category_code'] != null && aiRes['category_code'] != 'THU_NHAP') {
              finalCategory = aiRes['category_code'];
            }
          } catch (_) {}
        } else {
          finalCategory = 'THU_NHAP';
        }

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
          dataRefreshTrigger.value++;
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
    } else if (packageName.contains('vib') || lower.contains('vib') || lower.contains('myvib')) {
      source = 'VIB (MyVIB)';
    } else if (packageName.contains('vnpay') || lower.contains('vnpay') || lower.contains('vn pay')) {
      source = 'Ví VNPAY';
    }

    // 1. Tách số tiền (Ưu tiên tìm số tiền đứng sau dấu + / - hoặc sau từ khóa biến động)
    double detectedAmount = 0;
    String? detectedTypeFromSign;

    // Loại bỏ phần số dư cuối (tránh nhận nhầm số dư tài khoản thành số tiền giao dịch)
    String textWithoutBalance = text;
    final balanceIndex = lower.indexOf('số dư:');
    final balanceIndex2 = lower.indexOf('so du:');
    final balanceIndex3 = lower.indexOf('số dư cuối');
    final balanceIndex4 = lower.indexOf('số dư khả dụng');
    final balanceIndex5 = lower.indexOf('so du kha dung');
    final balanceIndex6 = lower.indexOf('balance:');
    final balanceIndex7 = lower.indexOf('khả dụng:');
    final cutIndex = [balanceIndex, balanceIndex2, balanceIndex3, balanceIndex4, balanceIndex5, balanceIndex6, balanceIndex7]
        .where((i) => i >= 0)
        .fold<int>(-1, (min, i) => min == -1 || i < min ? i : min);
    if (cutIndex > 0) {
      textWithoutBalance = text.substring(0, cutIndex);
    }

    // Regex 0: Bắt số tiền viết tắt dạng k/K phổ thông tại VN (ví dụ: +250k, 250k, 50k, 100k, -50k)
    final kMatch = RegExp(r'([+-])?\s*([0-9]{1,4}(?:[.,][0-9]{1,3})?)\s*[kK]\b').firstMatch(textWithoutBalance);
    if (kMatch != null) {
      final signStr = kMatch.group(1);
      final numStr = kMatch.group(2)!.replaceAll(',', '.');
      final parsedK = double.tryParse(numStr);
      if (parsedK != null && parsedK > 0) {
        detectedAmount = parsedK * 1000;
        if (signStr == '+') detectedTypeFromSign = 'income';
        if (signStr == '-') detectedTypeFromSign = 'expense';
      }
    }

    // Regex 1: Số tiền có dấu + hoặc - rõ ràng (ví dụ: +250,000VND, -45.000đ)
    if (detectedAmount == 0) {
      final signedMatch = RegExp(r'([+-])\s*([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})\s*(?:vnd|vnđ|d|đ)?\b', caseSensitive: false)
          .firstMatch(textWithoutBalance);
      if (signedMatch != null) {
        final signStr = signedMatch.group(1);
        final rawNum = signedMatch.group(2)!.replaceAll(RegExp(r'[^0-9]'), '');
        detectedAmount = double.tryParse(rawNum) ?? 0;
        if (signStr == '+') detectedTypeFromSign = 'income';
        if (signStr == '-') detectedTypeFromSign = 'expense';
      }
    }

    // Regex 2: Số tiền sau các từ khóa "thanh toán", "nhận", "cộng", "nạp", "số tiền", "gd"
    if (detectedAmount == 0) {
      final keywordMatch = RegExp(r'(?:thanh toán|chuyển|nhận|cộng|nạp|trừ|gd|số tiền|so tien|gia)[:\s]+(?:thành công\s+)?([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})\s*(?:vnd|vnđ|d|đ)?\b', caseSensitive: false)
          .firstMatch(textWithoutBalance);
      if (keywordMatch != null) {
        final rawNum = keywordMatch.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
        detectedAmount = double.tryParse(rawNum) ?? 0;
      }
    }

    // Regex 3: Tìm bất kỳ số tiền nào có định dạng tiền tệ (từ 1.000đ trở lên)
    if (detectedAmount == 0) {
      final anyMatch = RegExp(r'\b([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})\s*(?:vnd|vnđ|d|đ)\b', caseSensitive: false)
          .firstMatch(textWithoutBalance);
      if (anyMatch != null) {
        final rawNum = anyMatch.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
        detectedAmount = double.tryParse(rawNum) ?? 0;
      }
    }

    if (detectedAmount < 1000) {
      return null; // Không trích xuất được số tiền hợp lệ
    }

    // 2. Phân loại 2 Mục Lớn: Thu Nhập vs Chi Tiêu (Ưu tiên tuyệt đối)
    String type = 'expense';
    if (detectedTypeFromSign != null) {
      type = detectedTypeFromSign;
    } else {
      final hasIncomeKeywords = lower.contains('+') ||
          lower.contains('cong') || lower.contains('cộng') ||
          lower.contains('duoc cong') || lower.contains('được cộng') ||
          lower.contains('nhan') || lower.contains('nhận') ||
          lower.contains('da nhan') || lower.contains('đã nhận') ||
          lower.contains('nap') || lower.contains('nạp') ||
          lower.contains('tien vao') || lower.contains('tiền vào') ||
          lower.contains('tien ve') || lower.contains('tiền về') ||
          lower.contains('chuyen den') || lower.contains('chuyển đến') ||
          lower.contains('hoan') || lower.contains('hoàn') || lower.contains('refund') ||
          lower.contains('tang') || lower.contains('tăng') ||
          lower.contains('credit') || lower.contains('cr:');

      final hasExpenseKeywords = lower.contains('-') ||
          lower.contains('tru') || lower.contains('trừ') ||
          lower.contains('bi tru') || lower.contains('bị trừ') ||
          lower.contains('thanh toan') || lower.contains('thanh toán') ||
          lower.contains('rut tien') || lower.contains('rút tiền') ||
          lower.contains('chuyen di') || lower.contains('chuyển đi') ||
          lower.contains('giam') || lower.contains('giảm') ||
          lower.contains('debit') || lower.contains('dr:');

      if (hasIncomeKeywords && !hasExpenseKeywords) {
        type = 'income';
      } else if (hasIncomeKeywords && hasExpenseKeywords) {
        // Nếu có cả 2 (ví dụ: "Nhận tiền từ chuyển khoản"), ưu tiên các từ thể hiện tiền vào
        if (lower.contains('cộng') || lower.contains('cong') || lower.contains('nhận') || lower.contains('nhan') || lower.contains('nạp') || lower.contains('nap')) {
          type = 'income';
        } else {
          type = 'expense';
        }
      } else {
        type = 'expense';
      }
    }

    // 3. Trích xuất nội dung / ghi chú
    String note = '';
    final refMatch = RegExp(r'(?:nd|ref|lời nhắn|nội dung|noi dung|cho|tại|tai)[:\s]+([^.\n]+)', caseSensitive: false).firstMatch(text);
    if (refMatch != null) {
      note = '$source: ${refMatch.group(1)!.trim()}';
    } else {
      note = '$source: ${type == 'income' ? 'Nhận tiền' : 'Thanh toán'}';
    }

    if (note.length > 60) {
      note = note.substring(0, 60);
    }

    // 4. Gán danh mục chuẩn theo 2 mục lớn
    final categoryCode = type == 'income' ? 'THU_NHAP' : 'AN_UONG';

    return {
      'amount': detectedAmount,
      'type': type,
      'note': note,
      'categoryCode': categoryCode,
      'source': source,
    };
  }
}
