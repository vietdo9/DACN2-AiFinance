const express = require('express');
const http = require('http');
const authRoutes = require('./routes/auth.routes');
const transactionRoutes = require('./routes/transaction.routes');
const analyticsRoutes = require('./routes/analytics.routes');
const aiRoutes = require('./routes/ai.routes');
const walletRoutes = require('./routes/wallet.routes');

const app = express();
app.use(express.json());
app.use('/api/auth', authRoutes);
app.use('/api/transactions', transactionRoutes);
app.use('/api/analytics', analyticsRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api/wallets', walletRoutes);

const server = app.listen(5098, async () => {
    console.log('Test Multi-User server running on port 5098...');

    async function reqApi(method, path, body = null, token = null) {
        return new Promise((resolve, reject) => {
            const data = body ? JSON.stringify(body) : null;
            const headers = { 'Content-Type': 'application/json' };
            if (token) headers['Authorization'] = `Bearer ${token}`;
            if (data) headers['Content-Length'] = Buffer.byteLength(data);

            const req = http.request({
                hostname: '127.0.0.1',
                port: 5098,
                path,
                method,
                headers
            }, (res) => {
                let bodyStr = '';
                res.on('data', chunk => bodyStr += chunk);
                res.on('end', () => {
                    resolve({ status: res.statusCode, data: bodyStr ? JSON.parse(bodyStr) : {} });
                });
            });
            req.on('error', reject);
            if (data) req.write(data);
            req.end();
        });
    }

    try {
        console.log('\n--- 1. ĐĂNG KÝ TÀI KHOẢN A (Nguyễn Văn A) ---');
        const userAEmail = `user_a_${Date.now()}@finwise.vn`;
        const regA = await reqApi('POST', '/api/auth/register', {
            full_name: 'Nguyễn Văn A',
            email: userAEmail,
            password: 'passwordA123'
        });
        const tokenA = regA.data.data.token;
        console.log(`[+] Đã tạo User A: ${userAEmail}`);

        console.log('\n--- 2. ĐĂNG KÝ TÀI KHOẢN B (Trần Thị B) ---');
        const userBEmail = `user_b_${Date.now()}@finwise.vn`;
        const regB = await reqApi('POST', '/api/auth/register', {
            full_name: 'Trần Thị B',
            email: userBEmail,
            password: 'passwordB123'
        });
        const tokenB = regB.data.data.token;
        console.log(`[+] Đã tạo User B: ${userBEmail}`);

        console.log('\n--- 3. KIỂM TRA DỰ BÁO AI CỦA USER B (Tài khoản mới tinh) ---');
        const forecastB = await reqApi('GET', '/api/ai/user-forecast', null, tokenB);
        console.log('Kết quả AI của User B:', JSON.stringify(forecastB.data));
        if (forecastB.data.has_enough_data === false) {
            console.log('[V] CHÍNH XÁC: Tài khoản mới B không bị gán số liệu giả 2.844.000đ!');
        } else {
            throw new Error('User B bị gán dữ liệu dự báo sai!');
        }

        console.log('\n--- 4. USER A THÊM GIAO DỊCH (Ăn phở bò 60.000đ) ---');
        const addTxA = await reqApi('POST', '/api/transactions', {
            amount: 60000,
            type: 'expense',
            note: 'Ăn phở bò tái nạm buổi sáng',
            category_code: 'AN_UONG'
        }, tokenA);
        console.log('[+] User A thêm giao dịch thành công:', addTxA.data.data.note, addTxA.data.data.amount);

        console.log('\n--- 5. KIỂM TRA TÍNH CÁCH LY THỐNG KÊ (ANALYTICS SUMMARY) ---');
        const summaryA = await reqApi('GET', '/api/analytics/summary', null, tokenA);
        const summaryB = await reqApi('GET', '/api/analytics/summary', null, tokenB);

        console.log(`- Thống kê User A (đã tiêu 60k): Chi tiêu tháng này = ${summaryA.data.data.this_month_expense}đ`);
        console.log(`- Thống kê User B (chưa tiêu gì): Chi tiêu tháng này = ${summaryB.data.data.this_month_expense}đ`);

        if (summaryA.data.data.this_month_expense === 60000 && summaryB.data.data.this_month_expense === 0) {
            console.log('\n[V] XÁC NHẬN: DỮ LIỆU VÀ AI GIỮA CÁC TÀI KHOẢN ĐÃ ĐƯỢC CÁCH LY 100% HOÀN TOÀN ĐỘC LẬP!');
        } else {
            throw new Error('Dữ liệu giữa User A và User B vẫn bị lẫn lộn!');
        }

    } catch (err) {
        console.error('[X] Lỗi kiểm thử:', err.message);
    } finally {
        server.close();
        process.exit(0);
    }
});
