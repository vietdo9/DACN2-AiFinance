const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_KEY;

const isSupabaseConfigured = () => {
    return supabaseUrl && 
           supabaseKey && 
           !supabaseUrl.includes('your-project-id') && 
           !supabaseKey.includes('your-anon-or-service-role-key');
};

let supabase = null;

if (isSupabaseConfigured()) {
    try {
        supabase = createClient(supabaseUrl, supabaseKey);
        console.log('[+] Đã kết nối Supabase Client thành công!');
    } catch (err) {
        console.error('[!] Lỗi khi khởi tạo Supabase:', err.message);
    }
} else {
    console.warn('[!] Cảnh báo: SUPABASE_URL hoặc SUPABASE_KEY chưa được cấu hình trong file .env');
    console.warn('[i] Hướng dẫn: Đăng nhập https://supabase.com, tạo Project và dán URL + Key vào file .env');
}

module.exports = {
    supabase,
    isSupabaseConfigured
};
