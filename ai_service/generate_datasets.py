"""
Script sinh bộ dữ liệu lớn mô phỏng cho bài toán Quản lý tài chính cá nhân tiếng Việt:
1. Dataset NLP: transactions_vn.csv (~10.000+ mẫu) với 10 nhãn danh mục phong phú.
2. Dataset Chuỗi thời gian: daily_expense_timeseries.csv (Chuỗi chi tiêu liên tục 2 năm có chu kỳ lương, cuối tuần, lễ Tết).
"""

import os
import random
import pandas as pd
import numpy as np
from datetime import datetime, timedelta

# Đảm bảo thư mục dataset tồn tại
DATASET_DIR = os.path.join(os.path.dirname(__file__), "dataset")
os.makedirs(DATASET_DIR, exist_ok=True)

# ==============================================================================
# 1. BỘ DỮ LIỆU NLP: PHÂN LOẠI CHI TIÊU TIẾNG VIỆT (10 DANH MỤC)
# ==============================================================================

CATEGORIES_MAP = {
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

# Từ vựng & Mẫu câu mở rộng cho từng danh mục
TEMPLATES = {
    "AN_UONG": {
        "items": [
            "cơm tấm sườn bì chả", "phở bò tái nạm", "bún bò huế", "bún đậu mắm tôm", "bánh mì thịt chả",
            "cơm gà xối mỡ", "lẩu haidilao", "thịt nướng kpub", "buffet manwah", "pizza hut",
            "gà rán kfc", "jollibee", "lotteria", "trà sữa phúc long", "trà đào the coffee house",
            "cà phê muối", "matcha latte phê la", "highlands coffee", "cà phê đen đá", "bạc xỉu",
            "bánh tráng trộn", "nem chua rán", "chè sầu riêng", "ốc luộc chấm mắm", "trứng vịt lộn",
            "mua rau muống thịt heo ở winmart", "đi chợ mua cá chép và rau củ", "mua hoa quả sạch",
            "ăn trưa văn phòng", "ăn tối với người yêu", "khao cả phòng trà sữa", "mua bánh mì ăn sáng",
            "ăn hủ tiếu nam vang", "ăn miến lươn", "cơm rang dưa bò", "bún chả hà nội", "bánh xèo miền tây"
        ],
        "verbs": ["Ăn", "Uống", "Mua", "Order", "Đặt qua shopeefood", "Đi ăn", "Khao", "Thanh toán", "Tiêu tiền"]
    },
    "DI_LAI": {
        "items": [
            "đổ xăng ron 95", "đổ xăng đầy bình xe lead", "xăng xe máy wave", "nạp tiền xăng dầu",
            "bắt grab bike đi học", "đi be bike sang nhà bạn", "book grab car ra sân bay nội bài",
            "taxi xanh sm đi công việc", "vé xe buýt tháng", "nạp thẻ xe bus điện vinbus",
            "phí gửi xe vincom", "gửi xe qua đêm bệnh viện", "nạp tiền tài khoản vetc cao tốc",
            "nạp thẻ epass", "thay nhớt motul cho xe", "bảo dưỡng định kỳ xe máy", "vá lốp xe cán đinh",
            "rửa xe ô tô", "rửa xe máy bọt tuyết", "mua vé tàu hỏa về quê", "vé máy bay vietjet khứ hồi",
            "vé xe đò phương trang đi đà lạt", "thuê xe máy tự lái"
        ],
        "verbs": ["Đi", "Đặt", "Đổ", "Bắt", "Thanh toán", "Nạp", "Trả tiền", "Chi phí"]
    },
    "MUA_SAM": {
        "items": [
            "áo phông trơn uniqlo", "quần jean ống suông", "áo sơ mi trắng công sở", "váy hoa mùa hè",
            "giày sneaker nike air force", "dép crocs quai ngang", "giày chạy bộ adidas",
            "son môi 3ce", "kem chống nắng anessa", "nước tẩy trang bioderma", "sữa rửa mặt cerave",
            "chuột không dây logitech", "bàn phím cơ núm xoay", "tai nghe bluetooth soundpeats",
            "ốp lưng iphone", "sạc dự phòng anker 20000mah", "săn sale shopee 11.11",
            "đơn hàng tiktok shop", "đơn hàng lazada giao tận nơi", "kệ để đồ trang trí phòng",
            "máy sấy tóc panasonic", "nồi chiên không dầu", "mua balo đi làm thời trang"
        ],
        "verbs": ["Mua", "Sắm", "Order", "Săn sale", "Thanh toán", "Chi mua"]
    },
    "HOA_DON": {
        "items": [
            "tiền điện sinh hoạt evn", "hóa đơn tiền nước tháng này", "gói cước internet fpt wifi",
            "mạng internet cáp quang viettel", "đóng tiền truyền hình cáp", "gia hạn netflix 1 tháng",
            "gói youtube premium cá nhân", "tài khoản spotify gia đình", "nạp thẻ cào viettel 100k",
            "nạp tiền điện thoại vina 50k", "thanh toán cước trả sau mobifone", "phí quản lý tài khoản ngân hàng",
            "phí thường niên thẻ visa tín dụng", "tiền dịch vụ icloud 200gb"
        ],
        "verbs": ["Đóng", "Thanh toán", "Nạp", "Gia hạn", "Trả cước"]
    },
    "NHA_O": {
        "items": [
            "tiền thuê trọ tháng 10", "tiền thuê căn hộ chung cư", "đặt cọc tiền nhà 2 tháng",
            "phí dịch vụ quản lý chung cư", "tiền vệ sinh thu gom rác cả năm", "phí bảo trì thang máy",
            "thuê thợ sửa ống nước bị rò rỉ", "thay bóng đèn phòng khách bị cháy", "mua rèm cửa che nắng",
            "sơn lại tường phòng ngủ", "tiền gửi xe chung cư hàng tháng", "tiền bảo vệ an ninh tòa nhà"
        ],
        "verbs": ["Đóng", "Trả", "Thanh toán", "Chi tiền", "Chuyển khoản"]
    },
    "GIAI_TRI": {
        "items": [
            "vé xem phim cgv suất tối", "vé xem phim lotte cinema kèm bắp nước", "hát karaoke với nhóm lớp",
            "đi bắn bida giải trí cuối tuần", "nạp thẻ game garena", "nạp nguyên thạch genshin impact",
            "mua game sale trên steam", "vé vào cổng khu du lịch suối tiên", "chuyến cắm trại camping hồ dầu tiếng",
            "đi bar quẩy cùng hội bạn", "đi pub ngồi chill nghe acoustic", "vé xem live concert",
            "mua vé tour du lịch đà nẵng", "thuê lều trại dã ngoại"
        ],
        "verbs": ["Đi", "Xem", "Chơi", "Nạp", "Mua vé", "Chi cho"]
    },
    "SUC_KHOE": {
        "items": [
            "mua thuốc cảm sốt panadol nhà thuốc long châu", "khám tổng quát tại bệnh viện đại học y dược",
            "nhổ 2 chiếc răng khôn hàm dưới", "cạo vôi răng và hàn răng sâu", "mua viên uống vitamin c và kẽm",
            "thực phẩm bổ sung whey protein", "đóng gói tập gym 6 tháng the new gym", "thẻ tập yoga hàng tháng",
            "mua máy đo huyết áp omron cho bố mẹ", "mua hộp khẩu trang y tế và cồn sát khuẩn",
            "khám da liễu trị mụn", "tiền thuốc nhỏ mắt và nước muối sinh lý"
        ],
        "verbs": ["Mua", "Đi khám", "Chi tiền", "Thanh toán viện phí", "Đóng học"]
    },
    "HOC_TAP": {
        "items": [
            "đóng học phí tín chỉ học kỳ 1", "lệ phí thi chứng chỉ ielts idp", "lệ phí đăng ký thi toeic 4 kỹ năng",
            "mua giáo trình tiếng anh chuyên ngành", "sách lập trình python cơ bản", "mua sách tại nhà sách fahasa",
            "khóa học lập trình flutter trên udemy", "khóa học data analysis trên coursera", "mua sổ tay ghi chép và bút viết",
            "đăng ký lớp học giao tiếp tiếng trung", "học phí khóa luyện thi cao học", "mua tài khoản chatgpt plus hỗ trợ học tập"
        ],
        "verbs": ["Đóng", "Nộp", "Mua", "Đăng ký", "Chi tiền cho"]
    },
    "TIET_KIEM_DAU_TU": {
        "items": [
            "gửi tiết kiệm online vietcombank 6 tháng", "trích tiền vào sổ tiết kiệm tích lũy",
            "mua 1 chỉ vàng nhẫn sjc", "nạp tiền vào tài khoản chứng khoán vps", "mua thêm cổ phiếu fpt và vnm",
            "đầu tư tích lũy định kỳ ứng dụng tikop", "gửi tiền vào ví thần tài momo hưởng lãi",
            "nạp tiền ví tài lũy finhay", "mua chứng chỉ quỹ dcds", "chuyển tiền vào tài khoản dự phòng khẩn cấp"
        ],
        "verbs": ["Gửi", "Trích", "Mua", "Đầu tư", "Nạp tích lũy"]
    },
    "THU_NHAP": {
        "items": [
            "nhận lương chính thức công ty chuyển khoản", "tiền lương làm thêm part-time", "nhận tiền thưởng kpi quý",
            "tiền làm dự án freelance thiết kế app", "bố mẹ chuyển tiền sinh hoạt phí tháng này",
            "thanh lý laptop cũ được tiền mặt", "bán xe máy cũ lấy tiền", "nhận tiền lãi tiết kiệm kỳ hạn",
            "nhận cổ tức tiền mặt chứng khoán", "tiền hoa hồng môi giới", "bạn trả nợ tiền vay tháng trước",
            "tiền lì xì đầu năm", "trúng thưởng mini game"
        ],
        "verbs": ["Nhận", "Được cộng", "Thu về", "Được chuyển", "Kiếm được"]
    }
}

PRICE_FORMATS = [
    "{amount}k", "{amount}.000đ", "{amount}000 vnd", "{amount}k vnd",
    "{amount} ngàn", "{amount} nghìn đồng", "{amount} đồng", ""
]

def generate_amount(category):
    """Sinh số tiền hợp lý theo từng danh mục."""
    if category == "AN_UONG":
        return random.choice([25, 30, 35, 40, 45, 50, 60, 75, 120, 250, 350, 500])
    elif category == "DI_LAI":
        return random.choice([15, 20, 30, 50, 70, 100, 150, 250, 500, 1200])
    elif category == "MUA_SAM":
        return random.choice([80, 150, 250, 350, 500, 750, 1200, 2500])
    elif category == "HOA_DON":
        return random.choice([50, 100, 200, 350, 500, 750, 1200])
    elif category == "NHA_O":
        return random.choice([1500, 2000, 2500, 3000, 3500, 4500, 6000])
    elif category == "GIAI_TRI":
        return random.choice([50, 90, 120, 200, 350, 500, 1000])
    elif category == "SUC_KHOE":
        return random.choice([40, 80, 150, 300, 500, 1000, 2000])
    elif category == "HOC_TAP":
        return random.choice([100, 250, 500, 1500, 3000, 5000])
    elif category == "TIET_KIEM_DAU_TU":
        return random.choice([1000, 2000, 5000, 10000, 20000])
    elif category == "THU_NHAP":
        return random.choice([3000, 5000, 8000, 12000, 15000, 20000, 25000])
    return 100

def generate_nlp_dataset(total_samples=12000):
    """Sinh bộ dữ liệu NLP gồm 10.000 - 12.000 câu giao dịch tiếng Việt."""
    print(f"[*] Bắt đầu sinh bộ dữ liệu NLP ({total_samples} mẫu)...")
    data = []
    categories = list(TEMPLATES.keys())
    samples_per_cat = total_samples // len(categories)

    for cat in categories:
        items = TEMPLATES[cat]["items"]
        verbs = TEMPLATES[cat]["verbs"]

        for _ in range(samples_per_cat):
            item = random.choice(items)
            verb = random.choice(verbs)
            amt = generate_amount(cat)
            fmt = random.choice(PRICE_FORMATS)
            amt_str = fmt.format(amount=amt) if fmt else ""

            # Tạo phong cách viết câu tự nhiên phong phú (chữ hoa/chữ thường, có tiền hoặc không tiền, có từ đệm)
            style = random.randint(1, 6)
            if style == 1:
                sentence = f"{verb} {item} {amt_str}".strip()
            elif style == 2:
                sentence = f"{item} hết {amt_str}".strip()
            elif style == 3:
                sentence = f"{verb} {item}".strip()
            elif style == 4:
                sentence = f"{item} {amt_str}".strip()
            elif style == 5:
                prefix = random.choice(["Vừa mới", "Hôm nay", "Sáng nay", "Tối qua", "Chiều nay", "Chi phí"])
                sentence = f"{prefix} {verb.lower()} {item} {amt_str}".strip()
            else:
                sentence = f"{item}".strip()

            # Chuẩn hóa ngẫu nhiên (chữ thường hoặc giữ nguyên)
            if random.random() > 0.3:
                sentence = sentence.lower()

            data.append({"text": sentence, "category": cat})

    # Xáo trộn dữ liệu
    random.shuffle(data)
    df = pd.DataFrame(data)
    nlp_path = os.path.join(DATASET_DIR, "transactions_vn.csv")
    df.to_csv(nlp_path, index=False, encoding="utf-8-sig")
    print(f"[+] Đã lưu dataset NLP thành công: {nlp_path} ({len(df)} dòng)")
    return df

# ==============================================================================
# 2. BỘ DỮ LIỆU CHUỖI THỜI GIAN: DỰ BÁO CHI TIÊU HÀNG NGÀY (LSTM)
# ==============================================================================

def generate_timeseries_dataset(days=730):
    """
    Sinh chuỗi dữ liệu chi tiêu hàng ngày liên tiếp 2 năm (730 ngày).
    Mô phỏng chu kỳ thực tế:
    - Ngày trong tuần: Chi tiêu sinh hoạt cơ bản.
    - Cuối tuần (T7, CN): Chi tiêu tăng 40-70% (vui chơi, mua sắm).
    - Đầu tháng (ngày 1-5): Trả tiền nhà, đóng hóa đơn, tiền tăng vọt.
    - Dịp lễ, Tết: Chi tiêu đột biến.
    """
    print(f"[*] Bắt đầu sinh bộ dữ liệu Chuỗi thời gian ({days} ngày)...")
    start_date = datetime.now() - timedelta(days=days)
    records = []

    for i in range(days):
        current_date = start_date + timedelta(days=i)
        day_of_week = current_date.weekday() # 0 = Monday, 6 = Sunday
        day_of_month = current_date.day
        month = current_date.month

        # Chi tiêu cơ bản mỗi ngày (200k - 350k: ăn uống, đi lại cơ bản)
        base_expense = random.uniform(180_000, 320_000)

        # Hệ số cuối tuần (Thứ 7 & CN)
        weekend_factor = 1.0
        if day_of_week in [5, 6]:
            weekend_factor = random.uniform(1.4, 2.2) # Cuối tuần đi ăn ngoài, giải trí

        # Hệ số đầu tháng (Ngày 1 đến 5: Trả tiền trọ 3-4 triệu + hóa đơn)
        monthly_fixed_bill = 0
        if day_of_month in [1, 2, 3]:
            # Chỉ tính 1 lần trong 3 ngày đầu tháng
            if day_of_month == 2:
                monthly_fixed_bill = random.uniform(3_000_000, 4_500_000)

        # Mùa lễ hội (Tháng 1 hoặc 2: Tết nguyên đán; Tháng 11: Black Friday; Tháng 12: Noel)
        seasonal_factor = 1.0
        if month in [1, 2]:
            seasonal_factor = 1.3
        elif month in [11, 12]:
            seasonal_factor = 1.25

        # Nhiễu ngẫu nhiên (Noise)
        noise = random.gauss(0, 30_000)

        # Tính tổng chi tiêu trong ngày
        daily_total = (base_expense * weekend_factor * seasonal_factor) + monthly_fixed_bill + noise
        daily_total = max(50_000, round(daily_total, -3)) # Làm tròn đến nghìn đồng, tối thiểu 50k

        records.append({
            "date": current_date.strftime("%Y-%m-%d"),
            "amount": int(daily_total),
            "day_of_week": day_of_week,
            "is_weekend": 1 if day_of_week in [5, 6] else 0,
            "day_of_month": day_of_month,
            "month": month
        })

    df_ts = pd.DataFrame(records)
    ts_path = os.path.join(DATASET_DIR, "daily_expense_timeseries.csv")
    df_ts.to_csv(ts_path, index=False, encoding="utf-8-sig")
    print(f"[+] Đã lưu dataset Chuỗi thời gian thành công: {ts_path} ({len(df_ts)} ngày)")
    return df_ts

if __name__ == "__main__":
    generate_nlp_dataset(total_samples=12000)
    generate_timeseries_dataset(days=730)
    print("\n===> HOÀN TẤT SINH DỮ LIỆU ĐÀO TẠO <===")
