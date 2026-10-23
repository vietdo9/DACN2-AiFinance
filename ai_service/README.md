---
title: FinWise AI Service
emoji: 💰
colorFrom: blue
colorTo: indigo
sdk: docker
pinned: false
app_port: 7860
---

# FinWise AI Service - Huấn Luyện AI Trên Máy Cục Bộ (Local Training)

> 📖 **Lưu ý**: Tài liệu kiến trúc toàn diện của toàn bộ hệ thống ĐACN2 (Client Flutter + Backend Node.js + AI) được lưu tại [README.md gốc](../README.md).

Module này chứa toàn bộ mã nguồn xử lý và huấn luyện **2 mô hình Trí tuệ Nhân tạo (AI)** tự train cho đề tài **Quản lý Tài chính Cá nhân Tích hợp AI**:
1. **Model 1 (PhoBERT):** Phân loại giao dịch tiếng Việt tự động vào 10 danh mục chuẩn.
2. **Model 2 (LSTM):** Dự báo chi tiêu 7 ngày tiếp theo theo chuỗi thời gian dựa trên lịch sử chi tiêu.

Hệ thống được thiết kế và tối ưu riêng cho phần cứng: **AMD Ryzen 7 + NVIDIA RTX 4050 6GB VRAM (CUDA & Tensor Cores)**.

---

## 📁 Cấu trúc thư mục

```
e:\DACN2\ai_service\
│
├── dataset\                         # Thư mục chứa dữ liệu huấn luyện
│   ├── transactions_vn.csv          # Dữ liệu NLP 12.000 dòng
│   └── daily_expense_timeseries.csv # Dữ liệu chuỗi thời gian 730 ngày
│
├── models\                          # Nơi lưu file weights sau khi train
│   ├── phobert_classifier\          # Model PhoBERT (.bin/.safetensors, config, tokenizer)
│   └── lstm_forecaster\             # Model LSTM (.pth) & Scaler (.pkl)
│
├── reports\                         # Đồ thị & Báo cáo để dán vào Đồ án
│   ├── phobert_training_metrics.png # Biểu đồ Loss & Accuracy qua các Epochs
│   ├── phobert_confusion_matrix.png # Ma trận nhầm lẫn (Confusion Matrix)
│   ├── phobert_classification_report.txt # Bảng F1-Score, Precision, Recall
│   ├── lstm_forecast_comparison.png # Biểu đồ so sánh Thực tế vs Dự báo
│   └── lstm_evaluation_metrics.txt  # Chỉ số sai số MAE & RMSE
│
├── generate_datasets.py             # Script sinh dữ liệu huấn luyện lớn
├── train_phobert.py                 # Script huấn luyện PhoBERT (CUDA FP16)
├── train_lstm.py                    # Script huấn luyện mạng LSTM
├── app.py                           # FastAPI Server cung cấp REST API
└── requirements.txt                 # Danh sách thư viện Python
```

---

## 🚀 Hướng Dẫn Từng Bước Chạy Trên Máy Của Bạn

### Bước 1: Mở Terminal tại thư mục `ai_service` và tạo môi trường ảo

Mở PowerShell trên máy và di chuyển vào thư mục:
```powershell
cd e:\DACN2\ai_service
python -m venv venv
.\venv\Scripts\Activate.ps1
```
*(Nếu gặp lỗi PowerShell chặn script, gõ `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` rồi thử lại).*

---

### Bước 2: Cài đặt PyTorch hỗ trợ GPU RTX 4050 (CUDA)

Vì máy bạn có card **RTX 4050**, hãy cài PyTorch bản hỗ trợ CUDA 12.1/12.4 để tốc độ train nhanh gấp 15 - 20 lần so với CPU:

```powershell
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
```

Sau đó cài các thư viện còn lại:
```powershell
pip install -r requirements.txt
```

---

### Bước 3: Sinh bộ dữ liệu huấn luyện lớn (~12.000 mẫu)

Chạy script tạo dữ liệu mẫu phong phú:
```powershell
python generate_datasets.py
```
* Kết quả: Tạo ra 2 file CSV trong thư mục `dataset/`.

---

### Bước 4: Huấn luyện Model 1 - PhoBERT (Phân loại văn bản)

Chạy lệnh:
```powershell
python train_phobert.py
```
* **Thời gian ước tính:** ~3 – 5 phút trên RTX 4050.
* **Đầu ra:** Mô hình tốt nhất được lưu tại `models/phobert_classifier/`.
* Các ảnh biểu đồ `phobert_training_metrics.png` và `phobert_confusion_matrix.png` sẽ xuất hiện trong thư mục `reports/` để bạn copy dán vào báo cáo Đồ án!

---

### Bước 5: Huấn luyện Model 2 - LSTM (Dự báo chi tiêu)

Chạy lệnh:
```powershell
python train_lstm.py
```
* **Thời gian ước tính:** ~30 giây – 1 phút.
* **Đầu ra:** File trọng số `lstm_model.pth` và bộ chuẩn hóa `scaler.pkl` trong `models/lstm_forecaster/`.
* Ảnh biểu đồ so sánh `lstm_forecast_comparison.png` được lưu vào thư mục `reports/`.

---

### Bước 6: Khởi chạy API Service phục vụ cho Flutter và Node.js

Chạy lệnh:
```powershell
python app.py
```
Server sẽ chạy tại địa chỉ: `http://localhost:8000`.
Bạn có thể mở trình duyệt vào: `http://localhost:8000/docs` để xem giao diện Swagger UI và kiểm tra trực tiếp các API:
* `POST /api/v1/ai/classify`: Thử gõ một câu bất kỳ như *"Ăn lẩu haidilao 500k"* để xem AI phân loại.
* `POST /api/v1/ai/forecast`: Nhập chuỗi 30 ngày để xem AI dự báo 7 ngày tới.
