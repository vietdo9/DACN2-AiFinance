/**
 * PhoBERT Hugging Face Serverless Inference Service
 * Gọi trực tiếp mô hình PhoBERT do chính bạn huấn luyện (vietdo99/phobert-finwise)
 * được lưu trữ miễn phí 100% vĩnh viễn trên Hugging Face Model Hub.
 */

const axios = require('axios');

const HF_MODEL_ID = process.env.HF_MODEL_ID || 'vietdo99/phobert-finwise';
const HF_TOKEN = process.env.HF_TOKEN || '';

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

class PhobertHfService {
    /**
     * Phân loại giao dịch bằng mô hình PhoBERT tự train của bạn trên Hugging Face
     * @param {string} text - Câu nhập giao dịch, ví dụ "Ăn phở bò 45k"
     */
    static async classify(text) {
        if (!text || text.trim().length === 0) {
            return {
                category_code: 'MUA_SAM',
                category_name: CATEGORIES_MAP['MUA_SAM'],
                confidence: 0.5,
                engine: 'Default'
            };
        }

        // Endpoint Serverless Inference API của Hugging Face
        const url = `https://api-inference.huggingface.co/models/${HF_MODEL_ID}`;

        const headers = {
            'Content-Type': 'application/json',
            'x-wait-for-model': 'true' // Đợi Hugging Face nạp model vào RAM nếu đang ngủ
        };

        if (HF_TOKEN) {
            headers['Authorization'] = `Bearer ${HF_TOKEN}`;
        }

        try {
            const response = await axios.post(
                url,
                { inputs: text.trim() },
                { headers, timeout: 20000 }
            );

            // Hugging Face trả về mảng kết quả: [[{ label: 'AN_UONG', score: 0.98 }, ...]]
            const results = Array.isArray(response.data?.[0]) ? response.data[0] : response.data;

            if (Array.isArray(results) && results.length > 0) {
                // Sắp xếp lấy nhãn có điểm cao nhất
                results.sort((a, b) => (b.score || 0) - (a.score || 0));
                const top = results[0];
                const code = top.label || 'MUA_SAM';

                return {
                    category_code: code,
                    category_name: CATEGORIES_MAP[code] || code,
                    confidence: top.score ? parseFloat(top.score.toFixed(4)) : 0.9,
                    engine: `Your Self-Trained PhoBERT on Hugging Face Cloud (${HF_MODEL_ID})`
                };
            }

            throw new Error('Định dạng phản hồi từ Hugging Face không hợp lệ');
        } catch (error) {
            console.error('[!] Lỗi gọi PhoBERT Hugging Face:', error.response?.data || error.message);
            throw error;
        }
    }
}

module.exports = PhobertHfService;
