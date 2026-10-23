const express = require('express');
const router = express.Router();
const AiService = require('../services/aiService');
const { supabase, isSupabaseConfigured } = require('../config/supabase');
const { verifyToken } = require('../middlewares/auth');
const localStore = require('../config/localStore');

// 1. Kiểm tra trạng thái AI Service
router.get('/health', async (req, res) => {
    const health = await AiService.getHealth();
    return res.json({ success: true, ai_service: health });
});

// 1.1 Kiểm tra danh sách mô hình Gemini khả dụng
router.get('/gemini-models', async (req, res) => {
    try {
        const apiKey = process.env.GEMINI_API_KEY;
        if (!apiKey) return res.json({ success: false, message: 'Chưa có GEMINI_API_KEY' });
        const axios = require('axios');
        const listRes = await axios.get(`https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey}`, { timeout: 8000 });
        const models = (listRes.data?.models || []).map(m => ({
            name: m.name,
            methods: m.supportedGenerationMethods
        }));
        return res.json({ success: true, count: models.length, models });
    } catch (e) {
        return res.status(500).json({ success: false, error: e.response?.data || e.message });
    }
});

// 1.2 Kiểm tra gọi thử Gemini 2.5 Flash
router.get('/test-gemini-25', async (req, res) => {
    try {
        const apiKey = process.env.GEMINI_API_KEY;
        const axios = require('axios');
        const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;
        const response = await axios.post(url, {
            contents: [{ parts: [{ text: "Hãy trả về duy nhất chuỗi JSON {\"status\": \"ok\", \"message\": \"Gemini 2.5 Flash hoạt động hoàn hảo\"}" }] }],
            generationConfig: { response_mime_type: "application/json" }
        }, { timeout: 15000 });
        return res.json({ success: true, response: response.data?.candidates?.[0]?.content?.parts?.[0]?.text });
    } catch (e) {
        return res.status(500).json({ success: false, error: e.response?.data || e.message });
    }
});

// 2. Phân loại giao dịch (PhoBERT)
router.post('/classify', async (req, res) => {
    try {
        const { text } = req.body;
        if (!text || text.trim().length === 0) {
            return res.status(400).json({ success: false, message: 'Nội dung text không được để trống' });
        }

        const result = await AiService.classifyTransaction(text);
        return res.json({ success: true, data: result });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

// 3. Dự báo chi tiêu từ mảng 30 ngày (LSTM)
router.post('/forecast', async (req, res) => {
    try {
        const { daily_expenses } = req.body;
        if (!daily_expenses || !Array.isArray(daily_expenses) || daily_expenses.length < 30) {
            return res.status(400).json({
                success: false,
                message: 'Cần cung cấp mảng daily_expenses với ít nhất 30 ngày'
            });
        }

        const result = await AiService.forecastExpenses(daily_expenses);
        return res.json({ success: true, data: result });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

// 4. Dự báo chi tiêu ĐỘC LẬP RIÊNG BIỆT cho từng tài khoản (LSTM)
router.get('/user-forecast', verifyToken, async (req, res) => {
    try {
        const isDemoRequested = req.query.demo === 'true';

        // Lấy các giao dịch chi tiêu của chính tài khoản này trong 30 ngày qua
        const thirtyDaysAgo = new Date();
        thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
        const dateStr = thirtyDaysAgo.toISOString().split('T')[0];

        let txs = [];

        // 1. Lấy từ Supabase
        if (isSupabaseConfigured()) {
            try {
                const { data: sbTxs } = await supabase
                    .from('transactions')
                    .select('amount, transaction_date')
                    .eq('user_id', req.user.id)
                    .eq('type', 'expense')
                    .gte('transaction_date', dateStr)
                    .order('transaction_date', { ascending: true });

                if (sbTxs && sbTxs.length > 0) {
                    txs = sbTxs;
                }
            } catch (_) {}
        }

        // 2. Lấy từ Local Store nếu chưa có
        if (txs.length === 0) {
            const allTxs = localStore.getTransactions(req.user.id, { type: 'expense' });
            txs = allTxs.filter(t => t.transaction_date >= dateStr);
        }

        // KIỂM TRA: Nếu là tài khoản mới và chưa có giao dịch chi tiêu nào
        if (txs.length === 0 && !isDemoRequested) {
            return res.json({
                success: true,
                has_enough_data: false,
                message: 'Tài khoản của bạn chưa có lịch sử chi tiêu. Hãy thêm giao dịch để AI học thói quen chi tiêu của bạn!',
                data: null
            });
        }

        // Nếu người dùng chọn xem Demo
        if (isDemoRequested && txs.length === 0) {
            const demoSeries = [
                120000, 150000, 80000, 200000, 95000, 350000, 420000,
                110000, 130000, 160000, 90000, 250000, 310000, 500000,
                85000, 140000, 180000, 125000, 220000, 390000, 410000,
                150000, 95000, 135000, 170000, 210000, 380000, 450000,
                130000, 160000
            ];
            const forecastResult = await AiService.forecastExpenses(demoSeries);
            return res.json({
                success: true,
                has_enough_data: true,
                is_demo_data: true,
                data: {
                    historical_recent_days: demoSeries.slice(-7),
                    ...forecastResult
                }
            });
        }

        // Gom các giao dịch THẬT của người dùng theo ngày
        const mapByDate = {};
        txs.forEach(t => {
            const d = t.transaction_date;
            mapByDate[d] = (mapByDate[d] || 0) + parseFloat(t.amount || 0);
        });

        // Tạo mảng chuỗi thời gian 30 ngày từ dữ liệu thật của tài khoản
        const dailyExpenses = [];
        for (let i = 29; i >= 0; i--) {
            const d = new Date();
            d.setDate(d.getDate() - i);
            const k = d.toISOString().split('T')[0];
            dailyExpenses.push(mapByDate[k] || 0);
        }

        // Gọi AI Service với chuỗi chi tiêu THỰC TẾ của người dùng này
        const forecastResult = await AiService.forecastExpenses(dailyExpenses);

        return res.json({
            success: true,
            has_enough_data: true,
            is_demo_data: false,
            data: {
                historical_recent_days: dailyExpenses.slice(-7),
                ...forecastResult
            }
        });
    } catch (err) {
        console.error('[!] Lỗi dự báo người dùng:', err.message);
        return res.status(500).json({ success: false, message: err.message });
    }
});

module.exports = router;
