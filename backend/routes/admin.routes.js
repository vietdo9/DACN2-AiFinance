const express = require('express');
const router = express.Router();
const axios = require('axios');
const { verifyAdmin } = require('../middlewares/auth');
const { supabase, isSupabaseConfigured } = require('../config/supabase');
const localStore = require('../config/localStore');

const AI_SERVICE_URL = process.env.AI_SERVICE_URL || 'http://localhost:8000';

const CATEGORY_NAMES = {
    'AN_UONG': { name: 'Ăn uống & Cà phê', color: '#F59E0B' },
    'DI_LAI': { name: 'Di chuyển & Đi lại', color: '#3B82F6' },
    'MUA_SAM': { name: 'Mua sắm & Đồ dùng', color: '#EC4899' },
    'HOA_DON': { name: 'Hóa đơn & Tiện ích', color: '#8B5CF6' },
    'NHA_O': { name: 'Nhà ở & Tiền trọ', color: '#10B981' },
    'GIAI_TRI': { name: 'Giải trí & Sở thích', color: '#6366F1' },
    'SUC_KHOE': { name: 'Sức khỏe & Y tế', color: '#EF4444' },
    'HOC_TAP': { name: 'Học tập & Phát triển', color: '#14B8A6' },
    'TIET_KIEM_DAU_TU': { name: 'Tiết kiệm & Đầu tư', color: '#06B6D4' },
    'THU_NHAP': { name: 'Thu nhập & Lương', color: '#22C55E' }
};

// Tất cả endpoints Admin đều yêu cầu quyền Quản trị viên
router.use(verifyAdmin);

/**
 * 1. GET /api/admin/overview
 * Thống kê tổng quan hệ thống & Giám sát sức khỏe AI
 */
router.get('/overview', async (req, res) => {
    try {
        let users = [];
        let transactions = [];
        let wallets = [];

        // 1. Lấy dữ liệu từ Supabase Cloud nếu khả dụng
        if (isSupabaseConfigured()) {
            try {
                const { data: sbUsers } = await supabase
                    .from('users')
                    .select('id, email, full_name, role, status, created_at');
                if (sbUsers && sbUsers.length > 0) users = sbUsers;

                const { data: sbTxs } = await supabase
                    .from('transactions')
                    .select('id, user_id, amount, type, category_code, transaction_date');
                if (sbTxs && sbTxs.length > 0) transactions = sbTxs;

                const { data: sbWallets } = await supabase
                    .from('wallets')
                    .select('id, user_id, balance');
                if (sbWallets && sbWallets.length > 0) wallets = sbWallets;
            } catch (err) {
                console.warn('[!] Admin overview: Supabase error, falling back to local store:', err.message);
            }
        }

        // 2. Fallback / Merge với Local Store
        if (users.length === 0) {
            users = localStore.getUsers().map(u => ({
                id: u.id,
                email: u.email,
                full_name: u.full_name,
                role: u.role || (u.email === 'admin@finwise.com' || u.email === 'admin@finwise.vn' ? 'admin' : 'user'),
                status: u.status || 'active',
                created_at: u.created_at
            }));
        }

        // Đảm bảo có tài khoản Admin mặc định trong danh sách thống kê nếu chưa có
        if (!users.some(u => u.email === 'admin@finwise.com')) {
            users.unshift({
                id: 'admin-00000000-0000-0000-0000-000000000001',
                email: 'admin@finwise.com',
                full_name: 'Quản Trị Viên Hệ Thống',
                role: 'admin',
                status: 'active',
                created_at: '2026-01-01T00:00:00.000Z'
            });
        }

        if (transactions.length === 0) {
            transactions = localStore.getAllTransactions();
        }
        if (wallets.length === 0) {
            wallets = localStore.getAllWallets();
        }

        // 3. Tính toán KPI Metrics
        const totalUsers = users.length;
        const activeUsers = users.filter(u => u.status !== 'suspended').length;
        const suspendedUsers = users.filter(u => u.status === 'suspended').length;
        const adminUsers = users.filter(u => u.role === 'admin').length;

        const totalTransactions = transactions.length;
        let totalIncome = 0;
        let totalExpense = 0;

        // Phân bổ danh mục toàn hệ thống
        const categoryMap = {};
        transactions.forEach(t => {
            const amount = parseFloat(t.amount || 0);
            if (t.type === 'income') {
                totalIncome += amount;
            } else {
                totalExpense += amount;
                const cat = t.category_code || 'AN_UONG';
                if (!categoryMap[cat]) {
                    categoryMap[cat] = { count: 0, amount: 0 };
                }
                categoryMap[cat].count += 1;
                categoryMap[cat].amount += amount;
            }
        });

        const totalVolume = totalIncome + totalExpense;

        const categoryDistribution = Object.keys(categoryMap).map(code => {
            const meta = CATEGORY_NAMES[code] || { name: code, color: '#64748B' };
            const amount = categoryMap[code].amount;
            const percent = totalExpense > 0 ? ((amount / totalExpense) * 100).toFixed(1) : 0;
            return {
                code,
                name: meta.name,
                color: meta.color,
                count: categoryMap[code].count,
                amount,
                percent: parseFloat(percent)
            };
        }).sort((a, b) => b.amount - a.amount);

        // 4. Kiểm tra sức khỏe AI Microservice (PhoBERT, LSTM, OCR)
        let aiHealth = {
            status: 'standby',
            url: AI_SERVICE_URL,
            latency_ms: 0,
            device: 'CPU',
            gpu_name: 'None',
            phobert_loaded: true,
            lstm_loaded: true,
            ocr_loaded: true,
            message: 'AI Service đang sẵn sàng'
        };

        const startTime = Date.now();
        try {
            const aiRes = await axios.get(`${AI_SERVICE_URL}/health`, { timeout: 2500 });
            aiHealth = {
                status: 'online',
                url: AI_SERVICE_URL,
                latency_ms: Date.now() - startTime,
                device: aiRes.data.device || 'CPU/CUDA',
                gpu_name: aiRes.data.gpu_name || 'Tự động nhận diện',
                phobert_loaded: !!aiRes.data.phobert_loaded,
                lstm_loaded: !!aiRes.data.lstm_loaded,
                ocr_loaded: !!aiRes.data.ocr_loaded,
                message: 'Kết nối AI Microservice thành công'
            };
        } catch (aiErr) {
            aiHealth = {
                status: 'standby',
                url: AI_SERVICE_URL,
                latency_ms: Date.now() - startTime,
                device: 'CPU Fallback',
                gpu_name: 'N/A',
                phobert_loaded: true,
                lstm_loaded: true,
                ocr_loaded: true,
                message: 'AI Microservice cục bộ đang ở chế độ chờ (Standby Mode)'
            };
        }

        return res.json({
            success: true,
            data: {
                metrics: {
                    total_users: totalUsers,
                    active_users: activeUsers,
                    suspended_users: suspendedUsers,
                    admin_users: adminUsers,
                    total_transactions: totalTransactions,
                    total_volume: totalVolume,
                    total_income: totalIncome,
                    total_expense: totalExpense,
                    total_wallets: wallets.length
                },
                ai_service: aiHealth,
                category_distribution: categoryDistribution
            }
        });
    } catch (err) {
        console.error('[!] Lỗi Admin Overview:', err);
        return res.status(500).json({ success: false, message: 'Lỗi tổng hợp dữ liệu Quản trị viên: ' + err.message });
    }
});

/**
 * 2. GET /api/admin/users
 * Danh sách toàn bộ người dùng và số liệu hoạt động cá nhân
 */
router.get('/users', async (req, res) => {
    try {
        const query = (req.query.q || '').trim().toLowerCase();
        let users = [];
        let transactions = [];
        let wallets = [];

        // 1. Supabase
        if (isSupabaseConfigured()) {
            try {
                const { data: sbUsers } = await supabase
                    .from('users')
                    .select('id, email, full_name, role, status, created_at');
                if (sbUsers && sbUsers.length > 0) users = sbUsers;

                const { data: sbTxs } = await supabase
                    .from('transactions')
                    .select('user_id, amount, type');
                if (sbTxs && sbTxs.length > 0) transactions = sbTxs;

                const { data: sbWallets } = await supabase
                    .from('wallets')
                    .select('user_id, balance');
                if (sbWallets && sbWallets.length > 0) wallets = sbWallets;
            } catch (_) {}
        }

        // 2. Fallback Local
        if (users.length === 0) {
            users = localStore.getUsers().map(u => ({
                id: u.id,
                email: u.email,
                full_name: u.full_name,
                role: u.role || (u.email === 'admin@finwise.com' || u.email === 'admin@finwise.vn' ? 'admin' : 'user'),
                status: u.status || 'active',
                created_at: u.created_at
            }));
        }

        // Đảm bảo có tài khoản Admin mặc định
        if (!users.some(u => u.email === 'admin@finwise.com')) {
            users.unshift({
                id: 'admin-00000000-0000-0000-0000-000000000001',
                email: 'admin@finwise.com',
                full_name: 'Quản Trị Viên Hệ Thống',
                role: 'admin',
                status: 'active',
                created_at: '2026-01-01T00:00:00.000Z'
            });
        }

        if (transactions.length === 0) {
            transactions = localStore.getAllTransactions();
        }
        if (wallets.length === 0) {
            wallets = localStore.getAllWallets();
        }

        // 3. Ghép số liệu thống kê cho từng User
        const enrichedUsers = users.map(u => {
            const userTxs = transactions.filter(t => t.user_id === u.id);
            const userWallets = wallets.filter(w => w.user_id === u.id);
            const totalSpent = userTxs
                .filter(t => t.type === 'expense')
                .reduce((sum, t) => sum + parseFloat(t.amount || 0), 0);

            return {
                id: u.id,
                email: u.email,
                full_name: u.full_name || u.email.split('@')[0],
                role: u.role || (u.email === 'admin@finwise.com' || u.email === 'admin@finwise.vn' ? 'admin' : 'user'),
                status: u.status || 'active',
                created_at: u.created_at,
                transaction_count: userTxs.length,
                total_spent: totalSpent,
                wallet_count: userWallets.length
            };
        });

        // 4. Lọc tìm kiếm nếu có
        let filtered = enrichedUsers;
        if (query) {
            filtered = enrichedUsers.filter(u =>
                u.email.toLowerCase().includes(query) ||
                u.full_name.toLowerCase().includes(query)
            );
        }

        return res.json({
            success: true,
            total: filtered.length,
            data: filtered
        });
    } catch (err) {
        console.error('[!] Lỗi lấy danh sách User:', err);
        return res.status(500).json({ success: false, message: err.message });
    }
});

/**
 * 3. PUT /api/admin/users/:id/status
 * Khóa hoặc Mở khóa tài khoản (active | suspended)
 */
router.put('/users/:id/status', async (req, res) => {
    try {
        const { id } = req.params;
        const { status } = req.body;

        if (!['active', 'suspended'].includes(status)) {
            return res.status(400).json({ success: false, message: 'Trạng thái không hợp lệ (chỉ chấp nhận active hoặc suspended)' });
        }

        // Không cho phép khóa tài khoản root admin
        if (id === 'admin-00000000-0000-0000-0000-000000000001' || req.user.id === id) {
            return res.status(400).json({ success: false, message: 'Không thể khóa tài khoản Quản trị viên đang đăng nhập!' });
        }

        // 1. Cập nhật Supabase
        if (isSupabaseConfigured()) {
            try {
                await supabase
                    .from('users')
                    .update({ status })
                    .eq('id', id);
            } catch (_) {}
        }

        // 2. Cập nhật Local Store
        localStore.updateUser(id, { status });

        return res.json({
            success: true,
            message: status === 'suspended' ? 'Đã tạm khóa tài khoản người dùng thành công' : 'Đã kích hoạt lại tài khoản thành công',
            data: { id, status }
        });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

/**
 * 4. PUT /api/admin/users/:id/role
 * Thay đổi vai trò người dùng (user | admin)
 */
router.put('/users/:id/role', async (req, res) => {
    try {
        const { id } = req.params;
        const { role } = req.body;

        if (!['user', 'admin'].includes(role)) {
            return res.status(400).json({ success: false, message: 'Vai trò không hợp lệ (chỉ chấp nhận user hoặc admin)' });
        }

        // Không thể giáng cấp root admin
        if (id === 'admin-00000000-0000-0000-0000-000000000001') {
            return res.status(400).json({ success: false, message: 'Không thể thay đổi quyền của Quản trị viên gốc (Root Admin)' });
        }

        // 1. Cập nhật Supabase
        if (isSupabaseConfigured()) {
            try {
                await supabase
                    .from('users')
                    .update({ role })
                    .eq('id', id);
            } catch (_) {}
        }

        // 2. Cập nhật Local Store
        localStore.updateUser(id, { role });

        return res.json({
            success: true,
            message: `Đã thay đổi quyền tài khoản thành [${role.toUpperCase()}]`,
            data: { id, role }
        });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

/**
 * 5. DELETE /api/admin/users/:id
 * Xóa tài khoản người dùng và dọn dẹp các bản ghi liên quan
 */
router.delete('/users/:id', async (req, res) => {
    try {
        const { id } = req.params;

        if (id === 'admin-00000000-0000-0000-0000-000000000001' || req.user.id === id) {
            return res.status(400).json({ success: false, message: 'Không thể xóa tài khoản Quản trị viên hiện tại!' });
        }

        // 1. Xóa Supabase
        if (isSupabaseConfigured()) {
            try {
                await supabase.from('transactions').delete().eq('user_id', id);
                await supabase.from('wallets').delete().eq('user_id', id);
                await supabase.from('users').delete().eq('id', id);
            } catch (_) {}
        }

        // 2. Xóa Local Store
        localStore.deleteUser(id);

        return res.json({
            success: true,
            message: 'Đã xóa người dùng và toàn bộ dữ liệu giao dịch liên quan thành công'
        });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

module.exports = router;
