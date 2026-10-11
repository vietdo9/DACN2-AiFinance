# 📱 FinWise Mobile & Multi-Platform (Flutter)

Ứng dụng Quản lý Tài chính Cá nhân Tích hợp Trí tuệ Nhân tạo **FinWise** được xây dựng bằng **Flutter**, hỗ trợ đa nền tảng (**Android, iOS, Web, Windows Desktop**).

---

## ✨ Các Tính Năng Nổi Bật

1. **Dashboard Tổng Quan**:
   * Thẻ số dư ví điện tử gradient sang trọng.
   * Thống kê Thu nhập & Chi tiêu trong tháng.
   * Biểu đồ tròn phân bổ chi tiêu trực quan (`fl_chart`).
   * Banner cảnh báo dòng tiền thông minh từ AI.
2. **Thêm Giao Dịch Nhanh & AI Tự Phân Loại**:
   * Người dùng chỉ cần gõ ghi chú (Ví dụ: *"Ăn lẩu kichi 350k"* hoặc *"Đổ xăng xe máy 60k"*).
   * Bấm nút **"✨ AI Tự Phân Loại"** $\rightarrow$ ứng dụng gọi mô hình **PhoBERT** tự động chọn chính xác danh mục phù hợp.
3. **Dự Báo Chi Tiêu 7 Ngày (LSTM AI Forecaster)**:
   * Biểu đồ đường xu hướng chi tiêu 7 ngày kế tiếp.
   * Cảnh báo mức độ rủi ro chi tiêu: **AN TOÀN**, **CẦN LƯU Ý**, **NGUY CƠ BỘI CHI**.
   * Chi tiết số tiền dự kiến chi cho từng ngày.
4. **Lịch Sử Giao Dịch**:
   * Lọc nhanh theo: *Tất cả*, *Khoản chi*, *Thu nhập*.
   * Gắn nhãn badge giao dịch nào được phân loại bởi AI.

---

## 🚀 Hướng Dẫn Khởi Chạy Ứng Dụng

Mở Terminal tại thư mục `finwise_mobile`:
```powershell
cd e:\DACN2\finwise_mobile
```

### 1. Chạy trên trình duyệt Web (Chrome)
```powershell
flutter run -d chrome
```

### 2. Chạy trên Windows Desktop
```powershell
flutter run -d windows
```

### 3. Chạy trên Thiết bị di động / Máy ảo Android
* Bật máy ảo Android (Android Emulator) hoặc cắm điện thoại Android bật USB Debugging.
* Chạy lệnh:
```powershell
flutter run
```

---

## 📡 Cấu Hình Kết Nối API Backend

Trong file `lib/services/api_service.dart`, ứng dụng đã được cấu hình tự động nhận diện:
* **Khi chạy trên Windows / Web**: Kết nối tới `http://localhost:5000` (Backend Node.js).
* **Khi chạy trên Android Emulator**: Tự động chuyển sang `http://10.0.2.2:5000`.
* **Khi Backend offline**: Ứng dụng tự động kích hoạt chế độ Demo Offline với đầy đủ dữ liệu mẫu để việc demo và chấm điểm không bao giờ bị gián đoạn.
