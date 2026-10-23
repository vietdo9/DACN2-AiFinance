const axios = require('axios');
const GeminiService = require('./geminiService');
const PhobertHfService = require('./phobertHfService');
const OcrSpaceService = require('./ocrSpaceService');
require('dotenv').config();

const AI_BASE_URL = process.env.AI_SERVICE_URL || 'http://localhost:8000';

class AiService {
    /**
     * Kiểm tra trạng thái AI Service (Hỗ trợ phát hiện chế độ kép Hybrid)
     */
    static async getHealth() {
        // 1. Kiểm tra AI Service cục bộ (GPU)
        try {
            const response = await axios.get(`${AI_BASE_URL}/health`, { timeout: 2500 });
            return {
                ...response.data,
                mode: 'gpu_local_active',
                active_engine: 'Self-trained PhoBERT + LSTM + EasyOCR (GPU)',
                note: 'Máy tính đang bật: Đang sử dụng mô hình tự huấn luyện trên GPU máy tính.'
            };
        } catch (error) {
            const hasHf = Boolean(process.env.HF_TOKEN);

            return {
                status: 'healthy',
                mode: 'cloud_hybrid_active',
                ocr_engine: 'Cloud OCR.Space Engine (Siêu tốc < 1s, Không Timeout)',
                phobert_cloud: hasHf ? `vietdo99/phobert-finwise (Hugging Face)` : 'Offline Rule-based Classifier',
                active_engine: hasHf
                    ? 'Cloud OCR + Your Self-Trained PhoBERT (Hugging Face)'
                    : 'Cloud OCR.Space Engine',
                message: 'Máy tính đang tắt. Hệ thống đang chạy 100% trên Cloud 24/7!'
            };
        }
    }

    /**
     * Phân loại giao dịch (PhoBERT local -> PhoBERT Hugging Face -> Gemini/Rule)
     * @param {string} text - Ví dụ: "Ăn phở bò 45k"
     */
    static async classifyTransaction(text) {
        // 1. Thử gọi PhoBERT trên máy tính cục bộ nếu có
        try {
            const response = await axios.post(
                `${AI_BASE_URL}/api/v1/ai/classify`,
                { text: text },
                { headers: { 'Content-Type': 'application/json' }, timeout: 2500 }
            );
            return {
                ...response.data,
                engine: 'Self-trained PhoBERT Classifier (Local GPU)'
            };
        } catch (error) {
            // 2. Thử gọi PhoBERT tự train của bạn trên Hugging Face
            if (process.env.HF_TOKEN) {
                try {
                    return await PhobertHfService.classify(text);
                } catch (hfErr) {
                    console.log('[*] Lỗi PhoBERT Hugging Face, chuyển sang fallback:', hfErr.message);
                }
            }

            // 3. Fallback sang Rule-based / Gemini
            return await GeminiService.classifyTransaction(text);
        }
    }

    /**
     * Dự báo chi tiêu 7 ngày tới (LSTM ưu tiên, Statistical Forecaster dự phòng)
     * @param {number[]} dailyExpenses - Mảng ít nhất 30 số thực
     */
    static async forecastExpenses(dailyExpenses) {
        // 1. Thử gọi mô hình LSTM trên máy tính cục bộ
        try {
            const response = await axios.post(
                `${AI_BASE_URL}/api/v1/ai/forecast`,
                { daily_expenses: dailyExpenses },
                { headers: { 'Content-Type': 'application/json' }, timeout: 2500 }
            );
            return {
                ...response.data,
                engine: 'Self-trained LSTM Time-Series Forecaster (Local GPU)'
            };
        } catch (error) {
            return GeminiService.forecastExpenses(dailyExpenses);
        }
    }

    /**
     * Gửi ảnh hóa đơn bóc tách (EasyOCR local -> Cloud OCR.Space < 1s + PhoBERT HF 24/7)
     * @param {Buffer} fileBuffer - Buffer dữ liệu ảnh
     * @param {string} filename - Tên file ảnh
     * @param {string} mimetype - Loại file
     */
    static async scanBill(fileBuffer, filename = 'bill.jpg', mimetype = 'image/jpeg') {
        // 1. Thử gọi mô hình EasyOCR + PhoBERT cục bộ (khi máy tính mở)
        try {
            const formData = new FormData();
            const blob = new Blob([fileBuffer], { type: mimetype });
            formData.append('file', blob, filename);

            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 6000);

            const response = await fetch(`${AI_BASE_URL}/api/v1/ai/scan-bill`, {
                method: 'POST',
                body: formData,
                signal: controller.signal
            });
            clearTimeout(timeoutId);

            if (response.ok) {
                const data = await response.json();
                return {
                    ...data,
                    engine: 'Self-trained EasyOCR + PhoBERT (GPU RTX 4050)'
                };
            }
        } catch (error) {
            console.log('[*] AI Service cục bộ offline -> Bóc tách bằng Cloud OCR 24/7...');
        }

        // 2. Chuyển sang Cloud OCR.Space siêu tốc (< 1s, miễn phí, không timeout)
        let ocrData = null;
        try {
            console.log('[*] Bóc tách bằng Cloud OCR.Space...');
            ocrData = await OcrSpaceService.scanBill(fileBuffer, filename);
        } catch (ocrErr) {
            console.log('[*] OCR.Space lỗi, thử Gemini fallback:', ocrErr.message);
            try {
                ocrData = await GeminiService.scanBill(fileBuffer, mimetype);
            } catch (geminiErr) {
                throw new Error('Không thể bóc tách hóa đơn: ' + ocrErr.message);
            }
        }

        // 3. Nếu có PhoBERT Hugging Face, dùng chính PhoBERT của bạn để phân loại lại danh mục
        if (process.env.HF_TOKEN && ocrData && ocrData.raw_text) {
            try {
                const textForPhobert = `${ocrData.merchant} ${ocrData.raw_text}`.slice(0, 200);
                const phobertResult = await PhobertHfService.classify(textForPhobert);
                if (phobertResult && phobertResult.category_code) {
                    ocrData.category_code = phobertResult.category_code;
                    ocrData.category_name = phobertResult.category_name;
                    ocrData.engine = 'Cloud OCR + Your Self-Trained PhoBERT (vietdo99/phobert-finwise)';
                }
            } catch (err) {
                console.log('[*] Không thể phân loại lại bằng PhoBERT HF, giữ nguyên kết quả OCR:', err.message);
            }
        }

        return ocrData;
    }
}

module.exports = AiService;
