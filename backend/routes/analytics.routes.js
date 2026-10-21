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
        let allTxs = [];

        // 1. Thử lấy từ Supabase theo req.user.id
        if (isSupabaseConfigured()) {
            try {
                const { data: sbWallets } = await supabase
                    .from('wallets')
                    .select('id, name, balance, is_default')
                    .eq('user_id', req.user.id);
                if (sbWallets) wallets = sbWallets;

                // Lấy TẤT CẢ giao dịch của user để tính tổng số dư tích luỹ thực tế
                const { data: sbTxs } = await supabase
                    .from('transactions')
                    .select('amount, type, category_code, transaction_date')
                    .eq('user_id', req.user.id);
                if (sbTxs) allTxs = sbTxs;
            } catch (sbErr) {
                console.error('[!] Supabase analytics error:', sbErr.message);
            }
        }

        // 2. Nếu Supabase không có, lấy từ Local Store của đúng user_id đó
        if (wallets.length === 0) {
            wallets = localStore.getWallets(req.user.id);
        }
        if (allTxs.length === 0) {
            allTxs = localStore.getTransactions(req.user.id);
        }

        // Lọc các giao dịch trong tháng hiện tại
        const thisMonthTxs = allTxs.filter(t => t.transaction_date >= firstDayOfMonth);

        // Tính tổng tích lũy dòng tiền (All-time Income - All-time Expense)
        let allTimeIncome = 0;
        let allTimeExpense = 0;
        allTxs.forEach(t => {
            const amt = parseFloat(t.amount || 0);
            if (t.type === 'income') {
                allTimeIncome += amt;
            } else {
                allTimeExpense += amt;
            }
        });

        // TỔNG SỐ DƯ HIỆN TẠI (Net Balance):
        // Bằng: Tổng tất cả khoản Thu - Tổng tất cả khoản Chi
        const totalBalance = allTimeIncome - allTimeExpense;

        // Đồng bộ số dư thực tế này vào ví mặc định trong database để dữ liệu luôn nhất quán
        if (wallets.length > 0) {
            const defaultWallet = wallets.find(w => w.is_default) || wallets[0];
            if (defaultWallet) {
                defaultWallet.balance = totalBalance;
                if (isSupabaseConfigured() && defaultWallet.id) {
                    supabase.from('wallets')
                        .update({ balance: totalBalance })
                        .eq('id', defaultWallet.id)
                        .then(() => {})
                        .catch(() => {});
                }
            }
        }

        // Tính thu - chi trong tháng hiện tại
        let income = 0;
        let expense = 0;
        const catMap = {};

        thisMonthTxs.forEach(t => {
            const amt = parseFloat(t.amount || 0);
            if (t.type === 'income') {
                income += amt;
            } else {
                expense += amt;
            }
        });

        // Tính cơ cấu chi tiêu cho biểu đồ (lấy theo các giao dịch trong tháng, hoặc tất cả nếu tháng này chưa có chi)
        const expenseSourceTxs = (thisMonthTxs.filter(t => t.type === 'expense').length > 0)
            ? thisMonthTxs.filter(t => t.type === 'expense')
            : allTxs.filter(t => t.type === 'expense');

        const totalExpenseForChart = expenseSourceTxs.reduce((sum, t) => sum + parseFloat(t.amount || 0), 0);

        expenseSourceTxs.forEach(t => {
            const amt = parseFloat(t.amount || 0);
            const cCode = t.category_code || 'AN_UONG';
            catMap[cCode] = (catMap[cCode] || 0) + amt;
        });

        const categoryBreakdown = Object.keys(catMap).map(k => {
            const catMeta = CATEGORY_NAMES[k] || { name: k, color: '#6B7280' };
            return {
                category_code: k,
                category_name: catMeta.name,
                color: catMeta.color,
                total: catMap[k],
                percentage: totalExpenseForChart > 0 ? Math.round((catMap[k] / totalExpenseForChart) * 1000) / 10 : 0
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
