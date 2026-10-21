const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const multer = require('multer');
const { supabase, isSupabaseConfigured } = require('../config/supabase');
const { verifyToken } = require('../middlewares/auth');
const AiService = require('../services/aiService');
const localStore = require('../config/localStore');

const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 10 * 1024 * 1024 } // Tối đa 10MB
});

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
    { code: 'THU_NHAP', name: 'Thu nhập & Lương', type: 'income', icon: 'payments', color: '#22C55E' },
    { code: 'TIEN_CHUYEN_DEN', name: 'Nhận Chuyển Khoản', type: 'income', icon: 'account_balance_wallet', color: '#10B981' },
    { code: 'THU_KHAC', name: 'Thu Khác & Thưởng', type: 'income', icon: 'volunteer_activism', color: '#14B8A6' }
];

// Quét ảnh hóa đơn / Bill bằng AI (EasyOCR + PhoBERT)
router.post('/scan-bill', verifyToken, upload.single('bill'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ success: false, message: 'Vui lòng tải lên một ảnh hóa đơn (trường "bill")' });
        }

        const ocrResult = await AiService.scanBill(
            req.file.buffer,
            req.file.originalname,
            req.file.mimetype
        );

        return res.json({
            success: true,
            message: 'Quét hóa đơn thành công!',
            data: ocrResult
        });
    } catch (err) {
        console.error('[!] Lỗi khi quét hóa đơn:', err.message);
        return res.status(500).json({ success: false, message: err.message || 'Lỗi xử lý hóa đơn' });
    }
});


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

        // Nếu người dùng không chọn danh mục nhưng có nhập ghi chú
        if (!category_code && note && note.trim().length > 0) {
            // 1. Kiểm tra bộ nhớ cá nhân hóa của người dùng trước
            const userRule = localStore.findUserCategoryRule(req.user.id, note);
            if (userRule) {
                category_code = userRule.category_code;
                ai_predicted = true;
                ai_confidence = 1.0;
            } else {
                // 2. Nếu chưa từng gặp, gọi PhoBERT AI tự đoán
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
        }

        // Chuẩn hóa và làm sạch: đảm bảo type khớp với category_code
        if (type === 'income') {
            const incomeCodes = ['THU_NHAP', 'TIEN_CHUYEN_DEN', 'THU_KHAC'];
            if (!category_code || !incomeCodes.includes(category_code)) {
                category_code = 'THU_NHAP';
            }
        } else {
            if (!category_code || category_code === 'THU_NHAP') {
                category_code = 'AN_UONG';
            }
        }

        // Lưu vào bộ nhớ cá nhân hóa để học thói quen người dùng
        if (note && note.trim().length >= 2 && category_code) {
            localStore.saveUserCategoryRule(req.user.id, note, category_code);
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
                let { data: transaction, error: txError } = await supabase
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

                // Nếu lỗi Foreign Key do mã danh mục chưa có trong DB Supabase, fallback về THU_NHAP / AN_UONG
                if (txError && (txError.code === '23503' || (txError.message && txError.message.includes('foreign key')))) {
                    const fallbackCode = type === 'income' ? 'THU_NHAP' : 'AN_UONG';
                    const retry = await supabase
                        .from('transactions')
                        .insert([{
                            user_id: req.user.id,
                            wallet_id: wallet_id || null,
                            category_code: fallbackCode,
                            amount: numericAmount,
                            type,
                            note: note || '',
                            transaction_date: txDate,
                            ai_predicted,
                            ai_confidence
                        }])
                        .select()
                        .single();

                    if (!retry.error && retry.data) {
                        transaction = retry.data;
                        txError = null;
                        category_code = fallbackCode;
                    }
                }

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
                } else if (txError) {
                    console.error('[!] Lỗi insert Supabase transaction:', txError.message);
                }
            } catch (err) {
                console.error('[!] Exception khi insert Supabase transaction:', err.message);
            }
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

// 4. Cập nhật / Đổi danh mục giao dịch đã lưu (PUT /api/transactions/:id)
router.put('/:id', verifyToken, async (req, res) => {
    try {
        const { id } = req.params;
        const { amount, note, type, category_code, transaction_date } = req.body;

        // 1. Tìm giao dịch cũ để kiểm tra quyền và tính bù trừ số dư
        let oldTx = null;
        if (isSupabaseConfigured()) {
            try {
                const { data } = await supabase
                    .from('transactions')
                    .select('*')
                    .eq('id', id)
                    .eq('user_id', req.user.id)
                    .single();
                if (data) oldTx = data;
            } catch (_) {}
        }
        if (!oldTx) {
            oldTx = localStore.findTransactionById(id, req.user.id);
        }

        if (!oldTx) {
            return res.status(404).json({ success: false, message: 'Không tìm thấy giao dịch cần chỉnh sửa' });
        }

        const newAmount = amount !== undefined ? parseFloat(amount) : parseFloat(oldTx.amount);
        const newType = type || oldTx.type;
        let newCatCode = category_code || oldTx.category_code;
        const newNote = note !== undefined ? note : oldTx.note;
        const newDate = transaction_date || oldTx.transaction_date;

        // Chuẩn hóa và làm sạch: đảm bảo type khớp với category_code
        if (newType === 'income') {
            const incomeCodes = ['THU_NHAP', 'TIEN_CHUYEN_DEN', 'THU_KHAC'];
            if (!newCatCode || !incomeCodes.includes(newCatCode)) {
                newCatCode = 'THU_NHAP';
            }
        } else {
            if (!newCatCode || newCatCode === 'THU_NHAP') {
                newCatCode = 'AN_UONG';
            }
        }

        const catInfo = DEFAULT_CATEGORIES.find(c => c.code === newCatCode) || {
            name: newCatCode,
            icon: 'category',
            color: '#6B7280'
        };

        // Tính toán bù trừ chênh lệch số dư ví (delta)
        const oldEffect = oldTx.type === 'income' ? parseFloat(oldTx.amount) : -parseFloat(oldTx.amount);
        const newEffect = newType === 'income' ? newAmount : -newAmount;
        const delta = newEffect - oldEffect;

        let updatedTx = null;

        // Cập nhật Supabase (Lưu ý: Bảng transactions KHÔNG có cột updated_at)
        if (isSupabaseConfigured()) {
            try {
                let { data: tx, error } = await supabase
                    .from('transactions')
                    .update({
                        amount: newAmount,
                        type: newType,
                        category_code: newCatCode,
                        note: newNote,
                        transaction_date: newDate
                    })
                    .eq('id', id)
                    .eq('user_id', req.user.id)
                    .select()
                    .single();

                // Nếu lỗi Foreign Key do mã danh mục chưa có trong DB Supabase, fallback về THU_NHAP / AN_UONG
                if (error && (error.code === '23503' || (error.message && error.message.includes('foreign key')))) {
                    const fallbackCode = newType === 'income' ? 'THU_NHAP' : 'AN_UONG';
                    const retry = await supabase
                        .from('transactions')
                        .update({
                            amount: newAmount,
                            type: newType,
                            category_code: fallbackCode,
                            note: newNote,
                            transaction_date: newDate
                        })
                        .eq('id', id)
                        .eq('user_id', req.user.id)
                        .select()
                        .single();

                    if (!retry.error && retry.data) {
                        tx = retry.data;
                        error = null;
                        newCatCode = fallbackCode;
                    }
                }

                if (!error && tx) {
                    updatedTx = {
                        ...tx,
                        category_name: catInfo.name,
                        categories: catInfo
                    };

                    if (oldTx.wallet_id && delta !== 0) {
                        await supabase.rpc('update_wallet_balance', {
                            p_wallet_id: oldTx.wallet_id,
                            p_amount: delta
                        }).catch(() => {});
                    }
                } else if (error) {
                    console.error('[!] Supabase update transaction error:', error.message);
                }
            } catch (err) {
                console.error('[!] Supabase update exception:', err.message);
            }
        }

        // Cập nhật LocalStore
        const localUpdated = localStore.updateTransaction(id, req.user.id, {
            amount: newAmount,
            type: newType,
            category_code: newCatCode,
            category_name: catInfo.name,
            categories: catInfo,
            note: newNote,
            transaction_date: newDate
        });

        if (!updatedTx) {
            updatedTx = localUpdated;
            if (oldTx.wallet_id && delta !== 0) {
                localStore.updateWalletBalance(oldTx.wallet_id, delta);
            }
        }

        // HỌC TỪ PHẢN HỒI: Lưu quy tắc ưu tiên cho người dùng nếu có ghi chú
        if (newNote && newNote.trim().length >= 2 && newCatCode) {
            localStore.saveUserCategoryRule(req.user.id, newNote, newCatCode);
        }

        return res.json({
            success: true,
            message: 'Cập nhật giao dịch thành công!',
            data: updatedTx
        });
    } catch (err) {
        console.error('[!] Lỗi cập nhật giao dịch:', err.message);
        return res.status(500).json({ success: false, message: err.message });
    }
});

// 5. Xóa giao dịch (Chỉ được xóa giao dịch của chính mình)
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
