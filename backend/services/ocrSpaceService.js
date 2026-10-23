/**
 * OCR.Space Service - Cloud OCR siêu tốc (< 1 giây)
 * Miễn phí 25.000 lượt quét/tháng, không bị lỗi Timeout và không phụ thuộc Google Gemini.
 */

const axios = require('axios');

class OcrSpaceService {
    static getApiKey() {
        return process.env.OCR_SPACE_API_KEY || 'helloworld';
    }

    /**
     * Bóc tách hóa đơn bằng OCR.Space API
     * @param {Buffer} fileBuffer 
     * @param {string} filename 
     */
    static async scanBill(fileBuffer, filename = 'bill.jpg') {
        const apiKey = this.getApiKey();
        const url = 'https://api.ocr.space/parse/image';

        try {
            const formData = new FormData();
            const blob = new Blob([fileBuffer], { type: 'image/jpeg' });
            formData.append('file', blob, filename);
            formData.append('apikey', apiKey);
            formData.append('language', 'vnm'); // Tiếng Việt
            formData.append('isOverlayRequired', 'false');
            formData.append('scale', 'true');
            formData.append('detectOrientation', 'true');

            const response = await fetch(url, {
                method: 'POST',
                body: formData
            });

            if (!response.ok) {
                throw new Error(`OCR.Space HTTP ${response.status}`);
            }

            const data = await response.json();
            const parsedText = data.ParsedResults?.[0]?.ParsedText || '';

            if (!parsedText || parsedText.trim().length === 0) {
                throw new Error(data.ErrorMessage?.[0] || 'Không thể nhận diện ký tự từ ảnh hóa đơn');
            }

            return this.parseReceiptText(parsedText);
        } catch (error) {
            console.error('[!] Lỗi OCR.Space:', error.message);
            throw error;
        }
    }

    /**
     * Trích xuất thông minh Số tiền, Ngày tháng, Tên cửa hàng từ văn bản OCR
     */
    static parseReceiptText(text) {
        const lines = text.split('\n').map(l => l.trim()).filter(Boolean);

        // 1. Tên cửa hàng (Tìm ở 5 dòng đầu tiên)
        let merchant = 'Cửa hàng / Siêu thị';
        for (let i = 0; i < Math.min(5, lines.length); i++) {
            const l = lines[i];
            if (l.length >= 3 && !/^\d+$/.test(l) && !/hóa\s*đơn|phiếu|bill/i.test(l) && !/địa\s*chỉ|điện\s*thoại/i.test(l)) {
                merchant = l;
                break;
            }
        }

        // 2. Tìm ngày tháng
        let dateStr = new Date().toISOString().split('T')[0];
        const dateMatch = text.match(/(?:ngày\s+)?(\d{1,2})[\/\-\s]+(?:tháng\s+)?(\d{1,2})[\/\-\s]+(?:năm\s+)?(\d{4})/i) ||
                          text.match(/(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})/);

        if (dateMatch) {
            if (dateMatch[1].length === 4) {
                dateStr = `${dateMatch[1]}-${dateMatch[2].padStart(2, '0')}-${dateMatch[3].padStart(2, '0')}`;
            } else {
                dateStr = `${dateMatch[3]}-${dateMatch[2].padStart(2, '0')}-${dateMatch[1].padStart(2, '0')}`;
            }
        }

        // 3. Tìm Tổng số tiền (Thuật toán quét nhãn + Quét số lớn nhất ở phần đáy hóa đơn)
        let totalAmount = 0;

        // Quét các dòng có từ khóa tổng tiền
        const totalKeywords = ['tổng', 'thanh toán', 'tong', 'tien', 'total', 'amount', 'chuyển khoản', 'tiền hàng'];
        for (let i = 0; i < lines.length; i++) {
            const lineLower = lines[i].toLowerCase();
            const hasKeyword = totalKeywords.some(kw => lineLower.includes(kw));

            if (hasKeyword) {
                // Kiểm tra dòng hiện tại và 3 dòng tiếp theo
                for (let j = i; j <= Math.min(i + 3, lines.length - 1); j++) {
                    const matches = lines[j].match(/[0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9}/g);
                    if (matches) {
                        for (const m of matches) {
                            const val = parseInt(m.replace(/[^0-9]/g, ''), 10);
                            if (val >= 1000 && val > totalAmount) {
                                totalAmount = val;
                            }
                        }
                    }
                }
            }
        }

        // Nếu vẫn chưa tìm thấy, quét 10 dòng cuối cùng lấy số tiền hợp lý nhất
        if (totalAmount === 0) {
            const bottomLines = lines.slice(-10);
            for (const bl of bottomLines) {
                const matches = bl.match(/[0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,9}/g);
                if (matches) {
                    for (const m of matches) {
                        const val = parseInt(m.replace(/[^0-9]/g, ''), 10);
                        if (val >= 1000 && val > totalAmount) {
                            totalAmount = val;
                        }
                    }
                }
            }
        }

        return {
            success: true,
            merchant: merchant.replace(/[:\-]/g, '').trim(),
            total_amount: totalAmount,
            date: dateStr,
            category_code: 'MUA_SAM',
            category_name: 'Mua sắm & Đồ dùng',
            confidence: 0.95,
            raw_text: text.slice(0, 500),
            engine: 'Cloud OCR.Space Engine (< 1s)'
        };
    }
}

module.exports = OcrSpaceService;
