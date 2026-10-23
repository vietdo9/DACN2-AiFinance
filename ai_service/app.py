"""
API Microservice (FastAPI) phục vụ suy luận (Inference) cho 2 Model AI:
1. POST /api/v1/ai/classify: Phân loại danh mục từ câu nhập văn bản (PhoBERT).
2. POST /api/v1/ai/forecast: Dự báo chi tiêu 7 ngày tiếp theo (LSTM).
"""

import os
import sys
import pickle
import torch

# Cấu hình UTF-8 cho console Windows
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass
import torch.nn as nn
import numpy as np
import easyocr
import cv2
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
from transformers import AutoTokenizer, AutoModelForSequenceClassification
from bill_parser import parse_receipt_ocr_results

# Khởi tạo App FastAPI
app = FastAPI(
    title="FinWise AI Microservice",
    description="Hệ thống AI phân loại chi tiêu tiếng Việt và dự báo dòng tiền",
    version="1.0.0"
)

# Cấu hình CORS để Flutter và Node.js gọi thoải mái
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_DIR = os.path.dirname(__file__)
PHOBERT_DIR = os.path.join(BASE_DIR, "models", "phobert_classifier")
LSTM_DIR = os.path.join(BASE_DIR, "models", "lstm_forecaster")

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# Định nghĩa Kiến trúc LSTM
class ExpenseLSTM(nn.Module):
    def __init__(self, input_size=1, hidden_size=64, num_layers=2, output_size=7, dropout=0.2):
        super(ExpenseLSTM, self).__init__()
        self.lstm = nn.LSTM(
            input_size=input_size,
            hidden_size=hidden_size,
            num_layers=num_layers,
            batch_first=True,
            dropout=dropout if num_layers > 1 else 0
        )
        self.fc = nn.Sequential(
            nn.Linear(hidden_size, 32),
            nn.ReLU(),
            nn.Linear(32, output_size)
        )

    def forward(self, x):
        out, _ = self.lstm(x)
        last_step = out[:, -1, :]
        return self.fc(last_step)

# Biến toàn cục lưu trữ Model trong RAM
phobert_tokenizer = None
phobert_model = None
lstm_model = None
lstm_scaler = None
ocr_reader = None

CATEGORIES_NAMES_VN = {
    "AN_UONG": "Ăn uống & Cà phê",
    "DI_LAI": "Di chuyển & Đi lại",
    "MUA_SAM": "Mua sắm & Đồ dùng",
    "HOA_DON": "Hóa đơn & Tiện ích",
    "NHA_O": "Nhà ở & Tiền trọ",
    "GIAI_TRI": "Giải trí & Sở thích",
    "SUC_KHOE": "Sức khỏe & Y tế",
    "HOC_TAP": "Học tập & Phát triển",
    "TIET_KIEM_DAU_TU": "Tiết kiệm & Đầu tư",
    "THU_NHAP": "Thu nhập & Lương"
}

# Bổ trợ từ khóa tiếng Anh phổ biến để nhận diện danh mục chính xác tuyệt đối trên hóa đơn song ngữ/tiếng Anh
ENGLISH_DOMAIN_KEYWORDS = {
    "AN_UONG": [
        "coffee", "cafe", "tea", "starbucks", "highlands", "kfc", "mcdonald", "lotteria", "jollibee",
        "burger", "pizza", "restaurant", "bar", "bakery", "food", "drink", "bistro", "pub", "grill",
        "bbq", "steak", "sushi", "noodles", "latte", "cappuccino", "espresso", "milk tea", "cake", "ice cream"
    ],
    "DI_LAI": [
        "grab", "be", "gojek", "taxi", "uber", "flight", "airline", "vietjet", "vietnam airlines",
        "petrol", "gasoline", "fuel", "parking", "toll", "bus", "train", "ticket"
    ],
    "MUA_SAM": [
        "mart", "supermarket", "mall", "shopee", "lazada", "tiki", "zara", "uniqlo", "h&m",
        "fashion", "shoes", "clothes", "store", "shop", "convenience", "circle k", "family mart", "7-eleven"
    ],
    "GIAI_TRI": [
        "cinema", "movie", "cgv", "lotte cinema", "bhd", "game", "steam", "playstation", "netflix",
        "spotify", "concert", "karaoke", "billiard", "bowling"
    ],
    "SUC_KHOE": [
        "pharmacy", "drug", "hospital", "clinic", "dental", "medicine", "doctor", "gym", "fitness", "yoga"
    ],
    "NHA_O": [
        "hotel", "hostel", "homestay", "resort", "airbnb", "apartment", "rent", "room"
    ],
    "HOA_DON": [
        "electric", "water", "internet", "viettel", "vnpt", "fpt", "telecom", "utility", "bill"
    ],
    "HOC_TAP": [
        "book", "bookstore", "course", "udemy", "coursera", "school", "tuition", "academy", "library"
    ]
}


@app.on_event("startup")
def load_models():
    """Tải trước các mô hình vào bộ nhớ RAM/VRAM khi server khởi động."""
    global phobert_tokenizer, phobert_model, lstm_model, lstm_scaler, ocr_reader
    print(f"[*] Đang khởi động AI Service trên thiết bị: {device}...")

    # 1. Tải PhoBERT
    if os.path.exists(os.path.join(PHOBERT_DIR, "config.json")):
        print("[*] Đang nạp mô hình PhoBERT...")
        phobert_tokenizer = AutoTokenizer.from_pretrained(PHOBERT_DIR)
        phobert_model = AutoModelForSequenceClassification.from_pretrained(PHOBERT_DIR)
        phobert_model.to(device)
        phobert_model.eval()
        print("[+] Mô hình PhoBERT đã sẵn sàng!")
    else:
        print("[!] Cảnh báo: Chưa tìm thấy weights PhoBERT đã train. Vui lòng chạy train_phobert.py.")

    # 2. Tải LSTM
    lstm_weights = os.path.join(LSTM_DIR, "lstm_model.pth")
    scaler_file = os.path.join(LSTM_DIR, "scaler.pkl")
    if os.path.exists(lstm_weights) and os.path.exists(scaler_file):
        print("[*] Đang nạp mô hình LSTM Forecaster...")
        with open(scaler_file, "rb") as f:
            lstm_scaler = pickle.load(f)

        lstm_model = ExpenseLSTM(input_size=1, hidden_size=64, num_layers=2, output_size=7)
        lstm_model.load_state_dict(torch.load(lstm_weights, map_location=device, weights_only=True))
        lstm_model.to(device)
        lstm_model.eval()
        print("[+] Mô hình LSTM Forecaster đã sẵn sàng!")
    else:
        print("[!] Cảnh báo: Chưa tìm thấy weights LSTM đã train. Vui lòng chạy train_lstm.py.")

    # 3. Tải EasyOCR (CRAFT + CRNN Tiếng Việt)
    try:
        print("[*] Đang nạp mô hình OCR (EasyOCR CRAFT-CRNN)...")
        use_gpu = torch.cuda.is_available()
        ocr_reader = easyocr.Reader(['vi', 'en'], gpu=use_gpu, verbose=False)
        print(f"[+] Mô hình EasyOCR đã sẵn sàng (GPU: {use_gpu})!")
    except Exception as e:
        print(f"[!] Cảnh báo nạp EasyOCR: {e}")

# ==============================================================================
# SCHEMAS (Định dạng Request / Response)
# ==============================================================================

class ClassifyRequest(BaseModel):
    text: str

class ClassifyResponse(BaseModel):
    category_code: str
    category_name: str
    confidence: float

class ForecastRequest(BaseModel):
    daily_expenses: List[float] # Mảng ít nhất 30 ngày chi tiêu gần nhất

class ForecastResponse(BaseModel):
    predicted_next_7_days: List[float]
    total_forecast: float
    average_daily_forecast: float
    warning_level: str
    message: str

# ==============================================================================
# ENDPOINTS
# ==============================================================================

@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "device": str(device),
        "gpu_name": torch.cuda.get_device_name(0) if torch.cuda.is_available() else "None",
        "phobert_loaded": phobert_model is not None,
        "lstm_loaded": lstm_model is not None,
        "ocr_loaded": ocr_reader is not None
    }

@app.post("/api/v1/ai/scan-bill")
async def scan_bill(file: UploadFile = File(...)):
    global ocr_reader
    if ocr_reader is None:
        try:
            ocr_reader = easyocr.Reader(['vi', 'en'], gpu=torch.cuda.is_available(), verbose=False)
        except Exception as e:
            raise HTTPException(status_code=503, detail=f"Không thể khởi tạo mô hình OCR: {str(e)}")

    try:
        image_bytes = await file.read()
        if not image_bytes:
            raise HTTPException(status_code=400, detail="File ảnh rỗng!")

        # 1. Chuyển đổi bytes thành ảnh OpenCV để hỗ trợ xử lý xoay chiều
        nparr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        # 1.1 Quét ở góc ảnh ban đầu (0 độ)
        ocr_results = ocr_reader.readtext(img if img is not None else image_bytes)
        parsed = parse_receipt_ocr_results(ocr_results)
        
        # 1.2 Cơ chế Tự Động Xoay (Smart Auto-Orientation):
        # Nếu ảnh bị chụp dốc ngược (180 độ) hoặc xoay nghiêng (90/270 độ):
        # Độ tin cậy OCR sẽ rất thấp (< 0.45) hoặc không tìm thấy tổng tiền.
        # Hệ thống tự động thử xoay ảnh để tìm góc đọc chuẩn nhất!
        avg_conf = sum(r[2] for r in ocr_results) / len(ocr_results) if ocr_results else 0.0
        if img is not None and (avg_conf < 0.45 or parsed.get("total_amount", 0) == 0):
            # Thử xoay 180 độ (trường hợp chụp ngược phổ biến nhất)
            img_180 = cv2.rotate(img, cv2.ROTATE_180)
            res_180 = ocr_reader.readtext(img_180)
            conf_180 = sum(r[2] for r in res_180) / len(res_180) if res_180 else 0.0
            parsed_180 = parse_receipt_ocr_results(res_180)

            # Nếu xoay 180 độ tìm thấy tổng tiền hoặc độ tin cậy cao hơn hẳn
            if (conf_180 > avg_conf + 0.15) or (parsed.get("total_amount", 0) == 0 and parsed_180.get("total_amount", 0) > 0):
                ocr_results = res_180
                parsed = parsed_180
                avg_conf = conf_180
            # Nếu vẫn chưa tìm thấy tiền, thử tiếp các góc xoay ngang (90 độ, 270 độ)
            elif parsed.get("total_amount", 0) == 0:
                for rot in [cv2.ROTATE_90_CLOCKWISE, cv2.ROTATE_90_COUNTERCLOCKWISE]:
                    img_rot = cv2.rotate(img, rot)
                    res_rot = ocr_reader.readtext(img_rot)
                    parsed_rot = parse_receipt_ocr_results(res_rot)
                    if parsed_rot.get("total_amount", 0) > 0:
                        ocr_results = res_rot
                        parsed = parsed_rot
                        break
        
        # 3. Sử dụng PhoBERT kết hợp Bộ từ điển Song ngữ Anh - Việt để dự đoán danh mục
        cat_code = "MUA_SAM"
        confidence = 0.5
        
        text_for_phobert = f"{parsed['merchant']} {' '.join(parsed['all_lines'][1:6])}".strip()
        text_lower = text_for_phobert.lower()

        # Kiểm tra từ khóa thương hiệu / món hàng tiếng Anh phổ biến
        english_match_code = None
        for code, kw_list in ENGLISH_DOMAIN_KEYWORDS.items():
            if any(kw in text_lower for kw in kw_list):
                english_match_code = code
                break

        if phobert_model and phobert_tokenizer and text_for_phobert:
            try:
                inputs = phobert_tokenizer(
                    text_for_phobert,
                    truncation=True,
                    padding="max_length",
                    max_length=64,
                    return_tensors="pt"
                ).to(device)
                with torch.no_grad():
                    outputs = phobert_model(**inputs)
                    probs = torch.softmax(outputs.logits, dim=1).cpu().numpy()[0]
                    pred_idx = int(np.argmax(probs))
                    confidence = float(probs[pred_idx])
                    cat_code = phobert_model.config.id2label[pred_idx]
            except Exception as pe:
                print(f"[!] Lỗi khi chạy PhoBERT cho hóa đơn: {pe}")

        # Nếu có từ khóa tiếng Anh rõ rệt và PhoBERT chưa chắc chắn (< 0.75), ưu tiên danh mục tiếng Anh
        if english_match_code and (confidence < 0.75 or cat_code == "MUA_SAM"):
            cat_code = english_match_code
            confidence = max(confidence, 0.90)
                
        cat_name = CATEGORIES_NAMES_VN.get(cat_code, "Mua sắm & Đồ dùng")


        return {
            "success": True,
            "merchant": parsed["merchant"],
            "total_amount": parsed["total_amount"],
            "date": parsed["date"],
            "category_code": cat_code,
            "category_name": cat_name,
            "confidence": round(confidence, 4),
            "raw_text": parsed["raw_text"],
            "line_count": len(parsed["all_lines"])
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Lỗi xử lý hóa đơn OCR: {str(e)}")

@app.post("/api/v1/ai/classify", response_model=ClassifyResponse)
def classify_transaction(req: ClassifyRequest):
    if not phobert_model or not phobert_tokenizer:
        raise HTTPException(
            status_code=503,
            detail="Mô hình PhoBERT chưa được nạp. Hãy chạy file train_phobert.py trước!"
        )

    text = req.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="Văn bản không được để trống!")

    inputs = phobert_tokenizer(
        text,
        truncation=True,
        padding="max_length",
        max_length=64,
        return_tensors="pt"
    ).to(device)

    with torch.no_grad():
        outputs = phobert_model(**inputs)
        probs = torch.softmax(outputs.logits, dim=1).cpu().numpy()[0]
        pred_idx = int(np.argmax(probs))
        confidence = float(probs[pred_idx])

    cat_code = phobert_model.config.id2label[pred_idx]
    cat_name = CATEGORIES_NAMES_VN.get(cat_code, cat_code)

    return ClassifyResponse(
        category_code=cat_code,
        category_name=cat_name,
        confidence=round(confidence, 4)
    )

@app.post("/api/v1/ai/forecast", response_model=ForecastResponse)
def forecast_expenses(req: ForecastRequest):
    if not lstm_model or not lstm_scaler:
        raise HTTPException(
            status_code=503,
            detail="Mô hình LSTM chưa được nạp. Hãy chạy file train_lstm.py trước!"
        )

    expenses = req.daily_expenses
    if len(expenses) < 30:
        raise HTTPException(
            status_code=400,
            detail=f"Cần cung cấp dữ liệu chi tiêu của ít nhất 30 ngày gần nhất (Hiện có: {len(expenses)} ngày)."
        )

    # Lấy 30 ngày gần nhất
    recent_30_days = np.array(expenses[-30:]).reshape(-1, 1)
    scaled_input = lstm_scaler.transform(recent_30_days)
    tensor_input = torch.tensor(scaled_input, dtype=torch.float32).unsqueeze(0).to(device) # Shape: [1, 30, 1]

    with torch.no_grad():
        pred_scaled = lstm_model(tensor_input).cpu().numpy() # Shape: [1, 7]

    # Inverse transform
    pred_vnd = lstm_scaler.inverse_transform(pred_scaled.reshape(-1, 1)).flatten()
    pred_vnd = [max(0.0, round(float(v), -3)) for v in pred_vnd] # Làm tròn đến hàng nghìn đồng

    total_pred = sum(pred_vnd)
    avg_daily = total_pred / 7.0

    # Phân tích mức độ cảnh báo
    past_avg = np.mean(expenses[-30:])
    ratio = avg_daily / past_avg if past_avg > 0 else 1.0

    if ratio > 1.3:
        warning_level = "CAO"
        message = f"Cảnh báo: Chi tiêu 7 ngày tới dự kiến tăng {int((ratio-1)*100)}% so với trung bình tháng qua. Hãy thắt chặt ví tiền!"
    elif ratio > 1.1:
        warning_level = "TRUNG_BINH"
        message = "Chi tiêu tuần tới có xu hướng tăng nhẹ. Hãy lưu ý các khoản mua sắm và giải trí."
    else:
        warning_level = "AN_TOAN"
        message = "Dòng tiền dự kiến trong 7 ngày tới ở mức ổn định và an toàn."

    return ForecastResponse(
        predicted_next_7_days=pred_vnd,
        total_forecast=total_pred,
        average_daily_forecast=round(avg_daily, 0),
        warning_level=warning_level,
        message=message
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=8000, reload=True)
