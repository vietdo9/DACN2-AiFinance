-- ==============================================================================
-- FINWISE DATABASE SCHEMA CHO SUPABASE (POSTGRESQL)
-- Chạy đoạn script này trong mục SQL Editor trên Dashboard Supabase của bạn!
-- ==============================================================================

-- Bật extension tạo UUID
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. BẢNG NGƯỜI DÙNG (USERS)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(150),
    avatar_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. BẢNG VÍ TIỀN (WALLETS)
CREATE TABLE IF NOT EXISTS wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(100) NOT NULL DEFAULT 'Ví Chính',
    balance NUMERIC(15, 2) DEFAULT 0.00 NOT NULL,
    currency VARCHAR(10) DEFAULT 'VND' NOT NULL,
    color VARCHAR(20) DEFAULT '#4F46E5',
    is_default BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. BẢNG DANH MỤC THU CHI (CATEGORIES - ĐỒNG BỘ 10 NHÃN PHOBERT)
CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(20) NOT NULL CHECK (type IN ('expense', 'income')),
    icon VARCHAR(50) DEFAULT 'category',
    color VARCHAR(20) DEFAULT '#6B7280'
);

-- Nạp sẵn 10 Danh mục chuẩn tương thích 100% với PhoBERT AI
INSERT INTO categories (code, name, type, icon, color) VALUES
('AN_UONG', 'Ăn uống & Cà phê', 'expense', 'restaurant', '#F59E0B'),
('DI_LAI', 'Di chuyển & Đi lại', 'expense', 'directions_car', '#3B82F6'),
('MUA_SAM', 'Mua sắm & Đồ dùng', 'expense', 'shopping_bag', '#EC4899'),
('HOA_DON', 'Hóa đơn & Tiện ích', 'expense', 'receipt_long', '#8B5CF6'),
('NHA_O', 'Nhà ở & Tiền trọ', 'expense', 'home', '#10B981'),
('GIAI_TRI', 'Giải trí & Sở thích', 'expense', 'sports_esports', '#6366F1'),
('SUC_KHOE', 'Sức khỏe & Y tế', 'expense', 'medical_services', '#EF4444'),
('HOC_TAP', 'Học tập & Phát triển', 'expense', 'school', '#14B8A6'),
('TIET_KIEM_DAU_TU', 'Tiết kiệm & Đầu tư', 'expense', 'savings', '#06B6D4'),
('THU_NHAP', 'Thu nhập & Lương', 'income', 'payments', '#22C55E')
ON CONFLICT (code) DO NOTHING;

-- 4. BẢNG GIAO DỊCH THU CHI (TRANSACTIONS)
CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
    wallet_id UUID REFERENCES wallets(id) ON DELETE SET NULL,
    category_code VARCHAR(50) REFERENCES categories(code) ON DELETE RESTRICT,
    amount NUMERIC(15, 2) NOT NULL,
    type VARCHAR(20) NOT NULL CHECK (type IN ('expense', 'income')),
    note TEXT,
    transaction_date DATE DEFAULT CURRENT_DATE NOT NULL,
    ai_predicted BOOLEAN DEFAULT FALSE,
    ai_confidence NUMERIC(5, 4),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 5. BẢNG HẠN MỨC NGÂN SÁCH (BUDGETS)
CREATE TABLE IF NOT EXISTS budgets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
    category_code VARCHAR(50) REFERENCES categories(code) ON DELETE CASCADE,
    amount_limit NUMERIC(15, 2) NOT NULL,
    month INTEGER NOT NULL,
    year INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(user_id, category_code, month, year)
);

-- Tạo Index tăng tốc độ truy vấn
CREATE INDEX IF NOT EXISTS idx_transactions_user_date ON transactions(user_id, transaction_date DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category_code);
CREATE INDEX IF NOT EXISTS idx_wallets_user ON wallets(user_id);

-- Cho phép Backend Node.js đọc và ghi dữ liệu tự do (Disable RLS)
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
ALTER TABLE wallets DISABLE ROW LEVEL SECURITY;
ALTER TABLE transactions DISABLE ROW LEVEL SECURITY;
ALTER TABLE categories DISABLE ROW LEVEL SECURITY;
ALTER TABLE budgets DISABLE ROW LEVEL SECURITY;

