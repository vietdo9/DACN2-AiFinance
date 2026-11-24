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
Lấy **Project URL** và **service_role secret key** trong phần API của Supabase. Chỉ lưu khóa riêng tư này ở backend (ví dụ Render secret environment); tuyệt đối không đưa vào Flutter/mobile hoặc client. Backend dùng khóa này để ghi dữ liệu và gọi RPC quản trị. Không dùng publishable/anon key cho backend sau khi áp dụng migration quản trị.
```env
PORT=5000
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_KEY=your-private-service-role-key
# Optional separate service-role key for admin RPCs
# SUPABASE_ADMIN_KEY=<private service-role key>
JWT_SECRET=<generate a unique random secret of at least 32 bytes>
FINWISE_ADMIN_EMAILS=<comma-separated admin addresses, such as the provisioned admin account>
# Leave unset until a real root account is provisioned
# FINWISE_ROOT_ADMIN_EMAILS=<comma-separated real root account addresses>
AI_SERVICE_URL=http://localhost:8000
```

Admin access requires a stored password hash and an explicit `role: admin` on the user record or an address listed in `FINWISE_ADMIN_EMAILS`. Root-only deletion and root account protection use only real accounts explicitly listed in `FINWISE_ROOT_ADMIN_EMAILS`; there is no default production root account. The fictional `root-admin@example.test` identity is reserved for disposable local/database tests only and must never be provisioned in production. The built-in admin demo credentials are disabled. Generate and configure a unique `JWT_SECRET` before deployment; if it is unset or matches the deprecated default, the server generates an ephemeral process secret and existing sessions will need to sign in again after restart.

### Admin operations rollout

1. Configure the private service-role key on the backend before applying the migration. The migration revokes direct user-table writes from `anon` and `authenticated`; leaving the backend on a publishable key can break registration and normal account updates.
2. Apply [migrations/20261124_admin_operations.sql](./migrations/20261124_admin_operations.sql) in Supabase SQL Editor. It adds explicit role/status/session-version columns and service-role-only transactional admin functions plus an audit table.
3. Deploy the backend with the private key and configured admin/root email lists. Admin list and overview endpoints use Supabase only; they return a service-unavailable response if the required schema is absent rather than mixing local and cloud records.

The `admin_audit_events` table is retained as an operational record of status, role, and deletion actions for backend/SQL review. It intentionally has no admin dashboard viewer in this release.

### Self-service account deletion

Apply [migrations/20261126_self_account_deletion.sql](./migrations/20261126_self_account_deletion.sql) after the admin operations migration. The self-service endpoints require a configured Supabase service-role key and the auth session-version columns from the admin migration. They enforce a 15-second confirmation delay, and the SQL function rechecks the account role, configured admin/root addresses, and current session version under a row lock. Local JSON accounts and local spillover data are cleaned by user ID; cloud spillover cleanup has a durable ID-only retry queue.

The migration is additive and keeps existing user records as `role=user`, `status=active`, and session version `0`. To roll back the release, revert the backend first. Do not drop the audit table or new columns if they contain operational records; the backend can run with those additions present. JWT revocation depends on the deployed auth middleware checking `auth_session_version`: rolling back to middleware that does not check that column removes immediate revocation, and dropping the column while newer middleware is deployed can make authentication fail. Keep the column until all deployed middleware versions no longer depend on it.

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
