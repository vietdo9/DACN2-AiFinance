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
    // Ví điện tử & TMĐT (Chỉ theo dõi thanh toán đơn hàng thành công, chặn sạch voucher)
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
            lower.contains('mbvcb') ||
            lower.contains('vcb') ||
            lower.contains('mbbank') ||
            lower.contains('techcombank') ||
            lower.contains('vib') ||
            lower.contains('myvib') ||
            lower.contains('vnpay') ||
            lower.contains('vn pay');

        if (!isKnownPackage && !hasFinancialKeywords) {
          return; // Không phải thông báo tài chính
        }

        // 1.1 LỌC TUYỆT ĐỐI CÁC THÔNG BÁO VOUCHER / QUẢNG CÁO / KHUYẾN MÃI / QUÀ TẶNG
        // Ngân hàng và ví điện tử gửi rất nhiều tin tiếp thị (ví dụ: Tặng bạn voucher 50k, Nhận quà 100k...)
        // Những tin nhắn này KHÔNG PHẢI biến động số dư thực tế -> Bỏ qua ngay lập tức!
        final isMarketingOrVoucher = lower.contains('voucher') ||
            lower.contains('khuyến mãi') || lower.contains('khuyen mai') ||
            lower.contains('ưu đãi') || lower.contains('uu dai') ||
            lower.contains('mã giảm') || lower.contains('ma giam') ||
            lower.contains('phiếu giảm') || lower.contains('phieu giam') ||
            lower.contains('mã ưu đãi') || lower.contains('ma uu dai') ||
            lower.contains('nhập mã') || lower.contains('nhap ma') ||
            lower.contains('freeship') || lower.contains('miễn phí vận chuyển') ||
            lower.contains('tặng bạn') || lower.contains('tang ban') ||
            lower.contains('quà tặng') || lower.contains('qua tang') ||
            lower.contains('gói quà') || lower.contains('goi qua') ||
            lower.contains('tri ân') || lower.contains('săn sale') || lower.contains('san sale') ||
            lower.contains('flash sale') || lower.contains('hoàn xu') || lower.contains('hoan xu') ||
            lower.contains('xu shopee') || lower.contains('điểm thưởng') || lower.contains('diem thuong') ||
            lower.contains('chiết khấu') || lower.contains('chiet khau') ||
            lower.contains('vòng quay') || lower.contains('quay số') ||
            lower.contains('hết hạn') || lower.contains('het han') ||
            lower.contains('sắp hết hạn') || lower.contains('sap het han') ||
            lower.contains('đơn từ 0') || lower.contains('áp dụng cho đơn') ||
            lower.contains('nhận voucher') || lower.contains('nhan voucher') ||
            lower.contains('nhận ưu đãi') || lower.contains('nhan uu dai') ||
            lower.contains('chúc mừng bạn nhận') || lower.contains('chuc mung ban nhan');

        if (isMarketingOrVoucher) {
          debugPrint('[NotificationSyncService] 🛑 Bỏ qua tin quảng cáo/voucher: $title');
          return;
        }

        // 1.2 ĐIỀU KIỆN TIÊN QUYẾT: PHẢI CÓ TÍN HIỆU BIẾN ĐỘNG SỐ DƯ TÀI KHOẢN THỰC TẾ
        final hasBalanceKeyword = lower.contains('biến động số dư') ||
            lower.contains('bien dong so du') ||
            lower.contains('thay đổi số dư') ||
            lower.contains('thay doi so du') ||
            lower.contains('biến động tk') ||
            lower.contains('bien dong tk') ||
            lower.contains('số dư:') ||
            lower.contains('so du:') ||
            lower.contains('sd:') ||
            lower.contains('số dư cuối') ||
            lower.contains('so du cuoi') ||
            lower.contains('số dư khả dụng') ||
            lower.contains('so du kha dung') ||
            lower.contains('balance:') ||
            lower.contains('số dư tk') ||
            lower.contains('so du tk');

        final hasTransactionEvent = lower.contains('thanh toán thành công') ||
            lower.contains('thanh toan thanh cong') ||
            lower.contains('chuyển khoản thành công') ||
            lower.contains('chuyen khoan thanh cong') ||
            lower.contains('chuyển tiền thành công') ||
            lower.contains('chuyen tien thanh cong') ||
            lower.contains('nạp tiền thành công') ||
            lower.contains('nap tien thanh cong') ||
            lower.contains('rút tiền thành công') ||
            lower.contains('rut tien thanh cong') ||
            lower.contains('mbvcb') ||
            lower.contains('ct tu') ||
            lower.contains('ct từ') ||
            lower.contains('cashin') ||
            lower.contains('ecom.ew') ||
            (lower.contains('giao dịch thành công') && (lower.contains('mã') || lower.contains('ref') || lower.contains('ft') || lower.contains('tiền')));

        final hasSignedAmount = RegExp(r'([+-])\s*[0-9]{1,3}(?:[.,][0-9]{3})+\s*(?:vnd|vnđ|d|đ)?\b', caseSensitive: false).hasMatch(combinedText);

        if (!hasBalanceKeyword && !hasTransactionEvent && !hasSignedAmount) {
          debugPrint('[NotificationSyncService] ⚠️ Bỏ qua vì không phải biến động số dư thực tế: $title');
          return;
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
        // NGUYÊN TẮC:
        // - Thu Nhập -> Bắt buộc giữ nguyên danh mục THU_NHAP
        // - Đã nhận diện Sức khỏe & Y tế (SUC_KHOE: mua thuốc, bệnh viện, FPT Long Châu...) -> Bắt buộc giữ nguyên SUC_KHOE, không để AI hạ cấp sang Ăn uống/Mua sắm!
        String finalCategory = 'THU_NHAP';
        if (parsedTx['type'] == 'expense') {
          finalCategory = parsedTx['categoryCode'] ?? 'AN_UONG';
          if (finalCategory != 'SUC_KHOE') {
            try {
              final textForAi = (parsedTx['transferContent'] as String? ?? '').isNotEmpty
                  ? parsedTx['transferContent'] as String
                  : parsedTx['note'] as String;
              final aiRes = await ApiService().classifyWithAi(textForAi);
              if (aiRes != null && aiRes['category_code'] != null && aiRes['category_code'] != 'THU_NHAP') {
                finalCategory = aiRes['category_code'];
              }
            } catch (_) {}
          }
        } else {
          finalCategory = (parsedTx['categoryCode'] as String?) ?? 'TIEN_CHUYEN_DEN';
        }

        // 6. Tự động lưu giao dịch vào FinWise qua API (kèm đúng ngày phát hiện)
        final dateToSave = parsedTx['date'] is DateTime
            ? DateFormat('yyyy-MM-dd').format(parsedTx['date'])
            : DateFormat('yyyy-MM-dd').format(DateTime.now());

        final success = await ApiService().createTransaction(
          amount: parsedTx['amount'],
          note: parsedTx['note'],
          type: parsedTx['type'],
          categoryCode: finalCategory,
          transactionDate: dateToSave,
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

  /// Thuật toán bóc tách thông báo ngân hàng / ZaloPay / ShopeePay / MoMo
  Map<String, dynamic>? _parseNotification(String text, String packageName) {
    final parsed = parseBankText(text, packageName: packageName);
    if (parsed == null || (parsed['amount'] as double? ?? 0) < 1000) {
      return null;
    }

    String fullNote = '${parsed['source']}: ${parsed['note']}';
    if (fullNote.length > 80) {
      fullNote = fullNote.substring(0, 80);
    }
    parsed['note'] = fullNote;
    return parsed;
  }

  /// Hàm bóc tách giao dịch chuẩn hóa dùng chung cho cả Lắng nghe thông báo ngầm và Màn hình Nhập liệu
  static Map<String, dynamic>? parseBankText(String rawText, {String? packageName}) {
    if (rawText.trim().isEmpty) return null;

    final lower = rawText.toLowerCase();

    // 1. Xác định nguồn ngân hàng / ví điện tử (Ưu tiên đơn vị gửi thông báo)
    String source = 'Ngân hàng';
    final pkg = (packageName ?? '').toLowerCase();

    if (pkg.contains('vcb') || lower.contains('vietcombank') || lower.contains('mbvcb') || lower.contains('vcb:')) {
      source = 'Vietcombank';
    } else if (pkg.contains('zalopay') || (lower.contains('zalopay') && !lower.contains('tai '))) {
      source = 'ZaloPay';
    } else if (pkg.contains('momo') || (lower.contains('momo') && !lower.contains('tai '))) {
      source = 'Ví MoMo';
    } else if (pkg.contains('shopee') || lower.contains('shopee') || lower.contains('airpay')) {
      source = 'ShopeePay';
    } else if (pkg.contains('mb') || lower.contains('mbbank')) {
      source = 'MB Bank';
    } else if (pkg.contains('techcombank')) {
      source = 'Techcombank';
    } else if (pkg.contains('vib') || lower.contains('myvib')) {
      source = 'VIB (MyVIB)';
    } else if (pkg.contains('vnpay')) {
      source = 'Ví VNPAY';
    } else if (pkg.contains('vpbank')) {
      source = 'VPBank';
    } else if (pkg.contains('agribank')) {
      source = 'Agribank';
    } else if (pkg.contains('bidv')) {
      source = 'BIDV';
    } else if (pkg.contains('acb')) {
      source = 'ACB';
    } else if (pkg.contains('vietinbank') || pkg.contains('icb')) {
      source = 'VietinBank';
    }

    // 2. Bóc tách số tiền & loại trừ phần số dư cuối
    String textWithoutBalance = rawText;
    final balanceDelims = [
      'số dư:', 'so du:', 'số dư cuối', 'số dư khả dụng', 'so du kha dung',
      'balance:', 'khả dụng:', 'sd:'
    ];
    int cutIndex = -1;
    for (final delim in balanceDelims) {
      final idx = lower.indexOf(delim);
      if (idx >= 0 && (cutIndex == -1 || idx < cutIndex)) {
        cutIndex = idx;
      }
    }
    if (cutIndex > 0) {
      textWithoutBalance = rawText.substring(0, cutIndex);
    }

    double detectedAmount = 0;
    String? detectedTypeFromSign;

    // k/K match (vd: +250k, -50k)
    final kMatch = RegExp(r'([+-])\s*([0-9]{1,4}(?:[.,][0-9]{1,3})?)\s*[kK]\b').firstMatch(textWithoutBalance);
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

    // Signed full amount: +250,000VND, -45.000đ
    if (detectedAmount == 0) {
      final signedMatch = RegExp(
        r'([+-])\s*([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})\s*(?:vnd|vnđ|d|đ)?\b',
        caseSensitive: false,
      ).firstMatch(textWithoutBalance);
      if (signedMatch != null) {
        final signStr = signedMatch.group(1);
        final rawNum = signedMatch.group(2)!.replaceAll(RegExp(r'[^0-9]'), '');
        detectedAmount = double.tryParse(rawNum) ?? 0;
        if (signStr == '+') detectedTypeFromSign = 'income';
        if (signStr == '-') detectedTypeFromSign = 'expense';
      }
    }

    // Keyword amount: thanh toán 50.000, cộng 100,000, số tiền 20.000...
    if (detectedAmount == 0) {
      final keywordMatch = RegExp(
        r'(?:thanh toán|chuyển tiền|chuyển khoản|nhận tiền từ|cộng tiền|trừ tiền|số tiền|so tien|ghi nợ|ghi có)[:\s]+(?:thành công\s+)?([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})\s*(?:vnd|vnđ|d|đ)?\b',
        caseSensitive: false,
      ).firstMatch(textWithoutBalance);
      if (keywordMatch != null) {
        final rawNum = keywordMatch.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
        detectedAmount = double.tryParse(rawNum) ?? 0;
      }
    }

    // Currency format amount
    if (detectedAmount == 0) {
      final anyMatch = RegExp(
        r'\b([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})\s*(?:vnd|vnđ|d|đ)\b',
        caseSensitive: false,
      ).firstMatch(textWithoutBalance);
      if (anyMatch != null) {
        final rawNum = anyMatch.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
        detectedAmount = double.tryParse(rawNum) ?? 0;
      }
    }

    // 3. Phân loại 2 Mục Lớn: Thu Nhập vs Chi Tiêu (Ưu tiên tuyệt đối)
    String type = 'expense';
    if (detectedTypeFromSign != null) {
      type = detectedTypeFromSign;
    } else {
      final hasIncomeKeywords = lower.contains('+') ||
          lower.contains('cong tien') || lower.contains('cộng tiền') ||
          lower.contains('duoc cong') || lower.contains('được cộng') ||
          lower.contains('nhan tien tu') || lower.contains('nhận tiền từ') ||
          lower.contains('nhan duoc tien') || lower.contains('nhận được tiền') ||
          lower.contains('tien vao') || lower.contains('tiền vào') ||
          lower.contains('tien ve') || lower.contains('tiền về') ||
          lower.contains('chuyen den tai khoan') || lower.contains('chuyển đến tài khoản') ||
          lower.contains('hoan tien') || lower.contains('hoàn tiền') || lower.contains('refund') ||
          lower.contains('credit') || lower.contains('cr:') ||
          lower.contains('ghi có') || lower.contains('ghi co') ||
          lower.contains('interest payment') || lower.contains('tien lai') || lower.contains('tiền lãi');

      final hasExpenseKeywords = lower.contains('-') ||
          lower.contains('tru') || lower.contains('trừ') ||
          lower.contains('bi tru') || lower.contains('bị trừ') ||
          lower.contains('thanh toan') || lower.contains('thanh toán') ||
          lower.contains('rut tien') || lower.contains('rút tiền') ||
          lower.contains('chuyen di') || lower.contains('chuyển đi') ||
          lower.contains('debit') || lower.contains('dr:') ||
          lower.contains('ghi nợ') || lower.contains('ghi no');

      if (hasIncomeKeywords && !hasExpenseKeywords) {
        type = 'income';
      } else if (hasIncomeKeywords && hasExpenseKeywords) {
        if (lower.contains('cộng tiền') || lower.contains('cong tien') || lower.contains('nhận tiền từ') || lower.contains('nhan tien tu') || lower.contains('ghi có')) {
          type = 'income';
        } else {
          type = 'expense';
        }
      } else {
        type = 'expense';
      }
    }

    // 4. Trích xuất Ngày và Giờ giao dịch
    DateTime? detectedDate;
    final dateMatch = RegExp(r'\b(0?[1-9]|[12][0-9]|3[01])[\/\-\.](0?[1-9]|1[012])[\/\-\.](202\d|\d{2})\b').firstMatch(rawText);
    if (dateMatch != null) {
      try {
        final d = int.parse(dateMatch.group(1)!);
        final m = int.parse(dateMatch.group(2)!);
        var y = int.parse(dateMatch.group(3)!);
        if (y < 100) y += 2000;
        detectedDate = DateTime(y, m, d);
      } catch (_) {}
    }

    int? detectedHour;
    final timeMatch = RegExp(r'\b([0-1]?[0-9]|2[0-3])[:h]([0-5][0-9])\b').firstMatch(rawText);
    if (timeMatch != null) {
      detectedHour = int.tryParse(timeMatch.group(1)!);
    }

    // 5. Bóc tách Đối tác (Người nhận / gửi), Nội dung chuyển tiền & Danh mục
    String counterparty = '';
    String sender = '';
    String transferContent = '';
    String suggestedCategory = type == 'income' ? 'THU_NHAP' : 'AN_UONG';

    // MẪU ĐẶC BIỆT 1: ZALOPAY ECOM CASHIN / THANH TOÁN
    if (lower.contains('zalopay') && (lower.contains('ecom') || lower.contains('cashin') || lower.contains('ew'))) {
      counterparty = 'Ví ZaloPay';
      final phoneMatch = RegExp(r'\b(0\d{9})\b').firstMatch(rawText);
      final phone = phoneMatch?.group(1);
      final phoneSuffix = phone != null ? ' ($phone)' : '';

      if (lower.contains('cashin') || lower.contains('nạp')) {
        transferContent = 'Nạp ví ZaloPay';
        suggestedCategory = 'TIET_KIEM_DAU_TU';
        return {
          'amount': detectedAmount,
          'type': 'expense',
          'sender': '',
          'counterparty': 'Ví ZaloPay',
          'transferContent': transferContent,
          'note': 'Nạp tiền ví ZaloPay$phoneSuffix',
          'categoryCode': suggestedCategory,
          'source': source == 'Ngân hàng' ? 'Vietcombank' : source,
          'date': detectedDate,
          'hour': detectedHour,
        };
      } else {
        transferContent = 'Thanh toán ZaloPay';
        suggestedCategory = 'MUA_SAM';
        return {
          'amount': detectedAmount,
          'type': 'expense',
          'sender': '',
          'counterparty': 'Ví ZaloPay',
          'transferContent': transferContent,
          'note': 'Thanh toán qua ZaloPay',
          'categoryCode': suggestedCategory,
          'source': source == 'Ngân hàng' ? 'Vietcombank' : source,
          'date': detectedDate,
          'hour': detectedHour,
        };
      }
    }

    // MẪU ĐẶC BIỆT 2: VIETCOMBANK CT TU ... TOI ... [TAI ...]
    final ctMatch = RegExp(
      r'\bCT\s+(?:tu|từ)\s+(.+?)\s+(?:toi|tới|đến|den)\s+(.+?)(?:\s+(?:tai|tại)\s+([A-Za-z0-9_\s]+))?$',
      caseSensitive: false,
    ).firstMatch(rawText);

    if (ctMatch != null) {
      final senderPart = ctMatch.group(1)!.trim();
      final receiverPart = ctMatch.group(2)!.trim();

      sender = senderPart.replaceAll(RegExp(r'^\d{8,20}\s+'), '').trim();

      var beforeCt = rawText.substring(0, ctMatch.start).trim();
      final refIdx = beforeCt.toLowerCase().lastIndexOf(RegExp(r'\b(?:ref|nd|nội dung|noi dung)[:\s]+'));
      if (refIdx >= 0) {
        beforeCt = beforeCt.substring(refIdx).replaceFirst(RegExp(r'^(?:ref|nd|nội dung|noi dung)[:\s]+', caseSensitive: false), '').trim();
      }

      final dotParts = beforeCt.split('.').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      for (final part in dotParts.reversed) {
        final p = part.replaceAll(RegExp(r'^(?:ref|nd)[:\s]+', caseSensitive: false), '').trim();
        final pLow = p.toLowerCase();
        final isSystemCode = p.isEmpty ||
            RegExp(r'^MBVCB', caseSensitive: false).hasMatch(p) ||
            RegExp(r'^\d+$').hasMatch(p) ||
            RegExp(r'^[A-Z0-9]{8,}$').hasMatch(p) ||
            (RegExp(r'^(?=.*[0-9])(?=.*[A-Za-z])[A-Za-z0-9]{4,10}$').hasMatch(p) && !p.contains(' ')) ||
            pLow.contains('sd:') || pLow.contains('số dư') || pLow.contains('so du') ||
            pLow.contains('vnd') || pLow.startsWith('tk ') ||
            pLow.endsWith('chuyen tien') || pLow.endsWith('chuyển tiền');

        if (p.length >= 3 && !isSystemCode) {
          transferContent = p;
          break;
        }
      }

      String cleanReceiver = receiverPart;
      cleanReceiver = cleanReceiver.replaceAll(RegExp(r'#[A-Za-z0-9_]+#[A-Za-z0-9_]+#'), '');
      cleanReceiver = cleanReceiver.replaceAll(RegExp(r'#[A-Za-z0-9_]+#'), '');
      cleanReceiver = cleanReceiver.replaceAll(
        RegExp(r'^(?:PMC\d+|VQR\w+|MBBHX\w+|ZLP\d+|99MM\w+|AGBMBF\w+|AGB\w+|\d{8,20})\s*', caseSensitive: false),
        '',
      );
      cleanReceiver = cleanReceiver.replaceAll('#', ' ').trim();

      if (cleanReceiver.toUpperCase().startsWith('MOMO_')) {
        cleanReceiver = cleanReceiver.substring(5).trim();
      } else if (cleanReceiver.toUpperCase().startsWith('MOMO ')) {
        cleanReceiver = cleanReceiver.substring(5).trim();
      }

      if (cleanReceiver.contains('_')) {
        cleanReceiver = cleanReceiver.split('_').first.trim();
      }

      final upperR = cleanReceiver.toUpperCase();
      if (upperR.contains('LONG CHAU') || upperR.contains('LONG CHÂU') || upperR.contains('FPT PHARMA') || upperR.contains('FPT LONG CHAU')) {
        cleanReceiver = 'Nhà thuốc FPT Long Châu';
        suggestedCategory = 'SUC_KHOE';
      } else if (upperR.contains('PHARMACITY')) {
        cleanReceiver = 'Pharmacity';
        suggestedCategory = 'SUC_KHOE';
      } else if (upperR.contains('AN KHANG') && (upperR.contains('THUOC') || upperR.contains('THUỐC') || upperR.contains('DUOC') || upperR.contains('DƯỢC') || upperR.contains('NHA THUOC') || upperR.contains('PHARMA') || upperR.contains('MWG'))) {
        cleanReceiver = 'Nhà thuốc An Khang';
        suggestedCategory = 'SUC_KHOE';
      } else if (upperR.contains('BENH VIEN') || upperR.contains('BỆNH VIỆN') || upperR.startsWith('BV ') || upperR.startsWith('BV_')) {
        suggestedCategory = 'SUC_KHOE';
        if (upperR.startsWith('BV ') || upperR.startsWith('BV_')) {
          cleanReceiver = 'Bệnh viện ${cleanReceiver.substring(3).trim()}';
        }
      } else if (upperR.contains('PHONG KHAM') || upperR.contains('PHÒNG KHÁM') || upperR.contains('NHA KHOA') || upperR.contains('TRUNG TAM Y TE') || upperR.contains('TRUNG TÂM Y TẾ')) {
        suggestedCategory = 'SUC_KHOE';
      } else if (upperR.contains('NHA THUOC') || upperR.contains('NHÀ THUỐC') || upperR.contains('TIEM THUOC') || upperR.contains('TIỆM THUỐC') || upperR.contains('QUAY THUOC') || upperR.contains('PHARMACY') || upperR.contains('DUOC PHAM') || upperR.contains('DƯỢC PHẨM')) {
        suggestedCategory = 'SUC_KHOE';
      } else if (upperR.contains('BACH HOA XANH')) {
        cleanReceiver = 'Bách Hóa Xanh';
        suggestedCategory = 'MUA_SAM';
      } else if (upperR.contains('ZION')) {
        cleanReceiver = 'ZaloPay (Zion)';
        suggestedCategory = 'HOA_DON';
      } else if (upperR.contains('MINI MART') || upperR.contains('MART') || upperR.contains('MARKET') || upperR.contains('SIEU THI')) {
        suggestedCategory = 'MUA_SAM';
      } else if (upperR.contains('BAKERY') || upperR.contains('COFFEE') || upperR.contains('TEA') || upperR.contains('CAFE') || upperR.contains('FOOD')) {
        suggestedCategory = 'AN_UONG';
      }

      counterparty = cleanReceiver;

      final lowerContent = transferContent.toLowerCase();
      final isMedicalContent = lowerContent.contains('thuốc') || lowerContent.contains('thuoc') ||
          lowerContent.contains('khám') || lowerContent.contains('kham') ||
          lowerContent.contains('bệnh viện') || lowerContent.contains('benh vien') ||
          lowerContent.contains('viện phí') || lowerContent.contains('vien phi') ||
          lowerContent.contains('nha khoa') || lowerContent.contains('bác sĩ') || lowerContent.contains('bac si') ||
          lowerContent.contains('phòng khám') || lowerContent.contains('phong kham') ||
          lowerContent.contains('xét nghiệm') || lowerContent.contains('xet nghiem') ||
          lowerContent.contains('tiêm') || lowerContent.contains('tiem') ||
          lowerContent.contains('chích ngừa') || lowerContent.contains('chich ngua') ||
          lowerContent.contains('vắc xin') || lowerContent.contains('vac xin') ||
          lowerContent.contains('răng') || lowerContent.contains('rang') ||
          lowerContent.contains('y tế') || lowerContent.contains('y te') ||
          lowerContent.contains('dược phẩm') || lowerContent.contains('duoc pham') ||
          lowerContent.contains('sức khỏe') || lowerContent.contains('suc khoe') ||
          lowerContent.contains('fpt pharma') || lowerContent.contains('long châu') || lowerContent.contains('long chau') ||
          lowerContent.contains('pharmacity') || lowerContent.contains('an khang');

      if (isMedicalContent) {
        suggestedCategory = 'SUC_KHOE';
      } else if (lowerContent.contains('cơm') || lowerContent.contains('com') ||
          lowerContent.contains('xôi') || lowerContent.contains('xoi') ||
          lowerContent.contains('bánh') || lowerContent.contains('banh') ||
          lowerContent.contains('redbull') || lowerContent.contains('cafe') ||
          lowerContent.contains('trà') || lowerContent.contains('tra')) {
        suggestedCategory = 'AN_UONG';
      }

      String note = '';
      if (transferContent.isNotEmpty) {
        if (counterparty.isNotEmpty && !transferContent.toLowerCase().contains(counterparty.toLowerCase())) {
          note = '$transferContent (Đến: $counterparty)';
        } else {
          note = transferContent;
        }
      } else {
        final lowCp = counterparty.toLowerCase();
        final isPharmacy = lowCp.contains('thuốc') || lowCp.contains('thuoc') ||
            lowCp.contains('pharma') || lowCp.contains('long châu') || lowCp.contains('long chau') ||
            lowCp.contains('pharmacity') || lowCp.contains('an khang') || lowCp.contains('dược');
        final isDental = lowCp.contains('nha khoa') || lowCp.contains('răng');
        final isHospital = lowCp.contains('bệnh viện') || lowCp.contains('benh vien') ||
            lowCp.contains('phòng khám') || lowCp.contains('phong kham') ||
            lowCp.contains('y tế') || lowCp.contains('clinic') || lowCp.contains('hospital');
        final isStore = [
          'bách hóa xanh', 'mart', 'bakery', 'coffee', 'tea', 'cafe', 'zalopay'
        ].any((w) => lowCp.contains(w));

        if (isPharmacy) {
          note = 'Mua thuốc $counterparty';
        } else if (isDental) {
          note = 'Khám răng $counterparty';
        } else if (isHospital) {
          note = 'Khám chữa bệnh $counterparty';
        } else if (isStore) {
          note = 'Mua hàng $counterparty';
        } else {
          note = 'Chuyển cho $counterparty';
        }
      }

      return {
        'amount': detectedAmount,
        'type': 'expense',
        'sender': sender,
        'counterparty': counterparty,
        'transferContent': transferContent,
        'note': note,
        'categoryCode': suggestedCategory,
        'source': 'Vietcombank',
        'date': detectedDate,
        'hour': detectedHour,
      };
    }

    // MẪU ĐẶC BIỆT 3: NHẬN TIỀN CHUYỂN KHOẢN (VCB VÀ CÁC NGÂN HÀNG CÓ TỪ KHÓA REF / #SP# / CHUYEN TIEN)
    if (type == 'income' &&
        (lower.contains('ref') ||
            lower.contains('#sp#') ||
            lower.contains('chuyen tien') ||
            lower.contains('chuyển tiền') ||
            lower.contains('chuyen khoan') ||
            lower.contains('chuyển khoản'))) {
      // 1. Tìm phần nội dung sau từ khóa Ref (hoặc nd / nội dung)
      final refMatch = RegExp(r'\b(?:ref|nd|nội dung|noi dung)[:\s]+(.+)$', caseSensitive: false, multiLine: true).firstMatch(rawText);
      if (refMatch != null) {
        var refContent = refMatch.group(1)!.trim();
        // Cắt bỏ phần mã hệ thống #SP#... hoặc #...#
        refContent = refContent.replaceAll(RegExp(r'#SP#.*$', caseSensitive: false), '');
        refContent = refContent.replaceAll(RegExp(r'#[A-Za-z0-9_]+.*$'), '').trim();
        // Cắt bỏ mã giao dịch số hoặc prefix hệ thống đứng trước tên người gửi (ví dụ: 123456 NGUYEN VAN A)
        refContent = refContent.replaceAll(RegExp(r'^\d{6,}[\.\s]+'), '');
        refContent = refContent.replaceAll(RegExp(r'^(?:MBVCB|IBFT|FT\d+|VCB)[\.\s]+', caseSensitive: false), '').trim();

        // Tách Tên Người Gửi và Nội dung giao dịch (hành động chuyển tiền)
        final actionKeywordRegex = RegExp(
          r'^(?:chuyen tien|chuyển tiền|chuyen khoan|chuyển khoản|tra tien|trả tiền|dong tien|đóng tiền|gui tien|gửi tiền|ung ho|ủng hộ|thanh toan|thanh toán|ck\b|ibft\b)',
          caseSensitive: false,
        );
        final actionMatch = RegExp(
          r'^([A-ZÀ-Ỹa-z\s]{2,40}?)[\.\s]+(chuyen tien|chuyển tiền|chuyen khoan|chuyển khoản|tra tien|trả tiền|dong tien|đóng tiền|gui tien|gửi tiền|ung ho|ủng hộ|thanh toan|thanh toán|ck\b|ibft\b)(.*)$',
          caseSensitive: false,
        ).firstMatch(refContent);

        if (actionMatch != null) {
          sender = actionMatch.group(1)!.trim();
          final action = actionMatch.group(2)!.trim();
          final extra = actionMatch.group(3)!.trim();
          transferContent = (action + (extra.isNotEmpty ? ' $extra' : '')).trim();
        } else if (actionKeywordRegex.hasMatch(refContent)) {
          sender = '';
          transferContent = refContent.trim();
        } else {
          // Toàn bộ refContent là tên người gửi
          sender = refContent.trim();
          transferContent = 'Nhận tiền chuyển khoản';
        }
      } else {
        // Trường hợp không có chữ "Ref", nhưng có cú pháp "... [TÊN] chuyen tien#SP#..."
        final spMatch = RegExp(
          r'(?:ref|nd|nội dung|noi dung)?[:\s]*([A-ZÀ-Ỹa-z\s]{2,40}?)[\.\s]+(?:chuyen tien|chuyển tiền)#SP#',
          caseSensitive: false,
        ).firstMatch(rawText);
        if (spMatch != null) {
          sender = spMatch.group(1)!.replaceAll(RegExp(r'^(?:ref|nd)[:\s]+', caseSensitive: false), '').trim();
          transferContent = 'chuyen tien';
        }
      }

      // Làm sạch dấu chấm, phẩy thừa ở cuối
      sender = sender.replaceAll(RegExp(r'[\.\,\:\;\-]+$'), '').trim();
      transferContent = transferContent.replaceAll(RegExp(r'[\.\,\:\;\-]+$'), '').trim();

      counterparty = sender;
      final isDefaultRemark = transferContent.isEmpty ||
          RegExp(r'^(chuyen tien|chuyển tiền|chuyen khoan|chuyển khoản|ck|nhận tiền chuyển khoản)$', caseSensitive: false).hasMatch(transferContent);

      final note = (transferContent.isNotEmpty && !isDefaultRemark)
          ? (sender.isNotEmpty ? '$transferContent (Từ: $sender)' : transferContent)
          : (sender.isNotEmpty ? 'Nhận tiền từ $sender' : 'Nhận tiền chuyển khoản');

      return {
        'amount': detectedAmount,
        'type': 'income',
        'sender': sender,
        'counterparty': counterparty,
        'transferContent': transferContent,
        'note': note,
        'categoryCode': 'TIEN_CHUYEN_DEN',
        'source': source == 'Ngân hàng' ? 'Vietcombank' : source,
        'date': detectedDate,
        'hour': detectedHour,
      };
    }

    // MẪU ĐẶC BIỆT 4: TIỀN LÃI TÀI KHOẢN (INTEREST PAYMENT)
    if (lower.contains('interest payment') || lower.contains('tiền lãi')) {
      return {
        'amount': detectedAmount,
        'type': 'income',
        'sender': 'Vietcombank',
        'counterparty': 'Vietcombank',
        'transferContent': 'Tiền lãi tài khoản',
        'note': 'Tiền lãi tài khoản Vietcombank',
        'categoryCode': 'THU_NHAP',
        'source': 'Vietcombank',
        'date': detectedDate,
        'hour': detectedHour,
      };
    }

    // MẪU 5: THÔNG BÁO / SMS NGÂN HÀNG TIÊU CHUẨN (MB, TECHCOM, VPBANK, ACB, MOMO...)
    final partyRegex = RegExp(
      r'(?:đến|den|tới|toi|gửi đến|gui den|chuyển đến|chuyen den|cho|từ|tu|người nhận|nguoi nhan|người gửi|nguoi gui)[:\s]+([^.,\n|]{3,50})(?=[.,\n|]|\s+(?:lúc|luc|ngày|ngay|vào|vao|nội dung|noi dung|nd|ref|số dư|so du)|$)',
      caseSensitive: false,
    );
    final partyMatch = partyRegex.firstMatch(rawText);
    if (partyMatch != null) {
      String rawParty = partyMatch.group(1)!.trim();
      rawParty = rawParty.replaceAll(RegExp(r'^(?:PMC\d+|VQR\w+|MBBHX\w+|ZLP\d+|99MM\w+|AGB\w+|\d{8,20})\s*', caseSensitive: false), '');
      rawParty = rawParty.replaceAll(RegExp(r'#[^#]+#'), '').trim();
      if (!RegExp(r'^(vnd|vnđ|d|đ|tk|tài khoản|so du|số dư|thành công|thanh cong)\b', caseSensitive: false).hasMatch(rawParty)) {
        if (rawParty.toUpperCase().startsWith('MOMO_')) rawParty = rawParty.substring(5).trim();
        if (rawParty.contains('_')) rawParty = rawParty.split('_').first.trim();
        final upperP = rawParty.toUpperCase();
        if (upperP.contains('LONG CHAU') || upperP.contains('LONG CHÂU') || upperP.contains('FPT PHARMA') || upperP.contains('FPT LONG CHAU')) {
          rawParty = 'Nhà thuốc FPT Long Châu';
          suggestedCategory = 'SUC_KHOE';
        } else if (upperP.contains('PHARMACITY')) {
          rawParty = 'Pharmacity';
          suggestedCategory = 'SUC_KHOE';
        } else if (upperP.contains('AN KHANG') && (upperP.contains('THUOC') || upperP.contains('THUỐC') || upperP.contains('DUOC') || upperP.contains('DƯỢC') || upperP.contains('NHA THUOC') || upperP.contains('PHARMA') || upperP.contains('MWG'))) {
          rawParty = 'Nhà thuốc An Khang';
          suggestedCategory = 'SUC_KHOE';
        } else if (upperP.contains('BENH VIEN') || upperP.contains('BỆNH VIỆN') || upperP.startsWith('BV ') || upperP.startsWith('BV_')) {
          suggestedCategory = 'SUC_KHOE';
          if (upperP.startsWith('BV ') || upperP.startsWith('BV_')) {
            rawParty = 'Bệnh viện ${rawParty.substring(3).trim()}';
          }
        } else if (upperP.contains('PHONG KHAM') || upperP.contains('PHÒNG KHÁM') || upperP.contains('NHA KHOA') || upperP.contains('TRUNG TAM Y TE') || upperP.contains('TRUNG TÂM Y TẾ')) {
          suggestedCategory = 'SUC_KHOE';
        } else if (upperP.contains('NHA THUOC') || upperP.contains('NHÀ THUỐC') || upperP.contains('TIEM THUOC') || upperP.contains('TIỆM THUỐC') || upperP.contains('QUAY THUOC') || upperP.contains('PHARMACY') || upperP.contains('DUOC PHAM')) {
          suggestedCategory = 'SUC_KHOE';
        } else if (upperP.contains('BACH HOA XANH')) {
          rawParty = 'Bách Hóa Xanh';
          suggestedCategory = 'MUA_SAM';
        }
        counterparty = rawParty;
      }
    }

    final ndMatch = RegExp(
      r'(?:\bnd\b|\bnoi dung\b|\bnội dung\b|\blời nhắn\b|\bloi nhan\b|\bref\b|\blý do\b|\bly do\b)[:\s]+([^.\n|]+)',
      caseSensitive: false,
    ).firstMatch(rawText);
    if (ndMatch != null) {
      transferContent = ndMatch.group(1)!.trim();
      final dotParts = transferContent.split('.');
      if (dotParts.length > 1 && dotParts.last.trim().length >= 3) {
        transferContent = dotParts.last.trim();
      }
    } else {
      final taiMatch = RegExp(r'\b(?:tại|tai)\s+([^.\n|]+)', caseSensitive: false).firstMatch(rawText);
      if (taiMatch != null) {
        transferContent = 'Tại ${taiMatch.group(1)!.trim()}';
      }
    }

    String note = '';
    if (transferContent.isNotEmpty && counterparty.isNotEmpty) {
      if (transferContent.toLowerCase().contains(counterparty.toLowerCase())) {
        note = transferContent;
      } else {
        note = type == 'income' ? '$transferContent (Từ: $counterparty)' : '$transferContent (Đến: $counterparty)';
      }
    } else if (transferContent.isNotEmpty) {
      note = transferContent;
    } else if (counterparty.isNotEmpty) {
      final lowCp = counterparty.toLowerCase();
      final isPharmacy = lowCp.contains('thuốc') || lowCp.contains('thuoc') ||
          lowCp.contains('pharma') || lowCp.contains('long châu') || lowCp.contains('long chau') ||
          lowCp.contains('pharmacity') || lowCp.contains('an khang') || lowCp.contains('dược');
      final isDental = lowCp.contains('nha khoa') || lowCp.contains('răng');
      final isHospital = lowCp.contains('bệnh viện') || lowCp.contains('benh vien') ||
          lowCp.contains('phòng khám') || lowCp.contains('phong kham') ||
          lowCp.contains('y tế') || lowCp.contains('clinic') || lowCp.contains('hospital');
      if (isPharmacy && type == 'expense') {
        note = 'Mua thuốc $counterparty';
      } else if (isDental && type == 'expense') {
        note = 'Khám răng $counterparty';
      } else if (isHospital && type == 'expense') {
        note = 'Khám chữa bệnh $counterparty';
      } else {
        note = type == 'income' ? 'Nhận từ $counterparty' : 'Chuyển cho $counterparty';
      }
    } else {
      note = type == 'income' ? 'Nhận tiền chuyển khoản' : 'Thanh toán chuyển khoản';
    }

    if (type == 'expense') {
      final lowerCheck = '${counterparty.toLowerCase()} ${note.toLowerCase()} ${transferContent.toLowerCase()} ${rawText.toLowerCase()}';
      if (lowerCheck.contains('thuốc') || lowerCheck.contains('thuoc') ||
          lowerCheck.contains('khám') || lowerCheck.contains('kham') ||
          lowerCheck.contains('bệnh viện') || lowerCheck.contains('benh vien') ||
          lowerCheck.contains('viện phí') || lowerCheck.contains('vien phi') ||
          lowerCheck.contains('nha khoa') || lowerCheck.contains('bác sĩ') || lowerCheck.contains('bac si') ||
          lowerCheck.contains('phòng khám') || lowerCheck.contains('phong kham') ||
          lowerCheck.contains('xét nghiệm') || lowerCheck.contains('xet nghiem') ||
          lowerCheck.contains('tiêm') || lowerCheck.contains('tiem') ||
          lowerCheck.contains('chích ngừa') || lowerCheck.contains('chich ngua') ||
          lowerCheck.contains('vắc xin') || lowerCheck.contains('vac xin') ||
          lowerCheck.contains('răng') || lowerCheck.contains('rang') ||
          lowerCheck.contains('y tế') || lowerCheck.contains('y te') ||
          lowerCheck.contains('dược phẩm') || lowerCheck.contains('duoc pham') ||
          lowerCheck.contains('sức khỏe') || lowerCheck.contains('suc khoe') ||
          lowerCheck.contains('pharma') || lowerCheck.contains('long châu') || lowerCheck.contains('long chau') ||
          lowerCheck.contains('pharmacity') || lowerCheck.contains('an khang')) {
        suggestedCategory = 'SUC_KHOE';
      } else if (lowerCheck.contains('bách hóa') || lowerCheck.contains('mart') || lowerCheck.contains('mua sắm')) {
        suggestedCategory = 'MUA_SAM';
      } else if (lowerCheck.contains('cơm') || lowerCheck.contains('com') || lowerCheck.contains('cà phê') ||
          lowerCheck.contains('cafe') || lowerCheck.contains('coffee') || lowerCheck.contains('tea') ||
          lowerCheck.contains('bakery') || lowerCheck.contains('bánh') || lowerCheck.contains('redbull')) {
        suggestedCategory = 'AN_UONG';
      }
    }

    return {
      'amount': detectedAmount,
      'type': type,
      'sender': sender,
      'counterparty': counterparty,
      'transferContent': transferContent,
      'note': note,
      'categoryCode': suggestedCategory,
      'source': source,
      'date': detectedDate,
      'hour': detectedHour,
    };
  }
}
