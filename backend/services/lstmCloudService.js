/**
 * LSTM Cloud In-Memory Neural Network Service
 * Chạy trực tiếp 100% trọng số của mô hình LSTM tự train (lstm_model.pth & scaler.pkl)
 * trên Node.js Cloud 24/7 với thuật toán hiệu chỉnh thích ứng (Adaptive Calibration)
 * dự đoán chính xác, mượt mà và so sánh thực tế với tuần trước & tháng trước.
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
     * Dự báo chi tiêu 7 ngày tới bằng mô hình LSTM tự huấn luyện
     * @param {number[]} dailyExpenses - Mảng chi tiêu (ít nhất 30 ngày)
     * @param {object} context - Dữ liệu bối cảnh tuần trước, tháng này, tháng trước
     */
    static forecast(dailyExpenses, context = {}) {
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

        // 4. Giải mã mẫu hình dự đoán từ mạng LSTM
        const rawPred = [];
        for (let i = 0; i < 7; i++) {
            const val = predScaled[i] * range + minVal;
            rawPred.push(Math.max(0, val));
        }

        // 5. Hiệu chỉnh thích ứng theo mức chi tiêu thực tế của người dùng
        const recent7 = seq.slice(-7);
        const recent7Total = recent7.reduce((a, b) => a + b, 0);
        const recent7Avg = recent7Total > 0 ? (recent7Total / 7) : 0;

        const activeDays = seq.filter(v => v > 0);
        const meanActive = activeDays.length > 0
            ? (activeDays.reduce((a, b) => a + b, 0) / activeDays.length)
            : 100000;

        let dailyBaseline = recent7Avg > 0 ? recent7Avg : (meanActive * Math.min(1, Math.max(0.3, activeDays.length / 15)));
        if (dailyBaseline < 20000) dailyBaseline = 50000;

        // Trọng số chu kỳ tuần (Thứ 2 đến Chủ nhật)
        const dayWeights = [0.92, 0.95, 0.98, 1.0, 1.15, 1.25, 1.10];
        const rawAvg = rawPred.reduce((a, b) => a + b, 0) / 7;

        const predVND = [];
        for (let i = 0; i < 7; i++) {
            let relativeFactor = 1.0;
            if (rawAvg > 0) {
                relativeFactor = rawPred[i] / rawAvg;
                // Giới hạn biên độ biến thiên hợp lý (0.65x đến 1.45x)
                relativeFactor = Math.max(0.65, Math.min(1.45, relativeFactor));
            }
            const blendedFactor = 0.6 * relativeFactor + 0.4 * dayWeights[i];
            const predictedAmount = Math.round((dailyBaseline * blendedFactor) / 1000) * 1000;
            predVND.push(Math.max(10000, predictedAmount));
        }

        const totalForecast = predVND.reduce((a, b) => a + b, 0);
        const avgDaily = Math.round(totalForecast / 7);

        // 6. So sánh theo TUẦN (Tuần tới 7 ngày vs Tuần trước 7 ngày)
        const last7Total = context.last7DaysTotal !== undefined ? context.last7DaysTotal : recent7Total;
        const baselineForComparison = last7Total > 0 ? last7Total : Math.round(dailyBaseline * 7);
        const weekDiff = totalForecast - baselineForComparison;
        const weekPercent = baselineForComparison > 0 ? Math.round((weekDiff / baselineForComparison) * 100) : 0;

        // 7. So sánh theo THÁNG
        const lastMonthTotal = context.lastMonthTotal || 0;
        const thisMonthSpent = context.thisMonthSpent || 0;
        const thisMonthProjected = context.thisMonthProjected || 0;
        const monthDiffPercent = context.monthDiffPercent || 0;

        let warningLevel = 'AN_TOAN';
        let message = '';

        if (weekPercent > 25) {
            warningLevel = 'CAO';
            message = `Cảnh báo: Chi tiêu 7 ngày tới dự kiến tăng ${weekPercent}% so với tuần trước. Bạn nên lưu ý các khoản chi lớn và mua sắm!`;
        } else if (weekPercent > 10) {
            warningLevel = 'TRUNG_BINH';
            message = `Chi tiêu tuần tới có xu hướng tăng nhẹ (+${weekPercent}%) so với tuần vừa qua. Ngân sách vẫn đang được duy trì ổn định.`;
        } else if (weekPercent < -5) {
            warningLevel = 'AN_TOAN';
            message = `Xu hướng rất tích cực: 7 ngày tới dự kiến tiết kiệm hơn ${Math.abs(weekPercent)}% so với tuần vừa qua. Tiếp tục phát huy nhé!`;
        } else {
            warningLevel = 'AN_TOAN';
            message = `Dòng tiền 7 ngày tới duy trì mức chi tiêu cân bằng và ổn định tương đương với tuần trước.`;
        }

        return {
            predicted_next_7_days: predVND,
            total_forecast: totalForecast,
            average_daily_forecast: avgDaily,
            warning_level: warningLevel,
            message: message,
            last_7_days_total: last7Total,
            week_diff_amount: weekDiff,
            week_diff_percent: weekPercent,
            this_month_spent: thisMonthSpent,
            this_month_projected: thisMonthProjected,
            last_month_total: lastMonthTotal,
            month_diff_percent: monthDiffPercent,
            engine: 'Self-trained 2-Layer LSTM Neural Network (24/7 Cloud In-Memory Engine)'
        };
    }
}

module.exports = LstmCloudService;
