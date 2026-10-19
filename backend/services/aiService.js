const axios = require('axios');
require('dotenv').config();

const AI_BASE_URL = process.env.AI_SERVICE_URL || 'http://localhost:8000';

class AiService {
    /**
     * Kiểm tra trạng thái AI Service
     */
    static async getHealth() {
        try {
            const response = await axios.get(`${AI_BASE_URL}/health`, { timeout: 3000 });
            return response.data;
        } catch (error) {
            return {
                status: 'offline',
                message: 'Không thể kết nối đến AI Service tại ' + AI_BASE_URL
            };
        }
    }

    /**
     * Gọi PhoBERT phân loại giao dịch từ câu tiếng Việt
     * @param {string} text - Ví dụ: "Ăn phở bò 45k"
     */
    static async classifyTransaction(text) {
        try {
            const response = await axios.post(
                `${AI_BASE_URL}/api/v1/ai/classify`,
                { text: text },
                { headers: { 'Content-Type': 'application/json' }, timeout: 5000 }
            );
            return response.data;
        } catch (error) {
            console.error('[!] Lỗi gọi AI classify:', error.response?.data || error.message);
            throw new Error(error.response?.data?.detail || 'Lỗi khi gọi dịch vụ phân loại AI');
        }
    }

    /**
     * Gọi LSTM dự báo chi tiêu 7 ngày tới
     * @param {number[]} dailyExpenses - Mảng ít nhất 30 số thực
     */
    static async forecastExpenses(dailyExpenses) {
        try {
            const response = await axios.post(
                `${AI_BASE_URL}/api/v1/ai/forecast`,
                { daily_expenses: dailyExpenses },
                { headers: { 'Content-Type': 'application/json' }, timeout: 5000 }
            );
            return response.data;
        } catch (error) {
            console.error('[!] Lỗi gọi AI forecast:', error.response?.data || error.message);
            throw new Error(error.response?.data?.detail || 'Lỗi khi gọi dịch vụ dự báo AI');
        }
    }

    /**
     * Gửi ảnh hóa đơn sang AI Microservice để OCR bóc tách và phân loại
     * @param {Buffer} fileBuffer - Buffer dữ liệu ảnh
     * @param {string} filename - Tên file ảnh
     * @param {string} mimetype - Loại file
     */
    static async scanBill(fileBuffer, filename = 'bill.jpg', mimetype = 'image/jpeg') {
        try {
            const formData = new FormData();
            const blob = new Blob([fileBuffer], { type: mimetype });
            formData.append('file', blob, filename);

            const response = await fetch(`${AI_BASE_URL}/api/v1/ai/scan-bill`, {
                method: 'POST',
                body: formData
            });

            if (!response.ok) {
                const errJson = await response.json().catch(() => ({}));
                throw new Error(errJson.detail || `Lỗi AI Service: HTTP ${response.status}`);
            }

            return await response.json();
        } catch (error) {
            console.error('[!] Lỗi gọi AI scanBill:', error.message);
            throw error;
        }
    }
}

module.exports = AiService;
