import 'package:flutter_test/flutter_test.dart';
import 'package:finwise_mobile/services/notification_sync_service.dart';

void main() {
  group('Vietcombank & Bank SMS Ref Parser Tests', () {
    test('Test 1: User VCB message with DO VAN VIET', () {
      const raw = 'Số dư TK VCB 1028078349 +15,000 VND lúc 03-11-2026 13:50:32. Số dư 2,326,405 VND. Ref DO VAN VIET chuyen tien#SP#020097042211031350312026V523992646.5390.59338.135022';
      final res = NotificationSyncService.parseBankText(raw);

      expect(res, isNotNull);
      expect(res!['amount'], 15000.0);
      expect(res['type'], 'income');
      expect(res['sender'], 'DO VAN VIET');
      expect(res['counterparty'], 'DO VAN VIET');
      expect(res['note'], 'Nhận tiền từ DO VAN VIET');
      expect(res['source'], 'Vietcombank');
      expect(res['categoryCode'], 'TIEN_CHUYEN_DEN');
    });

    test('Test 2: User VCB message with NGUYEN TRAN CONG BAO', () {
      const raw = 'Số dư TK VCB 1028078349 +15,000 VND lúc 03-11-2026 11:59:19. Số dư 2,311,405 VND. Ref NGUYEN TRAN CONG BAO chuyen tien#SP#020097042211031159192026OWD6159249.5390.61318.115919';
      final res = NotificationSyncService.parseBankText(raw);

      expect(res, isNotNull);
      expect(res!['amount'], 15000.0);
      expect(res['type'], 'income');
      expect(res['sender'], 'NGUYEN TRAN CONG BAO');
      expect(res['counterparty'], 'NGUYEN TRAN CONG BAO');
      expect(res['note'], 'Nhận tiền từ NGUYEN TRAN CONG BAO');
      expect(res['source'], 'Vietcombank');
    });

    test('Test 3: VCB message with custom remark tra tien phong', () {
      const raw = 'Số dư TK VCB 1028078349 +1,500,000 VND lúc 03-11-2026 09:00:00. Số dư 3,826,405 VND. Ref TRAN VAN ANH tra tien phong thang 11#SP#99999';
      final res = NotificationSyncService.parseBankText(raw);

      expect(res, isNotNull);
      expect(res!['amount'], 1500000.0);
      expect(res['type'], 'income');
      expect(res['sender'], 'TRAN VAN ANH');
      expect(res['note'], 'tra tien phong thang 11 (Từ: TRAN VAN ANH)');
    });

    test('Test 4: VCB message with sender only after Ref', () {
      const raw = 'Số dư TK VCB 1028078349 +50,000 VND lúc 03-11-2026 10:00:00. Số dư 2,376,405 VND. Ref LE THI MAI#SP#88888';
      final res = NotificationSyncService.parseBankText(raw);

      expect(res, isNotNull);
      expect(res!['amount'], 50000.0);
      expect(res['type'], 'income');
      expect(res['sender'], 'LE THI MAI');
      expect(res['note'], 'Nhận tiền từ LE THI MAI');
    });
    test('Test 5: VCB message outgoing gas transfer with tien xang', () {
      const raw = 'Số dư TK VCB 1028078349 -50,000 VND lúc 08-11-2026 19:27:00. Số dư 2,326,405 VND. Ref MBVCB.123.tien xang. CT tu 1028078349 toi 0987654321 CHI NHANH CONG TY CO PHAN THUONG MA tai VCB';
      final res = NotificationSyncService.parseBankText(raw);

      expect(res, isNotNull);
      expect(res!['amount'], 50000.0);
      expect(res['type'], 'expense');
      expect(res['categoryCode'], 'DI_LAI');
      expect(res['counterparty'], 'CHI NHANH CONG TY CO PHAN THUONG MA');
      expect(res['note'], 'tien xang (Đến: CHI NHANH CONG TY CO PHAN THUONG MA)');
    });

    test('Test 6: VCB message outgoing to gas station brand without content', () {
      const raw = 'Số dư TK VCB 1028078349 -70,000 VND lúc 08-11-2026 19:30:00. Số dư 2,256,405 VND. Ref MBVCB.456. CT tu 1028078349 toi 0987654321 CAY XANG PETROLIMEX SO 1 tai VCB';
      final res = NotificationSyncService.parseBankText(raw);

      expect(res, isNotNull);
      expect(res!['amount'], 70000.0);
      expect(res['type'], 'expense');
      expect(res['categoryCode'], 'DI_LAI');
      expect(res['note'], 'Đổ xăng CAY XANG PETROLIMEX SO 1');
    });
  });
}

