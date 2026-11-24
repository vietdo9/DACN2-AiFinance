'use strict';

function validDate(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    const [year, month, day] = value.split('-').map(Number);
    if (year < 1 || year > 9999) return false;
    const date = new Date(0);
    date.setUTCHours(0, 0, 0, 0);
    date.setUTCFullYear(year, month - 1, day);
    return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

function vietnamToday(now = new Date()) {
    const parts = new Intl.DateTimeFormat('en-CA', {
        timeZone: 'Asia/Ho_Chi_Minh', year: 'numeric', month: '2-digit', day: '2-digit'
    }).formatToParts(now);
    const part = type => parts.find(item => item.type === type).value;
    return `${part('year')}-${part('month')}-${part('day')}`;
}

function shiftDate(value, days) {
    const [year, month, day] = value.split('-').map(Number);
    const date = new Date(0);
    date.setUTCHours(0, 0, 0, 0);
    date.setUTCFullYear(year, month - 1, day + days);
    if (date.getUTCFullYear() < 1 || date.getUTCFullYear() > 9999) return null;
    return `${String(date.getUTCFullYear()).padStart(4, '0')}-${String(date.getUTCMonth() + 1).padStart(2, '0')}-${String(date.getUTCDate()).padStart(2, '0')}`;
}

function getAdminPeriod(period, anchor) {
    if (!['all', 'week', 'month'].includes(period)) return { error: 'INVALID_PERIOD' };
    if (anchor !== undefined && !validDate(anchor)) return { error: 'INVALID_DATE' };
    if (period === 'all') {
        if (anchor !== undefined) return { error: 'AMBIGUOUS_PERIOD_DATE' };
        return { type: 'all', start_date: null, end_date: null };
    }
    const date = anchor || vietnamToday();
    if (period === 'week') {
        const [year, month, day] = date.split('-').map(Number);
        const utcDate = new Date(0);
        utcDate.setUTCHours(0, 0, 0, 0);
        utcDate.setUTCFullYear(year, month - 1, day);
        const weekday = utcDate.getUTCDay();
        const monday = shiftDate(date, -((weekday + 6) % 7));
        if (!monday) return { error: 'INVALID_DATE' };
        const sunday = shiftDate(monday, 6);
        if (!sunday) return { error: 'INVALID_DATE' };
        return { type: 'week', start_date: monday, end_date: sunday };
    }
    const [year, month] = date.split('-').map(Number);
    const start = `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-01`;
    const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
    const monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return { type: 'month', start_date: start, end_date: `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${monthDays[month - 1]}` };
}

module.exports = { validDate, vietnamToday, getAdminPeriod };
