/**
 * Gemini Service - Cloud AI Fallback 24/7
 * Tự động bóc tách hóa đơn và phân loại chi tiêu hoàn toàn miễn phí qua Google Gemini API.
 */

const axios = require('axios');

const CATEGORIES_MAP = {
    'AN_UONG': 'Ăn uống & Cà phê',
    'DI_LAI': 'Di chuyển & Đi lại',
    'MUA_SAM': 'Mua sắm & Đồ dùng',
    'HOA_DON': 'Hóa đơn & Tiện ích',
    'NHA_O': 'Nhà ở & Tiền trọ',
    'GIAI_TRI': 'Giải trí & Sở thích',
    'SUC_KHOE': 'Sức khỏe & Y tế',
    'HOC_TAP': 'Học tập & Phát triển',
    'TIET_KIEM_DAU_TU': 'Tiết kiệm & Đầu tư',
    'THU_NHAP': 'Thu nhập & Lương'
};

const VALID_MODELS = [
    'gemini-2.5-flash',
    'gemini-flash-latest',
    'gemini-2.5-flash-lite',
    'gemini-2.5-pro',
    'gemini-pro-latest'
];

let cachedModel = 'gemini-2.5-flash';

class GeminiService {
    static getApiKey() {
        return process.env.GEMINI_API_KEY || '';
    }

    /**
     * Tự động dò tìm Model khả dụng cho API Key từ Google AI Studio
     */
    static async getBestModel(apiKey) {
        if (cachedModel && cachedModel !== 'gemini-1.5-flash-latest') return cachedModel;
        try {
            const listRes = await axios.get(
                `https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey}`,
                { timeout: 10000 }
            );
            const models = listRes.data?.models || [];
            const candidates = models.filter(m => m.supportedGenerationMethods?.includes('generateContent'));
            
            // Ưu tiên các model flash nhanh và nhẹ
            const preferred = candidates.find(m => m.name.includes('gemini-2.5-flash')) ||
                              candidates.find(m => m.name.includes('flash-latest')) ||
                              candidates.find(m => m.name.includes('flash')) ||
                              candidates[0];

            if (preferred) {
                cachedModel = preferred.name.replace('models/', '');
                console.log('[*] Tự động kích hoạt mô hình Gemini:', cachedModel);
                return cachedModel;
            }
        } catch (e) {
            console.log('[!] Không thể gọi ListModels, dùng mặc định gemini-2.5-flash:', e.message);
        }
        return 'gemini-2.5-flash';
    }

    /**
     * Bóc tách hóa đơn qua Google Gemini Vision (Tự động fallback các model 2026)
     */
    static async scanBill(fileBuffer, mimetype = 'image/jpeg') {
        const apiKey = this.getApiKey();
        if (!apiKey) {
            throw new Error('Chưa cấu hình GEMINI_API_KEY trên server.');
        }

        const base64Data = fileBuffer.toString('base64');
        const best = await this.getBestModel(apiKey);
        
        // Danh sách model ưu tiên theo chuẩn Google Gemini 2026
        const candidateModels = [...new Set([
            best,
            ...VALID_MODELS
        ])].filter(Boolean);

        const prompt = `
Bạn là chuyên gia AI bóc tách hóa đơn tài chính cá nhân tiếng Việt.
Hãy phân tích ảnh hóa đơn/bill và trích xuất dữ liệu trả về ĐÚNG cấu trúc JSON sau:
{
  "merchant": "Tên cửa hàng hoặc thương hiệu trên hóa đơn (ví dụ: MINIMART247, Circle K, Highlands Coffee,...)",
  "total_amount": 84500 (Số nguyên tổng tiền thanh toán cuối cùng, không có ký tự đ/VND/dấu phẩy),
  "date": "YYYY-MM-DD" (Ngày lập hóa đơn nếu tìm thấy, nếu không có để ngày hôm nay),
  "category_code": "MUA_SAM", (Một trong các mã: AN_UONG, DI_LAI, MUA_SAM, HOA_DON, NHA_O, GIAI_TRI, SUC_KHOE, HOC_TAP, TIET_KIEM_DAU_TU, THU_NHAP),
  "category_name": "Mua sắm & Đồ dùng",
  "confidence": 0.95,
  "raw_text": "Tóm tắt các món hàng và thông tin quan trọng trên hóa đơn"
}
Chỉ trả về duy nhất chuỗi JSON hợp lệ.
`;

        let lastError = null;

        for (const modelName of candidateModels) {
            try {
                const url = `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=${apiKey}`;
                const response = await axios.post(
                    url,
                    {
                        contents: [
                            {
                                parts: [
                                    { text: prompt },
                                    {
                                        inline_data: {
                                            mime_type: mimetype || 'image/jpeg',
                                            data: base64Data
                                        }
                                    }
                                ]
                            }
                        ],
                        generationConfig: {
                            response_mime_type: "application/json",
                            temperature: 0.1
                        }
                    },
                    {
                        headers: { 'Content-Type': 'application/json' },
                        timeout: 25000
                    }
                );

                const textOutput = response.data?.candidates?.[0]?.content?.parts?.[0]?.text;
                if (!textOutput) continue;

                cachedModel = modelName; // Ghi nhớ model hoạt động tốt
                const parsed = JSON.parse(textOutput);
                return {
                    success: true,
                    merchant: parsed.merchant || 'Hóa đơn mua sắm',
                    total_amount: parseInt(parsed.total_amount, 10) || 0,
                    date: parsed.date || new Date().toISOString().split('T')[0],
                    category_code: parsed.category_code || 'MUA_SAM',
                    category_name: CATEGORIES_MAP[parsed.category_code] || parsed.category_name || 'Mua sắm & Đồ dùng',
                    confidence: parsed.confidence || 0.9,
                    raw_text: parsed.raw_text || '',
                    engine: `Cloud Gemini (${modelName}) 24/7`
                };
            } catch (error) {
                lastError = error;
                console.log(`[!] Model ${modelName} thất bại (${error.response?.data?.error?.message || error.message}), thử model tiếp theo...`);
            }
        }

        console.error('[!] Tất cả các model Gemini đều thất bại:', lastError?.response?.data || lastError?.message);
        throw new Error('Lỗi xử lý AI bóc tách hóa đơn: ' + (lastError?.response?.data?.error?.message || lastError?.message));
    }

    /**
     * Phân loại giao dịch từ câu text tiếng Việt
     */
    static async classifyTransaction(text) {
        const apiKey = this.getApiKey();
        if (!apiKey) {
            return this.ruleBasedClassifier(text);
        }

        const prompt = `
Phân loại giao dịch chi tiêu/thu nhập sau vào một trong 10 danh mục:
Mã danh mục hợp lệ: AN_UONG, DI_LAI, MUA_SAM, HOA_DON, NHA_O, GIAI_TRI, SUC_KHOE, HOC_TAP, TIET_KIEM_DAU_TU, THU_NHAP.

Câu giao dịch: "${text}"

Trả về định dạng JSON:
{
  "category_code": "AN_UONG",
  "category_name": "Ăn uống & Cà phê",
  "confidence": 0.95
}
`;

        for (const modelName of VALID_MODELS) {
            try {
                const url = `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=${apiKey}`;
                const response = await axios.post(
                    url,
                    {
                        contents: [{ parts: [{ text: prompt }] }],
                        generationConfig: {
                            response_mime_type: "application/json",
                            temperature: 0.1
                        }
                    },
                    { headers: { 'Content-Type': 'application/json' }, timeout: 8000 }
                );

                const textOutput = response.data?.candidates?.[0]?.content?.parts?.[0]?.text;
                if (!textOutput) continue;

                const parsed = JSON.parse(textOutput);
                return {
                    category_code: parsed.category_code || 'MUA_SAM',
                    category_name: CATEGORIES_MAP[parsed.category_code] || parsed.category_name || 'Mua sắm & Đồ dùng',
                    confidence: parsed.confidence || 0.85,
                    engine: `Cloud Gemini (${modelName}) 24/7`
                };
            } catch (err) {
                // Thử model tiếp theo
            }
        }

        return this.ruleBasedClassifier(text);
    }

    /**
     * Phân loại dự phòng bằng tập quy tắc từ khóa
     */
    static ruleBasedClassifier(text) {
        const lower = text.toLowerCase();
        const keywords = {
            'AN_UONG': ['phở', 'cơm', 'bún', 'bánh', 'cà phê', 'cafe', 'trà', 'ăn', 'uống', 'pizza', 'kfc', 'lẩu', 'nướng', 'nhậu'],
            'DI_LAI': ['xăng', 'grab', 'be', 'gojek', 'taxi', 'xe buýt', 'gửi xe', 'vé xe', 'máy bay', 'rửa xe'],
            'MUA_SAM': ['shopee', 'lazada', 'tiki', 'siêu thị', 'mart', 'quần áo', 'giày', 'tạp hóa', 'chợ', 'mua'],
            'HOA_DON': ['điện', 'nước', 'internet', 'wifi', 'viettel', 'vina', 'mobi', 'tiện ích', 'hóa đơn'],
            'NHA_O': ['tiền nhà', 'tiền trọ', 'phòng trọ', 'chung cư', 'sửa nhà'],
            'GIAI_TRI': ['xem phim', 'cgv', 'game', 'netflix', 'spotify', 'karaoke', 'billiard', 'du lịch'],
            'SUC_KHOE': ['thuốc', 'khám', 'bệnh viện', 'nha khoa', 'gym', 'bác sĩ', 'yoga'],
            'HOC_TAP': ['sách', 'học phí', 'khóa học', 'udemy', 'bút', 'vở', 'trường'],
            'TIET_KIEM_DAU_TU': ['tiết kiệm', 'vàng', 'cổ phiếu', 'chứng khoán', 'đầu tư', 'gửi bank'],
            'THU_NHAP': ['lương', 'thưởng', 'thu nhập', 'hoa hồng', 'bán hàng', 'tiền về']
        };

        for (const [code, words] of Object.entries(keywords)) {
            if (words.some(w => lower.includes(w))) {
                return {
                    category_code: code,
                    category_name: CATEGORIES_MAP[code],
                    confidence: 0.8,
                    engine: 'Rule-based Keyword Matcher (Local Fallback)'
                };
            }
        }

        return {
            category_code: 'MUA_SAM',
            category_name: CATEGORIES_MAP['MUA_SAM'],
            confidence: 0.5,
            engine: 'Default Fallback'
        };
    }

    /**
     * Dự báo chuỗi thời gian 7 ngày (Khi LSTM offline)
     */
    static forecastExpenses(dailyExpenses) {
        if (!dailyExpenses || dailyExpenses.length === 0) {
            dailyExpenses = Array(30).fill(100000);
        }

        const n = dailyExpenses.length;
        const recent7 = dailyExpenses.slice(-7);
        const avgRecent = recent7.reduce((a, b) => a + b, 0) / 7;
        const avgAll = dailyExpenses.reduce((a, b) => a + b, 0) / n;

        const slope = (avgRecent - avgAll) / 14;
        const dayWeights = [0.95, 0.98, 1.02, 1.0, 1.15, 1.25, 1.1];
        const predicted = [];

        for (let i = 0; i < 7; i++) {
            let base = avgRecent + slope * (i + 1);
            let val = Math.max(0, Math.round(base * dayWeights[i]));
            predicted.push(val);
        }

        const totalForecast = predicted.reduce((a, b) => a + b, 0);
        const avgDaily = Math.round(totalForecast / 7);

        let warningLevel = 'AN_TOAN';
        let message = 'Mức chi tiêu dự báo 7 ngày tới ở mức ổn định và an toàn.';

        if (avgDaily > avgAll * 1.35) {
            warningLevel = 'NGUY_HIEM';
            message = 'Cảnh báo: Xu hướng chi tiêu 7 ngày tới tăng đột biến vượt 35% mức trung bình. Bạn nên thắt chặt chi tiêu!';
        } else if (avgDaily > avgAll * 1.15) {
            warningLevel = 'CANH_BAO';
            message = 'Lưu ý: Chi tiêu 7 ngày tới dự kiến tăng nhẹ so với các tuần trước.';
        }

        return {
            predicted_next_7_days: predicted,
            total_forecast: totalForecast,
            average_daily_forecast: avgDaily,
            warning_level: warningLevel,
            message: message,
            engine: 'Statistical Time-Series Forecaster (24/7 Fallback)'
        };
    }
}

module.exports = GeminiService;
