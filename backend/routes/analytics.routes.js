const express = require('express');
const router = express.Router();
const { supabase, isSupabaseConfigured } = require('../config/supabase');
const { verifyToken } = require('../middlewares/auth');
const localStore = require('../config/localStore');

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
    'THU_NHAP': { name: 'Thu nhập & Lương', color: '#22C55E' },
    'TIEN_CHUYEN_DEN': { name: 'Nhận Chuyển Khoản', color: '#10B981' },
    'THU_KHAC': { name: 'Thu Khác & Thưởng', color: '#14B8A6' }
};

// Lấy số liệu thống kê tổng quan (Dashboard Summary) độc lập cho từng user_id
router.get('/summary', verifyToken, async (req, res) => {
    try {
        const now = new Date();
        const firstDayOfMonth = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split('T')[0];

        let wallets = [];
        let txs = [];

        // 1. Thử lấy từ Supabase theo req.user.id
        if (isSupabaseConfigured()) {
            try {
                const { data: sbWallets } = await supabase
                    .from('wallets')
                    .select('balance')
                    .eq('user_id', req.user.id);
                if (sbWallets) wallets = sbWallets;

                const { data: sbTxs } = await supabase
                    .from('transactions')
                    .select('amount, type, category_code, transaction_date')
                    .eq('user_id', req.user.id)
                    .gte('transaction_date', firstDayOfMonth);
                if (sbTxs) txs = sbTxs;
            } catch (_) {}
        }

        // 2. Nếu Supabase không có, lấy từ Local Store của đúng user_id đó
        if (wallets.length === 0) {
            wallets = localStore.getWallets(req.user.id);
        }
        if (txs.length === 0) {
            const allUserTxs = localStore.getTransactions(req.user.id);
            txs = allUserTxs.filter(t => t.transaction_date >= firstDayOfMonth);
        }

        // Tính tổng số dư các ví của user
        const totalBalance = (wallets || []).reduce((acc, w) => acc + parseFloat(w.balance || 0), 0);

        // Tính thu - chi trong tháng
        let income = 0;
        let expense = 0;
        const catMap = {};

        (txs || []).forEach(t => {
            const amt = parseFloat(t.amount || 0);
            if (t.type === 'income') {
                income += amt;
            } else {
                expense += amt;
                const cCode = t.category_code || 'AN_UONG';
                catMap[cCode] = (catMap[cCode] || 0) + amt;
            }
        });

        // Tính cơ cấu chi tiêu cho biểu đồ
        const categoryBreakdown = Object.keys(catMap).map(k => {
            const catMeta = CATEGORY_NAMES[k] || { name: k, color: '#6B7280' };
            return {
                category_code: k,
                category_name: catMeta.name,
                color: catMeta.color,
                total: catMap[k],
                percentage: expense > 0 ? Math.round((catMap[k] / expense) * 1000) / 10 : 0
            };
        });

        return res.json({
            success: true,
            data: {
                total_balance: totalBalance,
                this_month_income: income,
                this_month_expense: expense,
                expense_by_category: categoryBreakdown
            }
        });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

module.exports = router;
