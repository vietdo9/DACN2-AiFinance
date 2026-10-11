const express = require('express');
const router = express.Router();
const { supabase, isSupabaseConfigured } = require('../config/supabase');
const { verifyToken } = require('../middlewares/auth');

// Lấy số liệu thống kê tổng quan (Dashboard Summary)
router.get('/summary', verifyToken, async (req, res) => {
    try {
        if (!isSupabaseConfigured()) {
            return res.json({
                success: true,
                data: {
                    total_balance: 14500000,
                    this_month_income: 18000000,
                    this_month_expense: 3500000,
                    expense_by_category: [
                        { category_code: 'AN_UONG', category_name: 'Ăn uống & Cà phê', total: 1500000, percentage: 42.8, color: '#F59E0B' },
                        { category_code: 'DI_LAI', category_name: 'Di chuyển & Đi lại', total: 450000, percentage: 12.8, color: '#3B82F6' },
                        { category_code: 'HOA_DON', category_name: 'Hóa đơn & Tiện ích', total: 650000, percentage: 18.6, color: '#8B5CF6' },
                        { category_code: 'GIAI_TRI', category_name: 'Giải trí & Sở thích', total: 500000, percentage: 14.3, color: '#6366F1' },
                        { category_code: 'MUA_SAM', category_name: 'Mua sắm & Đồ dùng', total: 400000, percentage: 11.5, color: '#EC4899' }
                    ]
                }
            });
        }

        const now = new Date();
        const firstDayOfMonth = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split('T')[0];

        // Lấy tất cả ví
        const { data: wallets } = await supabase
            .from('wallets')
            .select('balance')
            .eq('user_id', req.user.id);

        const totalBalance = (wallets || []).reduce((acc, w) => acc + parseFloat(w.balance || 0), 0);

        // Lấy giao dịch trong tháng hiện tại
        const { data: txs } = await supabase
            .from('transactions')
            .select('amount, type, category_code')
            .eq('user_id', req.user.id)
            .gte('transaction_date', firstDayOfMonth);

        let income = 0;
        let expense = 0;
        const catMap = {};

        (txs || []).forEach(t => {
            const amt = parseFloat(t.amount);
            if (t.type === 'income') {
                income += amt;
            } else {
                expense += amt;
                catMap[t.category_code] = (catMap[t.category_code] || 0) + amt;
            }
        });

        const categoryBreakdown = Object.keys(catMap).map(k => ({
            category_code: k,
            total: catMap[k],
            percentage: expense > 0 ? Math.round((catMap[k] / expense) * 1000) / 10 : 0
        }));

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
