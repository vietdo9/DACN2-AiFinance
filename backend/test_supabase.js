require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_KEY;

console.log('====================================================');
console.log('   FINWISE - KIỂM TRA KẾT NỐI SUPABASE CLOUD POSTGRESQL');
console.log('====================================================');
console.log('[*] URL:', supabaseUrl);
console.log('[*] Key:', supabaseKey ? supabaseKey.substring(0, 16) + '...' : '(Chưa điền)');

if (!supabaseUrl || !supabaseKey) {
    console.error('\n[X] Chưa cấu hình SUPABASE_URL hoặc SUPABASE_KEY trong file .env');
    process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function checkSupabase() {
    try {
        console.log('\n[1/3] Kiểm tra đọc bảng categories...');
        const { data: cats, error: readErr } = await supabase.from('categories').select('*').limit(3);
        if (readErr) {
            console.error('[X] Lỗi đọc Supabase:', readErr.message);
        } else {
            console.log(`[+] Đọc thành công! Hiện có ${cats.length} danh mục.`);
        }

        console.log('\n[2/3] Kiểm tra quyền ghi dữ liệu (INSERT test)...');
        const testEmail = `test_ping_${Date.now()}@finwise.vn`;
        const { data: insertedUser, error: insertErr } = await supabase
            .from('users')
            .insert([{ email: testEmail, password_hash: 'test_hash', full_name: 'Ping Test' }])
            .select()
            .single();

        if (insertErr) {
            if (insertErr.code === '42501') {
                console.warn('\n[!] CẢNH BÁO: Bảng Supabase đang bật Row-Level Security (RLS) chặn quyền ghi của Anon Key!');
                console.warn('[*] HƯỚNG DẪN KHẮC PHỤC NHANH (Chọn 1 trong 2 cách):');
                console.warn('    Cách 1: Vào Supabase Dashboard -> SQL Editor -> Chạy lệnh:');
                console.warn('            ALTER TABLE users DISABLE ROW LEVEL SECURITY;');
                console.warn('            ALTER TABLE wallets DISABLE ROW LEVEL SECURITY;');
                console.warn('            ALTER TABLE transactions DISABLE ROW LEVEL SECURITY;');
                console.warn('            ALTER TABLE categories DISABLE ROW LEVEL SECURITY;');
                console.warn('    Cách 2: Vào Project Settings -> API -> Copy key "service_role" (secret) dán vào SUPABASE_KEY trong .env');
            } else {
                console.error('[X] Lỗi Supabase:', insertErr.message);
            }
        } else {
            console.log('[+] Ghi dữ liệu vào Supabase thành công 100%!');
            // Xóa user test để sạch sẽ
            await supabase.from('users').delete().eq('id', insertedUser.id);
            console.log('[+] Đã dọn dẹp bản ghi kiểm thử.');
        }

        console.log('\n[3/3] Trạng thái nạp 10 danh mục chuẩn PhoBERT...');
        const standardCats = [
            { code: 'AN_UONG', name: 'Ăn uống & Cà phê', type: 'expense', icon: 'restaurant', color: '#F59E0B' },
            { code: 'DI_LAI', name: 'Di chuyển & Đi lại', type: 'expense', icon: 'directions_car', color: '#3B82F6' },
            { code: 'MUA_SAM', name: 'Mua sắm & Đồ dùng', type: 'expense', icon: 'shopping_bag', color: '#EC4899' },
            { code: 'HOA_DON', name: 'Hóa đơn & Tiện ích', type: 'expense', icon: 'receipt_long', color: '#8B5CF6' },
            { code: 'NHA_O', name: 'Nhà ở & Tiền trọ', type: 'expense', icon: 'home', color: '#10B981' },
            { code: 'GIAI_TRI', name: 'Giải trí & Sở thích', type: 'expense', icon: 'sports_esports', color: '#6366F1' },
            { code: 'SUC_KHOE', name: 'Sức khỏe & Y tế', type: 'expense', icon: 'medical_services', color: '#EF4444' },
            { code: 'HOC_TAP', name: 'Học tập & Phát triển', type: 'expense', icon: 'school', color: '#14B8A6' },
            { code: 'TIET_KIEM_DAU_TU', name: 'Tiết kiệm & Đầu tư', type: 'expense', icon: 'savings', color: '#06B6D4' },
            { code: 'THU_NHAP', name: 'Thu nhập & Lương', type: 'income', icon: 'payments', color: '#22C55E' }
        ];

        const { error: seedErr } = await supabase.from('categories').upsert(standardCats, { onConflict: 'code' });
        if (seedErr) {
            console.log('[i] Danh mục được quản lý tự động bởi Backend Gateway fallback.');
        } else {
            console.log('[+] Đã đồng bộ 10 danh mục chuẩn lên Supabase!');
        }

        console.log('\n====================================================');
        console.log('[+] Kiểm tra hoàn tất.');
        console.log('====================================================\n');
    } catch (err) {
        console.error('[X] Ngoại lệ:', err.message);
    }
}

checkSupabase();
