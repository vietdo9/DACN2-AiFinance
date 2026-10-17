const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const { supabase, isSupabaseConfigured } = require('../config/supabase');
const { verifyToken } = require('../middlewares/auth');
const AiService = require('../services/aiService');
const localStore = require('../config/localStore');

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
    { code: 'TIET_KIEM_DAU_TU', name: 'Tiết kiệm & Đầu tư', type: 'expense', icon: 'savings', color: '#06B6D4' },
    { code: 'THU_NHAP', name: 'Thu nhập & Lương', type: 'income', icon: 'payments', color: '#22C55E' }
];

// 1. Lấy danh mục chuẩn
router.get('/categories', async (req, res) => {
    try {
        if (isSupabaseConfigured()) {
            try {
                const { data: categories, error } = await supabase
                    .from('categories')
                    .select('*')
                    .order('id', { ascending: true });

                if (!error && categories && categories.length > 0) {
                    return res.json({ success: true, data: categories });
                }
            } catch (_) {}
        }
        return res.json({ success: true, data: DEFAULT_CATEGORIES });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

// 2. Lấy danh sách giao dịch của NGƯỜI DÙNG HIỆN TẠI (Cách ly 100% theo user_id)
router.get('/', verifyToken, async (req, res) => {
    try {
        const { limit = 50, type, category } = req.query;

        // 1. Thử lấy từ Supabase
        if (isSupabaseConfigured()) {
            try {
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
                if (!error && transactions) {
                    return res.json({ success: true, data: transactions });
                }
            } catch (_) {}
        }

        // 2. Lấy từ Local Store cách ly theo đúng req.user.id
        const userTxs = localStore.getTransactions(req.user.id, { type, category, limit });
        return res.json({ success: true, data: userTxs });
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
                console.warn('[!] Không thể gọi PhoBERT AI tự phân loại:', aiErr.message);
                category_code = type === 'income' ? 'THU_NHAP' : 'AN_UONG';
            }
        }

        if (!category_code) {
            category_code = type === 'income' ? 'THU_NHAP' : 'AN_UONG';
        }

        const catInfo = DEFAULT_CATEGORIES.find(c => c.code === category_code) || {
            name: category_code,
            icon: 'category',
            color: '#6B7280'
        };

        const numericAmount = parseFloat(amount);
        const txDate = transaction_date || new Date().toISOString().split('T')[0];
        let savedTx = null;

        // 1. Thử lưu vào Supabase
        if (isSupabaseConfigured()) {
            try {
                const { data: transaction, error: txError } = await supabase
                    .from('transactions')
                    .insert([{
                        user_id: req.user.id,
                        wallet_id: wallet_id || null,
                        category_code,
                        amount: numericAmount,
                        type,
                        note: note || '',
                        transaction_date: txDate,
                        ai_predicted,
                        ai_confidence
                    }])
                    .select()
                    .single();

                if (!txError && transaction) {
                    savedTx = {
                        ...transaction,
                        category_name: catInfo.name,
                        categories: catInfo
                    };

                    // Cập nhật số dư ví
                    if (wallet_id) {
                        const delta = type === 'income' ? numericAmount : -numericAmount;
                        await supabase.rpc('update_wallet_balance', {
                            p_wallet_id: wallet_id,
                            p_amount: delta
                        }).catch(() => {});
                    }
                }
            } catch (_) {}
        }

        // 2. Lưu vào Local Store nếu Supabase chưa có
        if (!savedTx) {
            savedTx = {
                id: crypto.randomUUID ? crypto.randomUUID() : `tx-${Date.now()}`,
                user_id: req.user.id,
                wallet_id: wallet_id || null,
                category_code,
                category_name: catInfo.name,
                categories: catInfo,
                amount: numericAmount,
                type,
                note: note || '',
                transaction_date: txDate,
                ai_predicted,
                ai_confidence,
                created_at: new Date().toISOString()
            };

            localStore.addTransaction(savedTx);

            // Cập nhật số dư ví trong local store
            const userWallets = localStore.getWallets(req.user.id);
            const targetWallet = wallet_id 
                ? userWallets.find(w => w.id === wallet_id) 
                : userWallets[0];

            if (targetWallet) {
                const delta = type === 'income' ? numericAmount : -numericAmount;
                localStore.updateWalletBalance(targetWallet.id, delta);
            }
        }

        return res.status(201).json({
            success: true,
            message: 'Tạo giao dịch thành công' + (ai_predicted ? ' (PhoBERT tự động phân loại)' : ''),
            data: savedTx
        });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

// 4. Xóa giao dịch (Chỉ được xóa giao dịch của chính mình)
router.delete('/:id', verifyToken, async (req, res) => {
    try {
        const { id } = req.params;

        if (isSupabaseConfigured()) {
            try {
                const { error } = await supabase
                    .from('transactions')
                    .delete()
                    .eq('id', id)
                    .eq('user_id', req.user.id);

                if (!error) {
                    return res.json({ success: true, message: 'Đã xóa giao dịch thành công' });
                }
            } catch (_) {}
        }

        localStore.deleteTransaction(id, req.user.id);
        return res.json({ success: true, message: 'Đã xóa giao dịch thành công' });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

module.exports = router;
