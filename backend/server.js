const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
require('dotenv').config();

const authRoutes = require('./routes/auth.routes');
const walletRoutes = require('./routes/wallet.routes');
const transactionRoutes = require('./routes/transaction.routes');
const aiRoutes = require('./routes/ai.routes');
const analyticsRoutes = require('./routes/analytics.routes');

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(cors({ origin: '*' }));
app.use(express.json());
app.use(morgan('dev'));

// Định tuyến API (Routes)
app.use('/api/auth', authRoutes);
app.use('/api/wallets', walletRoutes);
app.use('/api/transactions', transactionRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api/analytics', analyticsRoutes);

// Endpoint kiểm tra hoạt động (Health Check)
app.get('/', (req, res) => {
    res.json({
        name: 'FinWise Backend API Gateway',
        version: '1.0.0',
        status: 'running',
        endpoints: {
            auth: '/api/auth (register, login, me)',
            wallets: '/api/wallets (list, create)',
            transactions: '/api/transactions (list, create with AI auto-tag, categories)',
            ai: '/api/ai (classify, forecast, user-forecast)',
            analytics: '/api/analytics (summary, breakdown)'
        },
        ai_service_url: process.env.AI_SERVICE_URL || 'http://localhost:8000'
    });
});

// Middleware xử lý lỗi tập trung
app.use((err, req, res, next) => {
    console.error('[Server Error]:', err);
    res.status(err.status || 500).json({
        success: false,
        message: err.message || 'Lỗi máy chủ nội bộ'
    });
});

// Khởi chạy server
app.listen(PORT, () => {
    console.log('====================================================');
    console.log(`[+] FinWise Node.js Backend đang chạy tại: http://localhost:${PORT}`);
    console.log(`[*] API Health: http://localhost:${PORT}/`);
    console.log(`[*] Kết nối AI Service: ${process.env.AI_SERVICE_URL || 'http://localhost:8000'}`);
    console.log('====================================================');
});
