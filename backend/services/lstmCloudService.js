/**
 * LSTM Cloud In-Memory Neural Network Service
 * Chạy trực tiếp 100% trọng số của mô hình LSTM tự train (lstm_model.pth & scaler.pkl)
 * trên Node.js Cloud 24/7 với độ trễ siêu thấp (< 10ms) mà không cần máy tính cá nhân phải mở!
 */

const fs = require('fs');
const path = require('path');

let weightsData = null;

try {
    const weightsPath = path.join(__dirname, '../config/lstm_model_weights.json');
    if (fs.existsSync(weightsPath)) {
        weightsData = JSON.parse(fs.readFileSync(weightsPath, 'utf8'));
    }
} catch (e) {
    console.error('[!] Lỗi nạp trọng số LSTM Cloud:', e.message);
}

function sigmoid(x) {
    return 1 / (1 + Math.exp(-x));
}

function tanh(x) {
    return Math.tanh(x);
}

// 1 bước thời gian cho 1 tầng LSTM theo chuẩn PyTorch
function lstmStep(x, hPrev, cPrev, W_ih, W_hh, b_ih, b_hh, hiddenSize) {
    const inputSize = x.length;
    const hNext = new Float64Array(hiddenSize);
    const cNext = new Float64Array(hiddenSize);
    const gates = new Float64Array(4 * hiddenSize);

    for (let row = 0; row < 4 * hiddenSize; row++) {
        let sum = b_ih[row] + b_hh[row];
        const row_ih = W_ih[row];
        for (let j = 0; j < inputSize; j++) {
            sum += row_ih[j] * x[j];
        }
        const row_hh = W_hh[row];
        for (let j = 0; j < hiddenSize; j++) {
            sum += row_hh[j] * hPrev[j];
        }
        gates[row] = sum;
    }

    for (let j = 0; j < hiddenSize; j++) {
        const i_gate = sigmoid(gates[j]);
        const f_gate = sigmoid(gates[hiddenSize + j]);
        const g_gate = tanh(gates[2 * hiddenSize + j]);
        const o_gate = sigmoid(gates[3 * hiddenSize + j]);

        const c_val = f_gate * cPrev[j] + i_gate * g_gate;
        cNext[j] = c_val;
        hNext[j] = o_gate * tanh(c_val);
    }

    return { h: hNext, c: cNext };
}

class LstmCloudService {
    static isAvailable() {
        return weightsData !== null && weightsData.weights && weightsData.scaler;
    }

    /**
     * Dự báo chi tiêu 7 ngày tới bằng chính mô hình LSTM tự huấn luyện
     * @param {number[]} dailyExpenses - Mảng chi tiêu (ít nhất 30 ngày)
     */
    static forecast(dailyExpenses) {
        if (!this.isAvailable()) {
            throw new Error('Chưa nạp được tệp trọng số LSTM weights');
        }

        const { scaler, weights } = weightsData;
        const minVal = scaler.data_min;
        const maxVal = scaler.data_max;
        const range = maxVal - minVal;

        // Đảm bảo lấy đủ 30 ngày gần nhất
        let seq = dailyExpenses || [];
        if (seq.length < 30) {
            const pad = Array(30 - seq.length).fill(0);
            seq = [...pad, ...seq];
        } else if (seq.length > 30) {
            seq = seq.slice(-30);
        }

        // 1. Chuẩn hóa MinMaxScaler [0, 1]
        const scaledSeq = seq.map(v => (v - minVal) / range);

        const hiddenSize = 64;
        let h0 = new Float64Array(hiddenSize);
        let c0 = new Float64Array(hiddenSize);
        let h1 = new Float64Array(hiddenSize);
        let c1 = new Float64Array(hiddenSize);

        // 2. Chạy qua 2 tầng LSTM (30 time steps)
        for (let t = 0; t < scaledSeq.length; t++) {
            const x0 = [scaledSeq[t]];
            const res0 = lstmStep(
                x0, h0, c0,
                weights['lstm.weight_ih_l0'],
                weights['lstm.weight_hh_l0'],
                weights['lstm.bias_ih_l0'],
                weights['lstm.bias_hh_l0'],
                hiddenSize
            );
            h0 = res0.h;
            c0 = res0.c;

            const res1 = lstmStep(
                h0, h1, c1,
                weights['lstm.weight_ih_l1'],
                weights['lstm.weight_hh_l1'],
                weights['lstm.bias_ih_l1'],
                weights['lstm.bias_hh_l1'],
                hiddenSize
            );
            h1 = res1.h;
            c1 = res1.c;
        }

        // 3. Fully Connected Layers (Linear 64->32 + ReLU + Linear 32->7)
        const W_fc0 = weights['fc.0.weight'];
        const b_fc0 = weights['fc.0.bias'];
        const fc0_out = new Float64Array(32);

        for (let i = 0; i < 32; i++) {
            let sum = b_fc0[i];
            const row = W_fc0[i];
            for (let j = 0; j < 64; j++) {
                sum += row[j] * h1[j];
            }
            fc0_out[i] = Math.max(0, sum);
        }

        const W_fc2 = weights['fc.2.weight'];
        const b_fc2 = weights['fc.2.bias'];
        const predScaled = new Float64Array(7);

        for (let i = 0; i < 7; i++) {
            let sum = b_fc2[i];
            const row = W_fc2[i];
            for (let j = 0; j < 32; j++) {
                sum += row[j] * fc0_out[j];
            }
            predScaled[i] = sum;
        }

        // 4. Inverse transform về VNĐ & làm tròn đến 1.000đ
        const predVND = [];
        for (let i = 0; i < 7; i++) {
            const val = predScaled[i] * range + minVal;
            const rounded = Math.max(0, Math.round(val / 1000) * 1000);
            predVND.push(rounded);
        }

        const totalForecast = predVND.reduce((a, b) => a + b, 0);
        const avgDaily = Math.round(totalForecast / 7);

        // 5. Phân tích mức độ rủi ro & cảnh báo
        const pastAvg = seq.reduce((a, b) => a + b, 0) / 30;
        const ratio = pastAvg > 0 ? avgDaily / pastAvg : 1.0;

        let warningLevel = 'AN_TOAN';
        let message = 'Dòng tiền dự kiến trong 7 ngày tới ở mức ổn định và an toàn.';

        if (ratio > 1.3) {
            warningLevel = 'CAO';
            message = `Cảnh báo: Chi tiêu 7 ngày tới dự kiến tăng ${Math.round((ratio - 1) * 100)}% so với trung bình tháng qua. Hãy thắt chặt ví tiền!`;
        } else if (ratio > 1.1) {
            warningLevel = 'TRUNG_BINH';
            message = 'Chi tiêu tuần tới có xu hướng tăng nhẹ. Hãy lưu ý các khoản mua sắm và giải trí.';
        }

        return {
            predicted_next_7_days: predVND,
            total_forecast: totalForecast,
            average_daily_forecast: avgDaily,
            warning_level: warningLevel,
            message: message,
            engine: 'Self-trained 2-Layer LSTM Neural Network (24/7 Cloud In-Memory Engine)'
        };
    }
}

module.exports = LstmCloudService;
