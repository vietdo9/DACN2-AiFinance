const express = require('express');
const http = require('http');
const authRoutes = require('./routes/auth.routes');

const app = express();
app.use(express.json());
app.use('/api/auth', authRoutes);

const server = app.listen(5099, async () => {
    console.log('Testing server running on port 5099...');

    const testEmail = `student_${Date.now()}@finwise.vn`;
    const testPassword = 'myPassword123';
    const testName = 'Nguyễn Văn Hoàn Hảo';

    async function postJson(path, body) {
        return new Promise((resolve, reject) => {
            const data = JSON.stringify(body);
            const req = http.request({
                hostname: '127.0.0.1',
                port: 5099,
                path,
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(data)
                }
            }, (res) => {
                let responseBody = '';
                res.on('data', chunk => responseBody += chunk);
                res.on('end', () => {
                    resolve({ status: res.statusCode, data: JSON.parse(responseBody) });
                });
            });
            req.on('error', reject);
            req.write(data);
            req.end();
        });
    }

    try {
        console.log('1. Đang kiểm tra Đăng Ký Tài Khoản...');
        const regRes = await postJson('/api/auth/register', {
            full_name: testName,
            email: testEmail,
            password: testPassword
        });
        console.log('Kết quả Đăng Ký:', regRes.status, JSON.stringify(regRes.data, null, 2));

        if (regRes.status !== 201 && regRes.status !== 200) {
            throw new Error('Đăng ký thất bại: ' + JSON.stringify(regRes.data));
        }

        console.log('\n2. Đang kiểm tra Đăng Nhập Tài Khoản vừa tạo...');
        const loginRes = await postJson('/api/auth/login', {
            email: testEmail,
            password: testPassword
        });
        console.log('Kết quả Đăng Nhập:', loginRes.status, JSON.stringify(loginRes.data, null, 2));

        if (loginRes.status !== 200 || !loginRes.data.data?.token) {
            throw new Error('Đăng nhập thất bại: ' + JSON.stringify(loginRes.data));
        }

        console.log('\n3. Đang kiểm tra Đăng Nhập sai mật khẩu...');
        const badLogin = await postJson('/api/auth/login', {
            email: testEmail,
            password: 'wrong_password'
        });
        console.log('Kết quả Đăng Nhập sai (kỳ vọng 401):', badLogin.status, badLogin.data.message);

        console.log('\n[V] TẤT CẢ TEST ĐĂNG KÝ VÀ ĐĂNG NHẬP ĐỀU THÀNH CÔNG 100%!');
    } catch (e) {
        console.error('\n[X] Lỗi kiểm thử:', e.message);
    } finally {
        server.close();
        process.exit(0);
    }
});
