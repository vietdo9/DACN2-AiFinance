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
        // NGUYÊN TẮC: 2 mục lớn Thu Nhập và Chi Tiêu là ưu tiên cao nhất!
        // Nếu là Thu Nhập -> Bắt buộc giữ nguyên danh mục THU_NHAP, tuyệt đối không gọi PhoBERT gán vào Ăn uống/Mua sắm!
        String finalCategory = 'THU_NHAP';
        if (parsedTx['type'] == 'expense') {
          finalCategory = parsedTx['categoryCode'] ?? 'AN_UONG';
          try {
            final textForAi = (parsedTx['transferContent'] as String? ?? '').isNotEmpty
                ? parsedTx['transferContent'] as String
                : parsedTx['note'] as String;
            final aiRes = await ApiService().classifyWithAi(textForAi);
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

    // Regex 0: Bắt số tiền viết tắt dạng k/K chỉ khi có dấu + / - rõ ràng (ví dụ: +250k, -50k)
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

    // Regex 2: Số tiền sau các từ khóa ngân hàng "thanh toán", "cộng", "trừ", "số tiền"
    if (detectedAmount == 0) {
      final keywordMatch = RegExp(r'(?:thanh toán|chuyển tiền|chuyển khoản|nhận tiền từ|cộng tiền|trừ tiền|số tiền|so tien)[:\s]+(?:thành công\s+)?([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9})\s*(?:vnd|vnđ|d|đ)?\b', caseSensitive: false)
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
      // Chỉ nhận diện là Thu Nhập khi có từ khóa biến động cộng tiền ngân hàng cụ thể
      // TUYỆT ĐỐI không dùng 'tang' (trùng 'tặng') hay 'nhan' (trùng 'nhận voucher/quà')
      final hasIncomeKeywords = lower.contains('+') ||
          lower.contains('cong tien') || lower.contains('cộng tiền') ||
          lower.contains('duoc cong') || lower.contains('được cộng') ||
          lower.contains('nhan tien tu') || lower.contains('nhận tiền từ') ||
          lower.contains('nhan duoc tien') || lower.contains('nhận được tiền') ||
          lower.contains('tien vao') || lower.contains('tiền vào') ||
          lower.contains('tien ve') || lower.contains('tiền về') ||
          lower.contains('chuyen den tai khoan') || lower.contains('chuyển đến tài khoản') ||
          lower.contains('hoan tien') || lower.contains('hoàn tiền') || lower.contains('refund') ||
          lower.contains('credit') || lower.contains('cr:');

      final hasExpenseKeywords = lower.contains('-') ||
          lower.contains('tru') || lower.contains('trừ') ||
          lower.contains('bi tru') || lower.contains('bị trừ') ||
          lower.contains('thanh toan') || lower.contains('thanh toán') ||
          lower.contains('rut tien') || lower.contains('rút tiền') ||
          lower.contains('chuyen di') || lower.contains('chuyển đi') ||
          lower.contains('debit') || lower.contains('dr:');

      if (hasIncomeKeywords && !hasExpenseKeywords) {
        type = 'income';
      } else if (hasIncomeKeywords && hasExpenseKeywords) {
        if (lower.contains('cộng tiền') || lower.contains('cong tien') || lower.contains('nhận tiền từ') || lower.contains('nhan tien tu')) {
          type = 'income';
        } else {
          type = 'expense';
        }
      } else {
        type = 'expense';
      }
    }

    // 3. Trích xuất người nhận/gửi và nội dung chuyển tiền
    String counterparty = '';
    final partyRegex = RegExp(
      r'(?:đến|den|tới|toi|gửi đến|gui den|chuyển đến|chuyen den|cho|từ|tu|người nhận|nguoi nhan|người gửi|nguoi gui)[:\s]+([A-Za-z0-9\sÀÁÂÃÈÉÊÌÍÒÓÔÕÙÚĂĐĨŨƠƯĂẠẢẤẦẨẪẬẮẰẲẴẶẸẺẼỀỀỂỄỆỈỊỌỎỐỒỔỖỘỚỜỞỠỢỤỦỨỪỬỮỰỲỴÝỶỸ]{3,35})(?=[.,\n|]|\s+(?:lúc|luc|ngày|ngay|vào|vao|nội dung|noi dung|nd|ref|số dư|so du)|$)',
      caseSensitive: false,
    );
    final partyMatch = partyRegex.firstMatch(text);
    if (partyMatch != null) {
      final rawParty = partyMatch.group(1)!.trim();
      if (!RegExp(r'^(vnd|vnđ|d|đ|tk|tài khoản|so du|số dư|thành công|thanh cong)\b', caseSensitive: false).hasMatch(rawParty)) {
        counterparty = rawParty;
      }
    }

    // 4. Tìm nội dung chuyển tiền (Phải có \b để không bị ăn nhầm 'ND' trong 'VND')
    String transferContent = '';
    final contentRegex = RegExp(
      r'(?:\bnd\b|\bnoi dung\b|\bnội dung\b|\blời nhắn\b|\bloi nhan\b|\bref\b|\blý do\b|\bly do\b)[:\s]+([^.\n|]+)',
      caseSensitive: false,
    );
    final contentMatch = contentRegex.firstMatch(text);
    if (contentMatch != null) {
      transferContent = contentMatch.group(1)!.trim();
      final dotParts = transferContent.split('.');
      if (dotParts.length > 1 && dotParts.last.trim().length >= 3) {
        transferContent = dotParts.last.trim();
      }
    }

    if (transferContent.isEmpty) {
      final taiRegex = RegExp(r'\b(?:tại|tai)\s+([^.\n|]+)', caseSensitive: false);
      final taiMatch = taiRegex.firstMatch(text);
      if (taiMatch != null) {
        transferContent = 'Tại ${taiMatch.group(1)!.trim()}';
      }
    }

    // 5. Kết hợp thành ghi chú hoàn chỉnh và ý nghĩa
    String meaningfulText = '';
    if (transferContent.isNotEmpty && counterparty.isNotEmpty) {
      if (transferContent.toLowerCase().contains(counterparty.toLowerCase())) {
        meaningfulText = transferContent;
      } else {
        meaningfulText = type == 'income'
            ? '$transferContent (Từ: $counterparty)'
            : '$transferContent (Đến: $counterparty)';
      }
    } else if (transferContent.isNotEmpty) {
      meaningfulText = transferContent;
    } else if (counterparty.isNotEmpty) {
      meaningfulText = type == 'income'
          ? 'Nhận từ $counterparty'
          : 'Chuyển cho $counterparty';
    } else {
      meaningfulText = type == 'income' ? 'Nhận tiền chuyển khoản' : 'Thanh toán chuyển khoản';
    }

    String note = '$source: $meaningfulText';
    if (note.length > 80) {
      note = note.substring(0, 80);
    }

    // 6. Gán danh mục chuẩn theo 2 mục lớn
    final categoryCode = type == 'income' ? 'THU_NHAP' : 'AN_UONG';

    return {
      'amount': detectedAmount,
      'type': type,
      'note': note,
      'transferContent': transferContent,
      'counterparty': counterparty,
      'categoryCode': categoryCode,
      'source': source,
    };
  }
}
