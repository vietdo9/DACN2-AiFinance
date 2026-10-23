---
language:
- vi
pipeline_tag: text-classification
tags:
- finance
- phobert
- text-classification
- pytorch
- transformers
widget:
- text: "Ăn phở bò tái nạm 45k"
- text: "Đổ xăng xe máy 50k"
- text: "Mua áo sơ mi Uniqlo 500k"
- text: "Thanh toán tiền điện tháng 10"
- text: "Nhận lương công ty 15 triệu"
---

# PhoBERT FinWise - Mô hình phân loại giao dịch tài chính tiếng Việt

Mô hình Deep Learning PhoBERT (`vinai/phobert-base-v2`) được tinh chỉnh (fine-tuned) phục vụ đề tài **Quản lý Tài chính Cá nhân Tích hợp AI (ĐACN2)**.

## 1. Thông tin mô hình
- **Kiến trúc**: `RobertaForSequenceClassification` (PhoBERT Base v2)
- **Số lớp phân loại**: 10 danh mục tài chính chuẩn
  - `AN_UONG`: Ăn uống & Cà phê
  - `DI_LAI`: Di chuyển & Đi lại
  - `MUA_SAM`: Mua sắm & Đồ dùng
  - `HOA_DON`: Hóa đơn & Tiện ích
  - `NHA_O`: Nhà ở & Tiền trọ
  - `GIAI_TRI`: Giải trí & Sở thích
  - `SUC_KHOE`: Sức khỏe & Y tế
  - `HOC_TAP`: Học tập & Phát triển
  - `TIET_KIEM_DAU_TU`: Tiết kiệm & Đầu tư
  - `THU_NHAP`: Thu nhập & Lương

## 2. Tác giả
- Đề tài Đồ Án Chuyên Ngành (ĐACN2) - FinWise AI Finance
- Huấn luyện trên phần cứng: NVIDIA GeForce RTX 4050 Laptop GPU
