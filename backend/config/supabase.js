const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_KEY;
const candidateServiceKey = process.env.SUPABASE_ADMIN_KEY || supabaseKey;

const isSupabaseConfigured = () => {
    return supabaseUrl && 
           supabaseKey && 
           !supabaseUrl.includes('your-project-id') && 
           !supabaseKey.includes('your-anon-or-service-role-key');
};

const isServiceRoleKeyConfigured = () => {
    if (String(candidateServiceKey || '').startsWith('sb_secret_')) return true;
    try {
        const payloadPart = String(candidateServiceKey || '').split('.')[1];
        if (!payloadPart) return false;
        const payload = JSON.parse(Buffer.from(payloadPart, 'base64url').toString('utf-8'));
        return payload.role === 'service_role';
    } catch (_) {
        return false;
    }
};

let supabase = null;
let supabaseService = null;

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

if (isSupabaseConfigured() && isServiceRoleKeyConfigured()) {
    try {
        supabaseService = createClient(supabaseUrl, candidateServiceKey, {
            auth: { persistSession: false, autoRefreshToken: false }
        });
    } catch (_) {}
}

module.exports = {
    supabase,
    supabaseService,
    isSupabaseConfigured,
    isServiceRoleKeyConfigured
};
