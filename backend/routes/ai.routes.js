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

// 4. Dự báo chi tiêu ĐỘC LẬP RIÊNG BIỆT cho từng tài khoản (LSTM)
function toLocalDateStr(d) {
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

function formatDayMonth(d) {
    const day = String(d.getDate()).padStart(2, '0');
    const month = String(d.getMonth() + 1).padStart(2, '0');
    return `${day}/${month}`;
}

router.get('/user-forecast', verifyToken, async (req, res) => {
    try {
        const isDemoRequested = req.query.demo === 'true';

        const now = new Date();
        const todayStr = toLocalDateStr(now);

        // 1. Chu kỳ Tuần này (Thứ Hai -> Chủ Nhật) & Tuần trước
        const dayOfWeek = now.getDay(); // 0 là Chủ Nhật, 1 là Thứ Hai, ..., 6 là Thứ Bảy
        const diffToMonday = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;

        const startOfThisWeek = new Date(now.getFullYear(), now.getMonth(), now.getDate() + diffToMonday);
        const endOfThisWeek = new Date(now.getFullYear(), now.getMonth(), now.getDate() + diffToMonday + 6);

        const startOfLastWeek = new Date(now.getFullYear(), now.getMonth(), now.getDate() + diffToMonday - 7);
        const endOfLastWeek = new Date(now.getFullYear(), now.getMonth(), now.getDate() + diffToMonday - 1);

        const startOfThisWeekStr = toLocalDateStr(startOfThisWeek);
        const endOfThisWeekStr = toLocalDateStr(endOfThisWeek);
        const startOfLastWeekStr = toLocalDateStr(startOfLastWeek);
        const endOfLastWeekStr = toLocalDateStr(endOfLastWeek);

        // Chu kỳ Tháng này & Tháng trước
        const startOfThisMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        const startOfLastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        const endOfLastMonth = new Date(now.getFullYear(), now.getMonth(), 0);

        const startOfThisMonthStr = toLocalDateStr(startOfThisMonth);
        const startOfLastMonthStr = toLocalDateStr(startOfLastMonth);
        const endOfLastMonthStr = toLocalDateStr(endOfLastMonth);

        const thisWeekLabel = `${formatDayMonth(startOfThisWeek)} - ${formatDayMonth(endOfThisWeek)}`;
        const lastWeekLabel = `${formatDayMonth(startOfLastWeek)} - ${formatDayMonth(endOfLastWeek)}`;
        const thisMonthLabel = `Tháng ${now.getMonth() + 1}`;
        const lastMonthLabel = `Tháng ${now.getMonth() === 0 ? 12 : now.getMonth()}`;

        const dayNames = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];

        // Lấy các giao dịch chi tiêu từ mốc sớm nhất giữa đầu tháng trước và tuần trước
        const earliestDateStr = startOfLastMonthStr < startOfLastWeekStr ? startOfLastMonthStr : startOfLastWeekStr;

        let txs = [];

        // 1. Lấy từ Supabase
        if (isSupabaseConfigured()) {
            try {
                const { data: sbTxs } = await supabase
                    .from('transactions')
                    .select('amount, transaction_date')
                    .eq('user_id', req.user.id)
                    .eq('type', 'expense')
                    .gte('transaction_date', earliestDateStr)
                    .order('transaction_date', { ascending: true });

                if (sbTxs && sbTxs.length > 0) {
                    txs = sbTxs;
                }
            } catch (_) {}
        }

        // 2. Lấy từ Local Store nếu chưa có
        if (txs.length === 0) {
            const allTxs = localStore.getTransactions(req.user.id, { type: 'expense' });
            txs = allTxs.filter(t => t.transaction_date >= earliestDateStr);
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
            const demoAmounts = [180000, 210000, 160000, 195000, 240000, 310000, 280000];
            const demoWeekDays = [];
            let demoThisWeekTotal = 0;

            for (let i = 0; i < 7; i++) {
                const curDate = new Date(startOfThisWeek.getFullYear(), startOfThisWeek.getMonth(), startOfThisWeek.getDate() + i);
                const curDateStr = toLocalDateStr(curDate);
                const isPast = curDateStr < todayStr;
                const isToday = curDateStr === todayStr;
                const amt = demoAmounts[i];
                demoThisWeekTotal += amt;

                demoWeekDays.push({
                    date: curDateStr,
                    day_name: dayNames[i],
                    day_label: formatDayMonth(curDate),
                    is_past_or_today: isPast || isToday,
                    amount: amt,
                    is_predicted: !isPast
                });
            }

            const demoLastWeekTotal = 1530000;
            const weekDiff = demoThisWeekTotal - demoLastWeekTotal;
            const weekPercent = Math.round((weekDiff / demoLastWeekTotal) * 100);

            return res.json({
                success: true,
                has_enough_data: true,
                is_demo_data: true,
                data: {
                    predicted_next_7_days: demoAmounts,
                    week_days_detail: demoWeekDays,
                    total_forecast: demoThisWeekTotal,
                    average_daily_forecast: Math.round(demoThisWeekTotal / 7),
                    warning_level: 'AN_TOAN',
                    message: 'Dòng tiền tuần này duy trì mức chi tiêu cân bằng và ổn định tương đương với tuần trước.',
                    last_7_days_total: demoLastWeekTotal,
                    week_diff_amount: weekDiff,
                    week_diff_percent: weekPercent,
                    this_week_label: thisWeekLabel,
                    last_week_label: lastWeekLabel,
                    this_month_spent: 3100000,
                    this_month_projected: 5850000,
                    last_month_total: 6200000,
                    month_diff_percent: -6,
                    this_month_label: thisMonthLabel,
                    last_month_label: lastMonthLabel,
                    engine: 'Self-trained 2-Layer LSTM Neural Network (24/7 Cloud In-Memory Engine)'
                }
            });
        }

        // Gom các giao dịch THẬT của người dùng theo ngày
        const mapByDate = {};
        let lastWeekTotal = 0;
        let lastMonthTotal = 0;
        let thisMonthSpent = 0;

        txs.forEach(t => {
            const d = t.transaction_date;
            const amt = parseFloat(t.amount || 0);
            mapByDate[d] = (mapByDate[d] || 0) + amt;

            if (d >= startOfLastWeekStr && d <= endOfLastWeekStr) {
                lastWeekTotal += amt;
            }
            if (d >= startOfLastMonthStr && d <= endOfLastMonthStr) {
                lastMonthTotal += amt;
            }
            if (d >= startOfThisMonthStr) {
                thisMonthSpent += amt;
            }
        });

        // Tính toán dự phóng tháng này
        const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
        const daysPassed = Math.max(1, now.getDate());
        const remainingDays = Math.max(0, daysInMonth - daysPassed);
        const dailyRateThisMonth = thisMonthSpent / daysPassed;
        const thisMonthProjected = Math.round(thisMonthSpent + (dailyRateThisMonth * remainingDays));
        const monthDiffPercent = lastMonthTotal > 0
            ? Math.round(((thisMonthProjected - lastMonthTotal) / lastMonthTotal) * 100)
            : 0;

        // Tạo mảng chuỗi thời gian 30 ngày gần nhất
        const dailyExpenses = [];
        for (let i = 29; i >= 0; i--) {
            const d = new Date();
            d.setDate(d.getDate() - i);
            const k = toLocalDateStr(d);
            dailyExpenses.push(mapByDate[k] || 0);
        }

        const context = {
            last7DaysTotal: lastWeekTotal,
            lastMonthTotal,
            thisMonthSpent,
            thisMonthProjected,
            monthDiffPercent
        };

        // Gọi AI Service với chuỗi chi tiêu THỰC TẾ và bối cảnh Tuần/Tháng
        const forecastResult = await AiService.forecastExpenses(dailyExpenses, context);

        // Xây dựng chi tiết 7 ngày trọn vẹn cho TUẦN NÀY (Thứ Hai -> Chủ Nhật)
        const weekDaysDetail = [];
        let thisWeekActualSpent = 0;
        let thisWeekProjectedTotal = 0;
        const final7DaysAmounts = [];

        for (let i = 0; i < 7; i++) {
            const curDate = new Date(startOfThisWeek.getFullYear(), startOfThisWeek.getMonth(), startOfThisWeek.getDate() + i);
            const curDateStr = toLocalDateStr(curDate);
            const isPast = curDateStr < todayStr;
            const isToday = curDateStr === todayStr;
            const actualAmt = mapByDate[curDateStr] || 0;
            const predictedAmt = (forecastResult.predicted_next_7_days && forecastResult.predicted_next_7_days[i]) || 0;

            let dayAmt = 0;
            let isPred = false;

            if (isPast) {
                dayAmt = actualAmt;
                thisWeekActualSpent += actualAmt;
                isPred = false;
            } else if (isToday) {
                if (actualAmt > 0) {
                    dayAmt = actualAmt;
                    thisWeekActualSpent += actualAmt;
                    isPred = false;
                } else {
                    dayAmt = predictedAmt;
                    isPred = true;
                }
            } else {
                dayAmt = predictedAmt;
                isPred = true;
            }

            thisWeekProjectedTotal += dayAmt;
            final7DaysAmounts.push(dayAmt);

            weekDaysDetail.push({
                date: curDateStr,
                day_name: dayNames[i],
                day_label: formatDayMonth(curDate),
                is_past_or_today: isPast || isToday,
                amount: dayAmt,
                is_predicted: isPred
            });
        }

        const weekDiffAmount = thisWeekProjectedTotal - lastWeekTotal;
        const weekDiffPercent = lastWeekTotal > 0 ? Math.round((weekDiffAmount / lastWeekTotal) * 100) : 0;

        let warningLevel = 'AN_TOAN';
        let message = '';
        if (weekDiffPercent > 25) {
            warningLevel = 'CAO';
            message = `Cảnh báo: Chi tiêu tuần này dự kiến tăng ${weekDiffPercent}% so với tuần trước. Bạn nên lưu ý các khoản chi lớn và mua sắm!`;
        } else if (weekDiffPercent > 10) {
            warningLevel = 'TRUNG_BINH';
            message = `Chi tiêu tuần này có xu hướng tăng nhẹ +${weekDiffPercent}% so với tuần trước. Ngân sách vẫn đang được duy trì ổn định.`;
        } else if (weekDiffPercent < -5) {
            warningLevel = 'AN_TOAN';
            message = `Xu hướng rất tích cực: Tuần này dự kiến tiết kiệm hơn ${Math.abs(weekDiffPercent)}% so với tuần trước. Tiếp tục phát huy nhé!`;
        } else {
            warningLevel = 'AN_TOAN';
            message = `Dòng tiền tuần này duy trì mức chi tiêu cân bằng và ổn định tương đương với tuần trước.`;
        }

        return res.json({
            success: true,
            has_enough_data: true,
            is_demo_data: false,
            data: {
                predicted_next_7_days: final7DaysAmounts,
                week_days_detail: weekDaysDetail,
                total_forecast: thisWeekProjectedTotal,
                average_daily_forecast: Math.round(thisWeekProjectedTotal / 7),
                warning_level: warningLevel,
                message: message,
                last_7_days_total: lastWeekTotal,
                week_diff_amount: weekDiffAmount,
                week_diff_percent: weekDiffPercent,
                this_week_label: thisWeekLabel,
                last_week_label: lastWeekLabel,
                this_month_spent: thisMonthSpent,
                this_month_projected: thisMonthProjected,
                last_month_total: lastMonthTotal,
                month_diff_percent: monthDiffPercent,
                this_month_label: thisMonthLabel,
                last_month_label: lastMonthLabel,
                engine: forecastResult.engine
            }
        });
    } catch (err) {
        console.error('[!] Lỗi dự báo người dùng:', err.message);
        return res.status(500).json({ success: false, message: err.message });
    }
});

module.exports = router;
