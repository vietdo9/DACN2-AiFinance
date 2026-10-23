/**
 * Gemini Service - Cloud AI Fallback 24/7
 * Tự động kích hoạt khi AI Service cục bộ (PhoBERT/LSTM/EasyOCR) tắt máy
 * Cung cấp khả năng bóc tách hóa đơn, phân loại danh mục và dự báo chi tiêu hoàn toàn miễn phí.
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

class GeminiService {
    static getApiKey() {
        return process.env.GEMINI_API_KEY || '';
    }

    /**
     * Bóc tách hóa đơn qua Gemini 1.5 Flash Vision
     * @param {Buffer} fileBuffer 
     * @param {string} mimetype 
     */
    static async scanBill(fileBuffer, mimetype = 'image/jpeg') {
        const apiKey = this.getApiKey();
        if (!apiKey) {
            throw new Error('Chưa cấu hình GEMINI_API_KEY trên server (vui lòng thêm vào Environment).');
        }

        const base64Data = fileBuffer.toString('base64');
        const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`;

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

        try {
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
                    timeout: 20000
                }
            );

            const textOutput = response.data?.candidates?.[0]?.content?.parts?.[0]?.text;
            if (!textOutput) {
                throw new Error('Gemini không phản hồi dữ liệu');
            }

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
                engine: 'Cloud Gemini 1.5 Flash (24/7 Fallback)'
            };
        } catch (error) {
            console.error('[!] Lỗi Gemini scanBill:', error.response?.data || error.message);
            throw new Error('Lỗi xử lý AI bóc tách hóa đơn: ' + (error.response?.data?.error?.message || error.message));
        }
    }

    /**
     * Phân loại giao dịch từ câu text tiếng Việt (Khi PhoBERT offline)
     * @param {string} text 
     */
    static async classifyTransaction(text) {
        const apiKey = this.getApiKey();
        if (!apiKey) {
            return this.ruleBasedClassifier(text);
        }

        const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`;
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

        try {
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
            const parsed = JSON.parse(textOutput);
            return {
                category_code: parsed.category_code || 'MUA_SAM',
                category_name: CATEGORIES_MAP[parsed.category_code] || parsed.category_name || 'Mua sắm & Đồ dùng',
                confidence: parsed.confidence || 0.85,
                engine: 'Cloud Gemini 1.5 Flash (24/7 Fallback)'
            };
        } catch (err) {
            console.error('[!] Lỗi Gemini classify, chuyển sang Rule-based:', err.message);
            return this.ruleBasedClassifier(text);
        }
    }

    /**
     * Phân loại dự phòng bằng tập quy tắc từ khóa (Nếu không có internet/API key)
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
     * Sử dụng mô hình thống kê Holt-Winters / Weighted Moving Average kết hợp độ biến động
     */
    static forecastExpenses(dailyExpenses) {
        if (!dailyExpenses || dailyExpenses.length === 0) {
            dailyExpenses = Array(30).fill(100000);
        }

        const n = dailyExpenses.length;
        const recent7 = dailyExpenses.slice(-7);
        const avgRecent = recent7.reduce((a, b) => a + b, 0) / 7;
        const avgAll = dailyExpenses.reduce((a, b) => a + b, 0) / n;

        // Tính độ dốc xu hướng (Trend slope)
        const slope = (avgRecent - avgAll) / 14;

        // Dự báo 7 ngày tiếp theo với độ biến thiên ngày trong tuần
        const dayWeights = [0.95, 0.98, 1.02, 1.0, 1.15, 1.25, 1.1]; // Tăng nhẹ cuối tuần
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
