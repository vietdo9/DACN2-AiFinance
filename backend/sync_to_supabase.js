require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY);
const usersFile = path.join(__dirname, 'data/local_users.json');

async function sync() {
    console.log('====================================================');
    console.log('       FINWISE - ĐỒNG BỘ DỮ LIỆU LÊN SUPABASE');
    console.log('====================================================\n');

    if (!fs.existsSync(usersFile)) {
        console.log('[i] Không tìm thấy file dữ liệu người dùng cục bộ.');
        return;
    }

    const users = JSON.parse(fs.readFileSync(usersFile, 'utf-8'));
    console.log(`[*] Tìm thấy ${users.length} tài khoản trong máy tính. Đang đẩy lên Supabase...`);

    let successCount = 0;
    for (const u of users) {
        try {
            const { data, error } = await supabase
                .from('users')
                .upsert([{
                    id: u.id,
                    email: u.email,
                    password_hash: u.password_hash,
                    full_name: u.full_name,
                    created_at: u.created_at
                }], { onConflict: 'email' })
                .select();

            if (error) {
                console.error(`[X] Lỗi tài khoản ${u.email}:`, error.message);
            } else {
                console.log(`[+] Đã lưu thành công lên Supabase Cloud: ${u.email} (${u.full_name})`);
                successCount++;

                // Đồng bộ ví mặc định cho user
                try {
                    await supabase.from('wallets').insert([{
                        user_id: u.id,
                        name: 'Ví Tiền Mặt',
                        balance: 0,
                        is_default: true
                    }]);
                } catch (wErr) {
                    // Đã có ví thì bỏ qua
                }
            }
        } catch (err) {
            console.error(`[X] Ngoại lệ khi đồng bộ ${u.email}:`, err.message);
        }
    }

    console.log(`\n====================================================`);
    console.log(`[+] ĐÃ ĐỒNG BỘ THÀNH CÔNG ${successCount}/${users.length} TÀI KHOẢN LÊN SUPABASE WEB!`);
    console.log('====================================================\n');
}

sync();
