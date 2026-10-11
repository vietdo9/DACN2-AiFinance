# 🖥️ FinWise Backend API Gateway (Node.js & Supabase)

Backend trung tâm điều phối cho hệ sinh thái Quản lý tài chính cá nhân đa nền tảng **FinWise**, kết nối giữa **Client Flutter** và **AI Microservice (FastAPI)**.

---

## ⚡ Các Tính Năng Chính
1. **Quản lý Tài khoản & Xác thực (Auth)**: Đăng ký, Đăng nhập, cấp JWT token bảo mật, mã hóa mật khẩu với `bcryptjs`.
2. **Cơ sở dữ liệu Supabase (PostgreSQL)**: Quản lý bảng Ví tiền (`wallets`), Giao dịch (`transactions`), Danh mục (`categories`), Ngân sách (`budgets`).
3. **Tích hợp Trí tuệ Nhân tạo (AI Gateway)**:
   * Tự động gọi **PhoBERT** (`POST /api/v1/ai/classify`) để phân loại chi tiêu thông minh khi người dùng nhập ghi chú tiếng Việt.
   * Tự động trích xuất chuỗi 30 ngày của người dùng để gọi **LSTM** (`POST /api/v1/ai/forecast`) tính toán dự báo 7 ngày tiếp theo và cảnh báo nguy cơ bội chi.
4. **Báo cáo Thống kê (Analytics)**: Cung cấp tổng số dư, thu nhập/chi tiêu tháng này, tỷ lệ phần trăm theo danh mục để vẽ biểu đồ tròn.

---

## 🚀 Hướng Dẫn Cấu Hình Supabase

### Bước 1: Tạo Database trên Supabase
1. Đăng nhập vào [https://supabase.com](https://supabase.com) và tạo một Project mới.
2. Mở mục **SQL Editor** trong thanh menu bên trái.
3. Mở file [supabase_schema.sql](./supabase_schema.sql), sao chép toàn bộ nội dung và dán vào SQL Editor $\rightarrow$ bấm **Run**.
4. Các bảng `users`, `wallets`, `categories` (sẵn 10 danh mục chuẩn PhoBERT), `transactions` sẽ được tạo tự động.

### Bước 2: Cập nhật file `.env`
Mở mục **Project Settings -> API** trên Supabase, lấy **Project URL** và **anon public key**, sau đó điền vào file `.env`:
```env
PORT=5000
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_KEY=your-supabase-anon-key
JWT_SECRET=finwise_super_secret_jwt_key_2026_dacn2
AI_SERVICE_URL=http://localhost:8000
```

---

## 💻 Khởi Chạy Server

Chạy ở chế độ thông thường:
```powershell
npm start
```

Chạy ở chế độ tự động reload khi sửa code (Development):
```powershell
npm run dev
```

* Máy chủ khởi động tại: **`http://localhost:5000`**

---

## 📡 Danh Sách API Endpoints

### 1. Xác thực (Auth)
* `POST /api/auth/register`: Đăng ký tài khoản mới (`{ email, password, full_name }`).
* `POST /api/auth/login`: Đăng nhập lấy JWT Token (`{ email, password }`).
  * *(Hỗ trợ tài khoản demo khi chưa kết nối Supabase: `demo@finwise.vn` / `123456`)*.
* `GET /api/auth/me`: Lấy thông tin người dùng hiện tại (cần header `Authorization: Bearer <token>`).

### 2. Ví Tiền (Wallets)
* `GET /api/wallets`: Lấy danh sách ví của người dùng.
* `POST /api/wallets`: Tạo ví mới (`{ name, balance, currency, color }`).

### 3. Giao Dịch (Transactions)
* `GET /api/transactions/categories`: Lấy 10 danh mục chuẩn (Ăn uống, Đi lại, Mua sắm...).
* `GET /api/transactions`: Lấy danh sách lịch sử thu chi (hỗ trợ lọc `?type=expense`, `?category=AN_UONG`).
* `POST /api/transactions`: Tạo giao dịch mới:
  * Nếu không truyền `category_code` mà chỉ nhập `note` (ví dụ: *"Ăn lẩu kichi 300k"*), hệ thống tự động gọi **PhoBERT AI** để dự đoán danh mục và tự động cập nhật số dư ví!
* `DELETE /api/transactions/:id`: Xóa giao dịch.

### 4. AI Gateway
* `GET /api/ai/health`: Kiểm tra kết nối đến AI Microservice.
* `POST /api/ai/classify`: Nhập `{ text: "..." }` để nhận diện danh mục.
* `POST /api/ai/forecast`: Nhập `{ daily_expenses: [30 số] }` để dự báo 7 ngày.
* `GET /api/ai/user-forecast`: Tự động gom dữ liệu 30 ngày của người dùng từ Supabase và trả về kết quả dự báo 7 ngày tới.

### 5. Thống Kê (Analytics)
* `GET /api/analytics/summary`: Thống kê tổng quan số dư, thu/chi tháng này, dữ liệu phân bổ danh mục cho biểu đồ tròn.
