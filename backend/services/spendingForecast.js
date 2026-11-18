const DAY_MS = 86_400_000;
const HISTORY_DAYS = 30;
const MIN_HISTORY_DAYS = 7;
const MIN_ACTIVE_DAYS = 2;
const MODEL_ACTIVE_DAYS = 7;
const calendar = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Ho_Chi_Minh', year: 'numeric', month: '2-digit', day: '2-digit'
});
const dayNames = ['Chủ Nhật', 'Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy'];

function dateKey(date) {
    const parts = Object.fromEntries(calendar.formatToParts(date).map(part => [part.type, part.value]));
    return `${parts.year}-${parts.month}-${parts.day}`;
}

const key = date => date.toISOString().slice(0, 10);
const day = (date, offset) => new Date(date.getTime() + offset * DAY_MS);
const label = date => `${key(date).slice(8)}/${key(date).slice(5, 7)}`;
const sum = values => values.reduce((total, amount) => total + amount, 0);

function getPeriod(now = new Date()) {
    const today = new Date(`${dateKey(now)}T00:00:00Z`);
    const weekStart = day(today, -((today.getUTCDay() + 6) % 7));
    const year = today.getUTCFullYear();
    const month = today.getUTCMonth();
    const lastMonth = new Date(Date.UTC(year, month - 1, 1));
    const historyStart = day(today, -HISTORY_DAYS);
    return {
        today, weekStart, historyStart, lastMonth,
        monthStart: new Date(Date.UTC(year, month, 1)),
        monthEnd: new Date(Date.UTC(year, month + 1, 0)),
        earliest: key(lastMonth < historyStart ? lastMonth : historyStart),
        latest: key(today)
    };
}

function dayDetail(date, amount, predicted) {
    return {
        date: key(date), day_name: dayNames[date.getUTCDay()], day_label: label(date),
        is_past_or_today: !predicted, amount, is_predicted: predicted
    };
}

async function buildForecast(rows, period, predict, demo = false, firstRecordedDate) {
    const { today, weekStart, historyStart, lastMonth, monthStart, monthEnd, latest } = period;
    const totals = new Map();
    for (const row of rows) {
        const date = String(row.transaction_date ?? '').slice(0, 10);
        const amount = Number(row.amount);
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || date > latest || !Number.isFinite(amount) || amount <= 0) continue;
        totals.set(date, (totals.get(date) ?? 0) + amount);
    }
    if (demo) {
        const examples = [50000, 70000, 90000, 45000, 120000, 85000, 65000];
        for (let i = 0; i <= HISTORY_DAYS; i++) totals.set(key(day(historyStart, i)), examples[i % 7]);
    }
    const actual = date => totals.get(key(date)) ?? 0;
    const history = Array.from({ length: HISTORY_DAYS }, (_, i) => actual(day(historyStart, i)));
    const activeDays = history.filter(amount => amount > 0).length;
    const windowStart = key(historyStart);
    const hasFullWindow = (firstRecordedDate && firstRecordedDate <= windowStart)
        || [...totals.keys()].some(date => date <= windowStart);
    const firstActiveDay = history.findIndex(amount => amount > 0);
    const observedDays = hasFullWindow ? HISTORY_DAYS
        : firstActiveDay === -1 ? 0 : HISTORY_DAYS - firstActiveDay;
    if (observedDays < MIN_HISTORY_DAYS || activeDays < MIN_ACTIVE_DAYS) {
        return {
            success: true, has_enough_data: false, data: null,
            message: `Cần lịch sử chi tiêu trải dài ít nhất 7 ngày, có khoản chi trong ít nhất 2 ngày đã qua. Hiện có ${activeDays} ngày có khoản chi trong 30 ngày đã qua.`
        };
    }

    const dailyAverage = sum(history) / observedDays;
    const limitedHistory = !hasFullWindow || activeDays < MODEL_ACTIVE_DAYS;
    let model;
    if (!demo && !limitedHistory) {
        try {
            model = await predict(history);
        } catch (_) {
            // A history-based estimate is still available if the model is unavailable.
        }
    }
    const amounts = model?.predicted_next_7_days;
    const validModel = Array.isArray(amounts) && amounts.length === 7
        && amounts.every(value => Number.isFinite(value) && value >= 0)
        && Number.isFinite(sum(amounts)) && sum(amounts) > 0
        && !/statistical/i.test(model.engine ?? '');
    const modelAverage = validModel ? sum(amounts) / 7 : 0;
    // The model supplies the daily pattern. The recorded history supplies the spending scale.
    const projections = Array.from({ length: 7 }, (_, i) => {
        const ratio = validModel ? Math.min(1.5, Math.max(0.5, amounts[i] / modelAverage)) : 1;
        return Math.round(dailyAverage * ratio);
    });
    const estimate = date => {
        const offset = (date - today) / DAY_MS;
        return projections[offset] ?? Math.round(dailyAverage);
    };
    const thisWeek = Array.from({ length: 7 }, (_, i) => {
        const date = day(weekStart, i);
        return dayDetail(date, date <= today ? actual(date) : estimate(date), date > today);
    });
    // Model index zero belongs to today. Its seventh output covers six days
    // from today, so the final upcoming day uses the historical average.
    const nextDays = Array.from({ length: 7 }, (_, i) => {
        const date = day(today, i + 1);
        return dayDetail(date, estimate(date), true);
    });
    const lastWeekTotal = sum(Array.from({ length: 7 }, (_, i) => actual(day(weekStart, i - 7))));
    const totalForecast = sum(thisWeek.map(entry => entry.amount));
    const weekDiff = totalForecast - lastWeekTotal;
    const weekPercent = lastWeekTotal > 0 ? Math.round(weekDiff / lastWeekTotal * 100) : null;
    const lastMonthTotal = sum([...totals].filter(([date]) => date >= key(lastMonth) && date < key(monthStart)).map(([, amount]) => amount));
    const monthSpent = sum([...totals].filter(([date]) => date >= key(monthStart)).map(([, amount]) => amount));
    const monthProjected = Math.round(monthSpent + dailyAverage * ((monthEnd - today) / DAY_MS));
    const monthPercent = lastMonthTotal > 0 ? Math.round((monthProjected - lastMonthTotal) / lastMonthTotal * 100) : null;
    const comparison = weekPercent === null
        ? 'Tuần trước không có khoản chi được ghi nhận để so sánh.'
        : `Chi tiêu tuần này ước tính ${weekPercent === 0 ? 'bằng' : weekPercent > 0 ? `cao hơn ${weekPercent}% so với` : `thấp hơn ${Math.abs(weekPercent)}% so với`} tuần trước.`;

    return {
        success: true, has_enough_data: true, is_demo_data: demo,
        data: {
            as_of: latest, active_days: activeDays, history_days: observedDays,
            predicted_next_7_days: nextDays.map(entry => entry.amount),
            next_days_detail: nextDays, week_days_detail: thisWeek,
            total_forecast: totalForecast, average_daily_forecast: Math.round(totalForecast / 7),
            warning_level: limitedHistory ? 'THAM_KHAO' : weekPercent > 20 ? 'CAO' : weekPercent > 10 ? 'TRUNG_BINH' : 'THAM_KHAO',
            message: limitedHistory
                ? `Lịch sử còn ít: ${activeDays} ngày có khoản chi trong ${observedDays} ngày quan sát. Ước tính theo mức chi trung bình. ${comparison}`
                : comparison,
            last_7_days_total: lastWeekTotal, week_diff_amount: weekDiff, week_diff_percent: weekPercent,
            this_week_label: `${label(weekStart)} - ${label(day(weekStart, 6))}`,
            last_week_label: `${label(day(weekStart, -7))} - ${label(day(weekStart, -1))}`,
            this_month_spent: monthSpent, this_month_projected: monthProjected,
            last_month_total: lastMonthTotal, month_diff_percent: monthPercent,
            this_month_label: `Tháng ${today.getUTCMonth() + 1}`,
            last_month_label: `Tháng ${lastMonth.getUTCMonth() + 1}`,
            engine: demo ? 'Dữ liệu mô phỏng' : validModel ? 'LSTM hiệu chỉnh theo lịch sử chi tiêu' : `Trung bình chi tiêu ${observedDays} ngày`
        }
    };
}

module.exports = { getPeriod, buildForecast };
