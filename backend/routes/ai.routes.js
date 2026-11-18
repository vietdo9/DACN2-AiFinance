const express = require('express');
const router = express.Router();
const AiService = require('../services/aiService');
const { supabase, isSupabaseConfigured } = require('../config/supabase');
const { verifyToken } = require('../middlewares/auth');
const localStore = require('../config/localStore');
const { getPeriod, buildForecast } = require('../services/spendingForecast');

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

// 1.2 Kiểm tra gọi thử Gemini 3.8 Flash
router.get('/test-gemini-25', async (req, res) => {
    try {
        const apiKey = process.env.GEMINI_API_KEY;
        const axios = require('axios');
        const modelName = req.query.model || 'gemini-3.8-flash';
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=${apiKey}`;
        const response = await axios.post(url, {
            contents: [{ parts: [{ text: "Hãy trả về duy nhất chuỗi JSON {\"status\": \"ok\", \"message\": \"Gemini 3.8 Flash hoạt động hoàn hảo\"}" }] }],
            generationConfig: { response_mime_type: "application/json" }
        }, { timeout: 15000 });
        return res.json({ success: true, model: modelName, response: response.data?.candidates?.[0]?.content?.parts?.[0]?.text });
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

// 4. Dự báo chi tiêu riêng cho tài khoản đang đăng nhập.
router.get('/user-forecast', verifyToken, async (req, res) => {
    try {
        const period = getPeriod();
        const demo = req.query.demo === 'true';
        let rows = [];
        let firstRecordedDate;
        const usingSupabase = !demo && isSupabaseConfigured();

        if (usingSupabase) {
            const pageSize = 500;
            for (let offset = 0; ; offset += pageSize) {
                const { data, error } = await supabase.from('transactions')
                    .select('amount, transaction_date')
                    .eq('user_id', req.user.id)
                    .eq('type', 'expense')
                    .gte('transaction_date', period.earliest)
                    .lte('transaction_date', period.latest)
                    .order('transaction_date', { ascending: true })
                    .order('id', { ascending: true })
                    .range(offset, offset + pageSize - 1);
                if (error) throw error;
                rows.push(...data);
                if (data.length < pageSize) break;
            }
            if (rows.length && rows[0].transaction_date > period.historyStart.toISOString().slice(0, 10)) {
                const { data, error } = await supabase.from('transactions')
                    .select('transaction_date')
                    .eq('user_id', req.user.id)
                    .eq('type', 'expense')
                    .lt('transaction_date', period.earliest)
                    .order('transaction_date', { ascending: true })
                    .limit(1);
                if (error) throw error;
                firstRecordedDate = data[0]?.transaction_date;
            }
        }

        if (!demo && (!usingSupabase || (rows.length === 0 && localStore.findUserById(req.user.id)))) {
            rows = localStore.getTransactions(req.user.id, { type: 'expense', limit: Number.MAX_SAFE_INTEGER });
        }

        return res.json(await buildForecast(rows, period, days => AiService.forecastExpenses(days), demo, firstRecordedDate));
    } catch (err) {
        console.error('[!] Lỗi dự báo người dùng:', err.message);
        return res.status(500).json({ success: false, message: 'Chưa thể tải dự báo chi tiêu. Vui lòng thử lại.' });
    }
});

module.exports = router;
