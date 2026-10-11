const express = require('express');
const router = express.Router();
const { supabase, isSupabaseConfigured } = require('../config/supabase');
const { verifyToken } = require('../middlewares/auth');
const AiService = require('../services/aiService');

// Danh sách 10 danh mục mặc định chuẩn PhoBERT
const DEFAULT_CATEGORIES = [
    { code: 'AN_UONG', name: 'Ăn uống & Cà phê', type: 'expense', icon: 'restaurant', color: '#F59E0B' },
    { code: 'DI_LAI', name: 'Di chuyển & Đi lại', type: 'expense', icon: 'directions_car', color: '#3B82F6' },
    { code: 'MUA_SAM', name: 'Mua sắm & Đồ dùng', type: 'expense', icon: 'shopping_bag', color: '#EC4899' },
    { code: 'HOA_DON', name: 'Hóa đơn & Tiện ích', type: 'expense', icon: 'receipt_long', color: '#8B5CF6' },
    { code: 'NHA_O', name: 'Nhà ở & Tiền trọ', type: 'expense', icon: 'home', color: '#10B981' },
    { code: 'GIAI_TRI', name: 'Giải trí & Sở thích', type: 'expense', icon: 'sports_esports', color: '#6366F1' },
    { code: 'SUC_KHOE', name: 'Sức khỏe & Y tế', type: 'expense', icon: 'medical_services', color: '#EF4444' },
    { code: 'HOC_TAP', name: 'Học tập & Phát triển', type: 'expense', icon: 'school', color: '#14B8A6' },
    { code: 'TIET_KIEM_DAU_TU', 'name': 'Tiết kiệm & Đầu tư', type: 'expense', icon: 'savings', color: '#06B6D4' },
    { code: 'THU_NHAP', 'name': 'Thu nhập & Lương', type: 'income', icon: 'payments', color: '#22C55E' }
];

// 1. Lấy danh mục chuẩn
router.get('/categories', async (req, res) => {
    try {
        if (!isSupabaseConfigured()) {
            return res.json({ success: true, data: DEFAULT_CATEGORIES });
        }

        const { data: categories, error } = await supabase
            .from('categories')
            .select('*')
            .order('id', { ascending: true });

        if (error || !categories || categories.length === 0) {
            return res.json({ success: true, data: DEFAULT_CATEGORIES });
        }

        return res.json({ success: true, data: categories });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

// 2. Lấy danh sách giao dịch của người dùng
router.get('/', verifyToken, async (req, res) => {
    try {
        const { limit = 50, type, category } = req.query;

        if (!isSupabaseConfigured()) {
            return res.json({
                success: true,
                data: [
                    {
                        id: 'tx-01',
                        amount: 45000,
                        type: 'expense',
                        category_code: 'AN_UONG',
                        category_name: 'Ăn uống & Cà phê',
                        note: 'Ăn phở bò sáng',
                        transaction_date: new Date().toISOString().split('T')[0],
                        ai_predicted: true
                    },
                    {
                        id: 'tx-02',
                        amount: 15000000,
                        type: 'income',
                        category_code: 'THU_NHAP',
                        category_name: 'Thu nhập & Lương',
                        note: 'Nhận lương tháng',
                        transaction_date: new Date().toISOString().split('T')[0],
                        ai_predicted: false
                    }
                ]
            });
        }

        let query = supabase
            .from('transactions')
            .select(`
                *,
                categories (name, icon, color),
                wallets (name)
            `)
            .eq('user_id', req.user.id)
            .order('transaction_date', { ascending: false })
            .limit(parseInt(limit));

        if (type) query = query.eq('type', type);
        if (category) query = query.eq('category_code', category);

        const { data: transactions, error } = await query;
        if (error) throw error;

        return res.json({ success: true, data: transactions });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

// 3. Tạo giao dịch mới (Hỗ trợ Tự động gọi PhoBERT phân loại nếu không truyền category_code)
router.post('/', verifyToken, async (req, res) => {
    try {
        const { wallet_id, amount, note, type, transaction_date } = req.body;
        let { category_code } = req.body;

        if (!amount || !type) {
            return res.status(400).json({ success: false, message: 'Số tiền và loại thu/chi là bắt buộc' });
        }

        let ai_predicted = false;
        let ai_confidence = null;

        // Nếu người dùng không chọn danh mục nhưng có nhập ghi chú, gọi PhoBERT AI tự đoán!
        if (!category_code && note && note.trim().length > 0) {
            try {
                const aiResult = await AiService.classifyTransaction(note);
                if (aiResult?.category_code) {
                    category_code = aiResult.category_code;
                    ai_predicted = true;
                    ai_confidence = aiResult.confidence;
                }
            } catch (aiErr) {
                console.warn('[!] Không thể gọi AI tự phân loại, dùng mặc định:', aiErr.message);
                category_code = type === 'income' ? 'THU_NHAP' : 'AN_UONG';
            }
        }

        if (!category_code) {
            category_code = type === 'income' ? 'THU_NHAP' : 'AN_UONG';
        }

        if (!isSupabaseConfigured()) {
            return res.status(201).json({
                success: true,
                message: 'Tạo giao dịch thành công (Demo Mode)',
                data: {
                    id: 'tx-new',
                    amount,
                    note,
                    type,
                    category_code,
                    ai_predicted,
                    ai_confidence,
                    transaction_date: transaction_date || new Date().toISOString().split('T')[0]
                }
            });
        }

        // 1. Thêm vào bảng transactions
        const { data: transaction, error: txError } = await supabase
            .from('transactions')
            .insert([{
                user_id: req.user.id,
                wallet_id: wallet_id || null,
                category_code,
                amount: parseFloat(amount),
                type,
                note: note || '',
                transaction_date: transaction_date || new Date().toISOString().split('T')[0],
                ai_predicted,
                ai_confidence
            }])
            .select()
            .single();

        if (txError) throw txError;

        // 2. Cập nhật số dư ví nếu có wallet_id
        if (wallet_id) {
            const balanceDelta = type === 'income' ? parseFloat(amount) : -parseFloat(amount);
            const { data: wallet } = await supabase.from('wallets').select('balance').eq('id', wallet_id).single();
            if (wallet) {
                const newBalance = parseFloat(wallet.balance) + balanceDelta;
                await supabase.from('wallets').update({ balance: newBalance }).eq('id', wallet_id);
            }
        }

        return res.status(201).json({
            success: true,
            message: 'Tạo giao dịch thành công',
            data: transaction
        });
    } catch (err) {
        console.error('[!] Lỗi tạo giao dịch:', err.message);
        return res.status(500).json({ success: false, message: err.message });
    }
});

// 4. Xóa giao dịch
router.delete('/:id', verifyToken, async (req, res) => {
    try {
        const { id } = req.params;

        if (!isSupabaseConfigured()) {
            return res.json({ success: true, message: 'Đã xóa giao dịch (Demo Mode)' });
        }

        const { error } = await supabase
            .from('transactions')
            .delete()
            .eq('id', id)
            .eq('user_id', req.user.id);

        if (error) throw error;

        return res.json({ success: true, message: 'Đã xóa giao dịch thành công' });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

module.exports = router;
