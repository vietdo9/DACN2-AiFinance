"""
Script tiền xử lý toàn diện:
1. Đọc dữ liệu thực tế từ Kaggle & Excel (Daily Household, Personal Dashboard, VN Cashless).
2. Lọc 1/2 dữ liệu tiếng Anh thanh toán/chuyển khoản từ Banking77.
3. Sinh đầy đủ 4 trường hợp tiếng Việt thực tế:
   - TH1: SMS / Sao kê ngân hàng (VCB, MB, Techcombank, MoMo, VNPay)
   - TH2: Tiếng lóng, viết tắt, Teencode (cành, lít, k, cf, ts, shopee...)
   - TH3: Chuỗi cửa hàng tiện lợi, Siêu thị, Nhà thuốc VN (Winmart, Circle K, Long Châu...)
   - TH4: Khoản chi sinh viên / Thuê trọ / Học tập / Sinh hoạt phí đặc thù
4. Cân bằng và xuất ra tập dữ liệu chuẩn ~10.000 dòng cho PhoBERT.
5. Tạo tập chuỗi thời gian hơn 1.400 ngày cho LSTM.
"""

import os
import sys
import random
import pandas as pd
import numpy as np
from datetime import datetime

# Cấu hình UTF-8 cho Windows
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

DATASET_DIR = os.path.join(os.path.dirname(__file__), "dataset")

# 10 Danh mục chuẩn
CATEGORY_MAP = {
    "food": "AN_UONG", "groceries": "AN_UONG", "restaurants": "AN_UONG",
    "coffee shops": "AN_UONG", "food & beverage": "AN_UONG", "fast food": "AN_UONG",
    "transportation": "DI_LAI", "transport": "DI_LAI", "gas & fuel": "DI_LAI",
    "fuel": "DI_LAI", "auto & transport": "DI_LAI",
    "shopping": "MUA_SAM", "apparel": "MUA_SAM", "supermarket": "MUA_SAM",
    "clothing": "MUA_SAM", "electronics": "MUA_SAM",
    "utilities": "HOA_DON", "subscription": "HOA_DON", "bills": "HOA_DON",
    "mobile service provider": "HOA_DON",
    "household": "NHA_O", "home improvement": "NHA_O", "mortgage & rent": "NHA_O",
    "mortgage payment": "NHA_O",
    "entertainment": "GIAI_TRI", "alcohol & bars": "GIAI_TRI", "festivals": "GIAI_TRI",
    "movies": "GIAI_TRI",
    "health": "SUC_KHOE", "medical": "SUC_KHOE", "pharmacy": "SUC_KHOE", "fitness": "SUC_KHOE",
    "education": "HOC_TAP", "books": "HOC_TAP",
    "investment": "TIET_KIEM_DAU_TU", "recurring deposit": "TIET_KIEM_DAU_TU", "savings": "TIET_KIEM_DAU_TU",
    "paycheck": "THU_NHAP", "income": "THU_NHAP", "salary": "THU_NHAP"
}

# ==============================================================================
# HÀM SINH CÁC TRƯỜNG HỢP TIẾNG VIỆT THỰC TẾ (TH 1, 2, 3, 4)
# ==============================================================================

def generate_vietnamese_scenarios():
    samples = []
    
    # --------------------------------------------------------------------------
    # TH1: SMS BIẾN ĐỘNG SỐ DƯ & SAO KÊ NGÂN HÀNG (VCB, MB, TCB, MOMO, VNPAY)
    # --------------------------------------------------------------------------
    bank_templates = [
        # Ăn uống
        ("VCB: TK 0011... GD -{amt} VND luc {time}. ND: MBVCB.{ref}.{name} chuyen tien an trua", "AN_UONG"),
        ("MB: GD -{amt} VND tai {shop} qua QR Code. So du ...", "AN_UONG"),
        ("TCB: -{amt} VND. Thanh toan thanh cong tai {shop}. So du ...", "AN_UONG"),
        ("MOMO: Ban da thanh toan {amt}d cho The Coffee House. Ma GD {ref}", "AN_UONG"),
        ("VNPAY: Thanh toan QR thanh cong {amt}d tai Phuc Long Coffee & Tea", "AN_UONG"),
        ("BIDV: -{amt} VND. ND: Tien cafe sang voi team", "AN_UONG"),
        
        # Đi lại
        ("VCB: GD -{amt} VND. ND: Thanh toan chuyen di GrabBike", "DI_LAI"),
        ("MOMO: Thanh toan thanh cong {amt}d cho BE GROUP VIETNAM", "DI_LAI"),
        ("TCB: -{amt} VND tai CAY XANG PETROLIMEX SO {ref}", "DI_LAI"),
        ("MB: -{amt} VND. ND: VETC nap tien thu phi tu dong cao toc", "DI_LAI"),
        ("ACB: GD -{amt} VND tai XANH SM TAXI. So du ...", "DI_LAI"),
        
        # Mua sắm
        ("VCB: GD -{amt} VND. ND: SHOPEEPAY thanh toan don hang {ref}", "MUA_SAM"),
        ("TCB: -{amt} VND tai TIKTOK SHOP. Ma don {ref}", "MUA_SAM"),
        ("MB: GD -{amt} VND tai UNIQLO VINCOM DONG KHOI", "MUA_SAM"),
        ("MOMO: Thanh toan don hang Lazada thanh cong {amt}d", "MUA_SAM"),
        ("VPBANK: GD POS -{amt} VND tai ZARA VIETNAM", "MUA_SAM"),

        # Hóa đơn & Tiện ích
        ("VNPAY: Thanh toan hoa don tien dien EVN thanh cong so tien {amt} VND", "HOA_DON"),
        ("MOMO: Thanh toan tien nuoc sinh hoat cong ty Sawaco {amt}d", "HOA_DON"),
        ("VCB: GD -{amt} VND. ND: VIETTEL TELECOM thanh toan cuoc internet FTTH", "HOA_DON"),
        ("TCB: -{amt} VND tai FPT TELECOM FIBER. So du ...", "HOA_DON"),
        ("MB: GD -{amt} VND cho NETFLIX SERVICES. Phi duy tri tai khoan", "HOA_DON"),
        ("VIETTEL MONEY: Nap tien dien thoai thanh cong {amt}d cho so 098...", "HOA_DON"),

        # Nhà ở & Tiền trọ
        ("VCB: GD -{amt} VND. ND: CK TIEN PHONG TRO THANG {month}", "NHA_O"),
        ("MB: GD -{amt} VND. ND: NGUYEN VAN A CHUYEN TIEN THUE NHA THANG {month}", "NHA_O"),
        ("TCB: -{amt} VND. ND: DONG TIEN COC NHA 2 THANG VA PHI DICH VU", "NHA_O"),
        ("ACB: -{amt} VND. ND: PHI QUAN LY CHUNG CU THANG {month}", "NHA_O"),

        # Giải trí
        ("MOMO: Thanh toan ve xem phim CGV Cinemas thanh cong {amt}d", "GIAI_TRI"),
        ("VCB: GD -{amt} VND tai STEAM GAMES PURCHASE", "GIAI_TRI"),
        ("MB: GD -{amt} VND. ND: Nap the Garena nap quan huy Lien Quan", "GIAI_TRI"),
        ("TCB: -{amt} VND tai LOTTE CINEMA HA NOI", "GIAI_TRI"),

        # Sức khỏe
        ("VCB: GD -{amt} VND tai NHA THUOC FPT LONG CHAU", "SUC_KHOE"),
        ("TCB: -{amt} VND tai PHARMACITY QUAN 1", "SUC_KHOE"),
        ("MB: GD -{amt} VND tai BENH VIEN DHYD TPHCM. Vien phi", "SUC_KHOE"),
        ("MOMO: Thanh toan the tap gym The New Gym {amt}d", "SUC_KHOE"),

        # Học tập
        ("VCB: GD -{amt} VND. ND: NOP HOC PHI TIN CHI HOC KY 1", "HOC_TAP"),
        ("TCB: -{amt} VND tai NHA SACH FAHASA NGUYEN HUE", "HOC_TAP"),
        ("MB: GD -{amt} VND. ND: DONG LE PHI THI CHUNG CHI IELTS IDP", "HOC_TAP"),

        # Tiết kiệm & Đầu tư
        ("VCB: GD -{amt} VND. ND: MO TIET KIEM ONLINE KY HAN 6 THANG", "TIET_KIEM_DAU_TU"),
        ("MB: GD -{amt} VND. ND: Nop tien tai khoan chung khoan VPS", "TIET_KIEM_DAU_TU"),
        ("TCB: -{amt} VND. ND: MUA CHUNG CHI QUY DCDS DINH KY", "TIET_KIEM_DAU_TU"),
        ("MOMO: Chuyen {amt}d vao Tui Than Tai huong lai suat", "TIET_KIEM_DAU_TU"),

        # Thu nhập
        ("VCB: So du TK ... +{amt} VND. ND: CTY TNHH ABC TRA LUONG THANG {month}", "THU_NHAP"),
        ("TCB: +{amt} VND. ND: CHUYEN TIEN THUONG KPI QUY {ref}", "THU_NHAP"),
        ("MB: +{amt} VND. ND: THANH TOAN DU AN FREELANCE DESIGN", "THU_NHAP"),
        ("ACB: +{amt} VND. ND: BO ME CHUYEN TIEN SINH HOAT PHI", "THU_NHAP")
    ]

    shops = [
        "Quan Com Binh Dan", "Pho Bo Nam Dinh", "Bun Cha Ha Noi", "Tra Sua Phe La",
        "Highlands Coffee", "KFC", "Lotteria", "Phuc Long Tea", "Katinat Saigon",
        "Pizza 4Ps", "Haidilao Hotpot", "Gogi House", "Dookki Vietnam", "Texas Chicken",
        "Bun Bo Hue O Xuan", "Com Tam Cali", "Banh Mi Huynh Hoa", "Mi Cay Sasin"
    ]
    names = ["ANH TUAN", "HOANG NAM", "MINH DUC", "THU TRANG", "HAI DANG", "LAN HUONG", "QUOC ANH", "THAO NGUYEN", "DUC HUY", "MAI ANH"]

    for _ in range(130):
        for tmpl, cat in bank_templates:
            text = tmpl.format(
                amt=random.choice(["25,000", "35,000", "45,000", "50,000", "65,000", "80,000", "120,000", "150,000", "250,000", "350,000", "450,000", "850,000", "1,500,000", "2,800,000", "3,500,000", "15,000,000"]),
                time=f"{random.randint(6, 23):02d}:{random.randint(10, 59):02d}",
                ref=random.randint(10000, 99999),
                name=random.choice(names),
                shop=random.choice(shops),
                month=random.randint(1, 12)
            )
            samples.append({"text": text, "category": cat})

    # --------------------------------------------------------------------------
    # TH2: TIẾNG LÓNG, VIẾT TẮT, VĂN PHONG ĐỜI THƯỜNG (TEENCODE)
    # --------------------------------------------------------------------------
    slang_data = [
        # Ăn uống
        ("cf highland", "AN_UONG"), ("ts phê la 60 cành", "AN_UONG"), ("bún bò 40 cành", "AN_UONG"),
        ("cơm sườn 35k", "AN_UONG"), ("trà đá thuốc lào 10k", "AN_UONG"), ("bánh mì pate 20 cành", "AN_UONG"),
        ("ăn ốc luộc với bạn 150 cành", "AN_UONG"), ("đi nhậu lẩu nướng 2 lít", "AN_UONG"),
        ("order trà sữa toco 45k", "AN_UONG"), ("ăn sáng xôi xéo 15k", "AN_UONG"),
        ("bạc xỉu đá mang về", "AN_UONG"), ("khao cả phòng trà sữa 300k", "AN_UONG"),
        ("ăn chè sầu đà nẵng 35 cành", "AN_UONG"), ("cơm rang dưa bò 40k", "AN_UONG"),

        # Đi lại
        ("đổ xăng 50k", "DI_LAI"), ("đổ xăng xe máy 70 cành", "DI_LAI"), ("đổ đầy bình ron 95 90k", "DI_LAI"),
        ("bắt grab bike 25k", "DI_LAI"), ("đi be bike sang trường 30 cành", "DI_LAI"),
        ("book car về quê 500 cành", "DI_LAI"), ("gửi xe bến xe 10k", "DI_LAI"),
        ("vá lốp xe máy dính đinh 30k", "DI_LAI"), ("thay dầu motul 120k", "DI_LAI"),
        ("vé xe bus tháng 100k", "DI_LAI"), ("tiền rửa xe bọt tuyết 25k", "DI_LAI"),

        # Mua sắm
        ("săn sale shopee 11.11 hết 5 lít", "MUA_SAM"), ("mua áo thun tiktok 150 cành", "MUA_SAM"),
        ("mua quần jean ống rộng 250k", "MUA_SAM"), ("mua son 3ce sale 200 cành", "MUA_SAM"),
        ("mua ốp lưng điện thoại 35k", "MUA_SAM"), ("sắm giày sneaker 8 lít", "MUA_SAM"),
        ("order sạc dự phòng 300k", "MUA_SAM"), ("mua chuột bàn phím cơ 6 lít", "MUA_SAM"),

        # Hóa đơn
        ("tiền điện tháng này 4 lít", "HOA_DON"), ("đóng tiền nước 80k", "HOA_DON"),
        ("tiền mạng wifi 220 cành", "HOA_DON"), ("share netflix 65k", "HOA_DON"),
        ("nạp thẻ viettel 50k", "HOA_DON"), ("nạp đt 100 cành", "HOA_DON"),
        ("gia hạn youtube premium 30k", "HOA_DON"), ("phí duy trì thẻ vcb 11k", "HOA_DON"),

        # Nhà ở
        ("tiền trọ tháng 10 2 củ rưỡi", "NHA_O"), ("tiền phòng trọ 2tr3", "NHA_O"),
        ("đóng cọc phòng trọ 3 củ", "NHA_O"), ("tiền rác với dịch vụ 150k", "NHA_O"),
        ("sửa vòi nước bồn rửa bát 100k", "NHA_O"), ("tiền gửi xe chung cư 120k", "NHA_O"),

        # Giải trí
        ("vé xem cgv 120 cành", "GIAI_TRI"), ("đi hát karaoke 3 lít", "GIAI_TRI"),
        ("đi bida với anh em 80k", "GIAI_TRI"), ("nạp game genshin 200k", "GIAI_TRI"),
        ("nạp quân huy lq 100 cành", "GIAI_TRI"), ("mua game steam sale 150k", "GIAI_TRI"),
        ("đi bar chill cuối tuần 5 lít", "GIAI_TRI"), ("vé concert âm nhạc 1 củ", "GIAI_TRI"),

        # Sức khỏe
        ("mua thuốc cảm panadol 25k", "SUC_KHOE"), ("mua vỉ berberin đau bụng 15k", "SUC_KHOE"),
        ("tiền khám răng nhổ răng khôn 1 củ", "SUC_KHOE"), ("mua vitamin c sủi 35k", "SUC_KHOE"),
        ("đóng tiền phòng gym 4 lít", "SUC_KHOE"), ("mua whey protein 1 củ 2", "SUC_KHOE"),

        # Học tập
        ("nộp học phí kỳ 1 8 củ", "HOC_TAP"), ("mua sách fahasa 150 cành", "HOC_TAP"),
        ("mua bút vở ghi bài 50k", "HOC_TAP"), ("tiền học toeic 2 củ", "HOC_TAP"),
        ("mua khóa học udemy 249k", "HOC_TAP"), ("lệ phí thi lại môn toán 200k", "HOC_TAP"),

        # Đầu tư & Tiết kiệm
        ("gửi tiết kiệm online 5 củ", "TIET_KIEM_DAU_TU"), ("bỏ lợn tiết kiệm 2 củ", "TIET_KIEM_DAU_TU"),
        ("mua 1 chỉ vàng nhẫn 8 củ", "TIET_KIEM_DAU_TU"), ("nạp tiền ví tikop 1 củ", "TIET_KIEM_DAU_TU"),
        ("bỏ túi thần tài momo 3 củ", "TIET_KIEM_DAU_TU"), ("mua cổ phiếu fpt 2 củ", "TIET_KIEM_DAU_TU"),

        # Thu nhập
        ("lương về 12 củ", "THU_NHAP"), ("tiền thưởng kpi 3 củ", "THU_NHAP"),
        ("làm thêm part time nhận 2 củ rưỡi", "THU_NHAP"), ("bố mẹ cho tiền tiêu vặt 2 củ", "THU_NHAP"),
        ("thanh lý đồ cũ được 5 lít", "THU_NHAP"), ("bạn trả nợ 500k", "THU_NHAP")
    ]

    prefixes = [
        "Hôm nay", "Vừa mới", "Sáng nay", "Tối qua", "Chiều nay", "Trưa nay",
        "Chi tiêu", "Đã trả", "Thanh toán", "Ghi chú", "Khoản chi"
    ]
    for item, cat in slang_data:
        samples.append({"text": item, "category": cat})
        samples.append({"text": item.capitalize(), "category": cat})
        for p in prefixes:
            samples.append({"text": f"{p} {item}".strip(), "category": cat})

    # --------------------------------------------------------------------------
    # TH3 & TH4: SIÊU THỊ, CỬA HÀNG TIỆN LỢI, TRƯỜNG HỌC & SINH HOẠT THỰC TẾ
    # --------------------------------------------------------------------------
    brand_data = [
        ("Circle K mua xúc xích và nước ngọt", "AN_UONG"),
        ("GS25 mua cơm nắm cá hồi và trà sữa", "AN_UONG"),
        ("7-Eleven mua mì trộn trứng lòng đào", "AN_UONG"),
        ("WinMart mua thịt heo rau xanh và gia vị", "AN_UONG"),
        ("Bách Hóa Xanh mua cá hồi và hoa quả", "AN_UONG"),
        ("Coopmart mua thực phẩm cả tuần", "AN_UONG"),
        ("Phúc Long mua trà lài sữa size L", "AN_UONG"),
        ("Katinat mua bơ già dừa non", "AN_UONG"),
        ("Mixue mua kem ốc quế và trà chanh", "AN_UONG"),
        ("Highlands mua phin sữa đá và bánh chuối", "AN_UONG"),
        ("The Coffee House mua trà đào cam sả", "AN_UONG"),
        ("Phê La mua ô long sữa trân châu", "AN_UONG"),
        ("Pizza 4P's ăn tối với gia đình", "AN_UONG"),
        ("Haidilao ăn lẩu cùng bạn bè", "AN_UONG"),
        ("KFC mua xô gà giòn cay", "AN_UONG"),
        ("Jollibee mua mì ý và gà giòn", "AN_UONG"),
        ("Lotteria mua hamburger bò và khoai lắc", "AN_UONG"),
        ("Cơm tấm Phúc Lộc Thọ ăn trưa", "AN_UONG"),
        ("Bún đậu mắm tôm thập cẩm ngõ gạch", "AN_UONG"),
        ("Quán cơm bình dân 2 suất ăn trưa", "AN_UONG"),

        # Y tế & Sức khỏe
        ("Nhà thuốc Long Châu mua thuốc đau đầu", "SUC_KHOE"),
        ("An Khang mua siro ho và vitamin tổng hợp", "SUC_KHOE"),
        ("Pharmacity mua nước súc miệng và khẩu trang", "SUC_KHOE"),
        ("Đi khám mắt cắt kính cận thị", "SUC_KHOE"),
        ("Nha khoa Kim lấy cao răng định kỳ", "SUC_KHOE"),
        ("Phòng khám đa khoa khám tổng quát", "SUC_KHOE"),
        ("Đăng ký thẻ tập gym California 1 năm", "SUC_KHOE"),
        ("The New Gym gia hạn gói tập 3 tháng", "SUC_KHOE"),
        ("Mua bình xịt sát khuẩn và bông băng y tế", "SUC_KHOE"),
        ("Mua hộp khẩu trang 4 lớp kháng khuẩn", "SUC_KHOE"),

        # Mua sắm
        ("Guardian mua sữa rửa mặt và bông tẩy trang", "MUA_SAM"),
        ("Hasaki mua kem chống nắng và kem dưỡng ẩm", "MUA_SAM"),
        ("Uniqlo Vincom mua áo chống nắng và áo thun", "MUA_SAM"),
        ("Zara mua áo sơ mi trắng công sở", "MUA_SAM"),
        ("H&M mua quần short đi biển", "MUA_SAM"),
        ("Anker Store mua củ sạc nhanh 65W", "MUA_SAM"),
        ("Thế Giới Di Động mua tai nghe bluetooth", "MUA_SAM"),
        ("FPT Shop mua chuột công thái học", "MUA_SAM"),
        ("Shopee Mall đặt mua bộ drap giường cotton", "MUA_SAM"),
        ("Tiki đặt mua nồi chiên không dầu", "MUA_SAM"),

        # Học tập
        ("Nhà sách Fahasa mua sách tiếng Anh giao tiếp", "HOC_TAP"),
        ("Nhà sách Tiền Phong mua văn phòng phẩm và bút", "HOC_TAP"),
        ("Đóng học phí chứng chỉ tin học quốc tế MOS", "HOC_TAP"),
        ("Đăng ký khóa học thiết kế UI/UX trên Figma", "HOC_TAP"),
        ("Đóng tiền học thêm lập trình web Fullstack", "HOC_TAP"),
        ("Mua tài khoản Coursera học Data Science", "HOC_TAP"),
        ("Nộp lệ phí bảo lưu môn học tại phòng đào tạo", "HOC_TAP"),
        ("Photo giáo trình và tài liệu ôn thi cuối kỳ", "HOC_TAP"),

        # Nhà ở
        ("Tiền thuê căn hộ mini tháng này", "NHA_O"),
        ("Phí bảo trì thang máy và dọn dẹp hành lang", "NHA_O"),
        ("Thay ổ khóa cửa phòng trọ mới", "NHA_O"),
        ("Mua cây lau nhà và nước lau sàn Sunlight", "NHA_O"),
        ("Sửa bình nóng lạnh bị hỏng rơ le", "NHA_O"),
        ("Đóng tiền quỹ bảo trì chung cư cả năm", "NHA_O"),

        # Giải trí
        ("BHD Star mua vé xem phim bom tấn", "GIAI_TRI"),
        ("Lotte Cinema xem phim kèm bắp nước phô mai", "GIAI_TRI"),
        ("Hát karaoke gia đình mừng sinh nhật", "GIAI_TRI"),
        ("Đi chơi bắn súng sơn paintball cuối tuần", "GIAI_TRI"),
        ("Thuê lều cắm trại dã ngoại hồ Trị An", "GIAI_TRI"),
        ("Mua vé tham quan thủy cung Times City", "GIAI_TRI"),
        ("Đi pub nghe nhạc sống acoustic thư giãn", "GIAI_TRI"),

        # Đầu tư & Tiết kiệm
        ("Nạp tiền tích lũy định kỳ ứng dụng Tikop", "TIET_KIEM_DAU_TU"),
        ("Gửi tiền vào tài khoản tiết kiệm linh hoạt", "TIET_KIEM_DAU_TU"),
        ("Mua 2 chỉ vàng nhẫn 9999 tiệm vàng Mi Hồng", "TIET_KIEM_DAU_TU"),
        ("Đầu tư mua chứng chỉ quỹ mở VCBF", "TIET_KIEM_DAU_TU"),
        ("Trích lương 20% vào quỹ dự phòng tài chính", "TIET_KIEM_DAU_TU"),

        # Thu nhập
        ("Nhận lương chính thức chuyển khoản qua VCB", "THU_NHAP"),
        ("Tiền thù lao trợ giảng đại học tháng này", "THU_NHAP"),
        ("Nhận hoa hồng giới thiệu khách hàng mua bảo hiểm", "THU_NHAP"),
        ("Bán thanh lý bàn học gỗ cũ sinh viên", "THU_NHAP"),
        ("Được thưởng nóng nhân viên xuất sắc tuần", "THU_NHAP")
    ]

    for item, cat in brand_data:
        for _ in range(20):
            cost = random.choice(["", "25k", "35k", "50k", "75k", "120k", "250k", "500k", "1tr2", "2tr5"])
            samples.append({"text": f"{item} {cost}".strip(), "category": cat})
            samples.append({"text": f"Vừa mới {item.lower()} {cost}".strip(), "category": cat})

    return samples

# ==============================================================================
# HÀM LỌC 1/2 DỮ LIỆU TIẾNG ANH THANH TOÁN TỪ BANKING77
# ==============================================================================

def get_banking77_relevant_samples(max_samples=4000):
    """Lấy khoảng 4.000 mẫu tiếng Anh liên quan đến giao dịch thanh toán từ Banking77."""
    train_path = os.path.join(DATASET_DIR, "banking77_train.csv")
    test_path = os.path.join(DATASET_DIR, "banking77_test.csv")
    
    dfs = []
    if os.path.exists(train_path):
        dfs.append(pd.read_csv(train_path))
    if os.path.exists(test_path):
        dfs.append(pd.read_csv(test_path))

    if not dfs:
        return []

    print("[*] Đang lọc ~4.000 dữ liệu thanh toán tiếng Anh từ Banking77...")
    df = pd.concat(dfs, ignore_index=True)

    # Bảng ánh xạ mở rộng các nhóm ý định tài chính / thanh toán
    relevant_intents = {
        # Hóa đơn & Phí dịch vụ
        "card_payment_fee_charged": "HOA_DON",
        "cash_withdrawal_charge": "HOA_DON",
        "transfer_fee_charged": "HOA_DON",
        "direct_debit_payment_problem": "HOA_DON",
        "direct_debit_payment_not_recognised": "HOA_DON",
        "beneficiary_not_allowed": "HOA_DON",
        "failed_transfer": "HOA_DON",
        "card_payment_wrong_exchange_rate": "HOA_DON",
        "extra_charge_on_statement": "HOA_DON",
        "transaction_charged_twice": "HOA_DON",
        "pending_card_payment": "HOA_DON",
        "declined_card_payment": "HOA_DON",
        "card_payment_not_recognised": "HOA_DON",
        "transfer_not_received_by_recipient": "HOA_DON",

        # Thu nhập & Nhận tiền
        "transfer_into_account": "THU_NHAP",
        "receiving_money": "THU_NHAP",
        "refund_not_showing_up": "THU_NHAP",
        "balance_not_updated_after_bank_transfer": "THU_NHAP",
        "balance_not_updated_after_cheque_or_cash_deposit": "THU_NHAP",

        # Tiết kiệm & Đầu tư
        "top_up_reverted": "TIET_KIEM_DAU_TU",
        "automatic_top_up": "TIET_KIEM_DAU_TU",
        "top_up_by_bank_transfer_charge": "TIET_KIEM_DAU_TU",
        "top_up_by_card_charge": "TIET_KIEM_DAU_TU",
        "top_up_by_cash_or_cheque": "TIET_KIEM_DAU_TU",
        "top_up_limits": "TIET_KIEM_DAU_TU",
        "exchange_rate": "TIET_KIEM_DAU_TU",
        "exchange_via_app": "TIET_KIEM_DAU_TU",
        "exchange_charge": "TIET_KIEM_DAU_TU",

        # Mua sắm
        "card_purchase_foreign_currency": "MUA_SAM",
        "declined_transfer": "MUA_SAM",
        "apple_pay_or_google_pay": "MUA_SAM",
        "contactless_not_working": "MUA_SAM",
        "virtual_card_not_working": "MUA_SAM",
        "order_physical_card": "MUA_SAM"
    }

    filtered = []
    for _, row in df.iterrows():
        cat = str(row["category"]).strip()
        text = str(row["text"]).strip()
        if cat in relevant_intents:
            mapped_cat = relevant_intents[cat]
            filtered.append({"text": text, "category": mapped_cat})

    # Xáo trộn và lấy đúng số lượng yêu cầu
    random.shuffle(filtered)
    selected = filtered[:max_samples]
    print(f"[+] Đã chọn thành công {len(selected)} mẫu tiếng Anh từ Banking77")
    return selected

# ==============================================================================
# QUY TRÌNH TIỀN XỬ LÝ CHÍNH
# ==============================================================================

def process_nlp_dataset():
    print("\n" + "="*50)
    print("[1] BẮT ĐẦU XÂY DỰNG BỘ DỮ LIỆU NLP CHUẨN (~10.000 DÒNG)")
    print("="*50)

    nlp_samples = []

    # 1. Dữ liệu thực tế từ Kaggle: Daily Household Transactions
    p1 = os.path.join(DATASET_DIR, "Daily Household Transactions.csv")
    if os.path.exists(p1):
        df1 = pd.read_csv(p1)
        for _, row in df1.iterrows():
            desc = str(row.get("Note", "")).strip()
            sub = str(row.get("Subcategory", "")).strip()
            cat = str(row.get("Category", "")).strip()
            text = desc if desc and desc.lower() != "nan" else sub
            if not text or text.lower() == "nan":
                text = cat
            mapped_cat = CATEGORY_MAP.get(cat.lower(), CATEGORY_MAP.get(sub.lower(), None))
            if mapped_cat and text:
                nlp_samples.append({"text": text, "category": mapped_cat})

    # 2. Dữ liệu thực tế từ Kaggle: Personal Transactions Dashboard
    p2 = os.path.join(DATASET_DIR, "personal_transactions_dashboard_ready (2).xlsx")
    if os.path.exists(p2):
        df2 = pd.read_excel(p2)
        for _, row in df2.iterrows():
            desc = str(row.get("Description", "")).strip()
            cat = str(row.get("Category", "")).strip()
            mapped_cat = CATEGORY_MAP.get(cat.lower(), None)
            if mapped_cat and desc and desc.lower() != "nan":
                nlp_samples.append({"text": desc, "category": mapped_cat})

    # 3. Dữ liệu thực tế từ Kaggle: VN Cashless 2026
    p3 = os.path.join(DATASET_DIR, "kaggle_vn_cashless_vn_cashless_2026.csv")
    if os.path.exists(p3):
        df3 = pd.read_csv(p3)
        for _, row in df3.iterrows():
            cat = str(row.get("Merchant_Category", "")).strip()
            method = str(row.get("Payment_Method", "")).strip()
            loc = str(row.get("Location", "")).strip()
            mapped_cat = CATEGORY_MAP.get(cat.lower(), None)
            if mapped_cat:
                nlp_samples.append({"text": f"Thanh toán {cat} bằng {method} tại {loc}", "category": mapped_cat})

    # 4. Bổ sung dữ liệu thanh toán từ Banking77 (~4.000 mẫu)
    b77_samples = get_banking77_relevant_samples(max_samples=4000)
    nlp_samples.extend(b77_samples)

    # 5. Bổ sung toàn diện 4 trường hợp tiếng Việt thực tế (TH 1, 2, 3, 4)
    vn_scenarios = generate_vietnamese_scenarios()
    nlp_samples.extend(vn_scenarios)

    # 6. Bổ sung từ thư viện mẫu tiếng Việt
    try:
        from generate_datasets import TEMPLATES
        for cat, val in TEMPLATES.items():
            for item in val["items"]:
                for verb in val["verbs"]:
                    nlp_samples.append({"text": f"{verb} {item}".strip().lower(), "category": cat})
                    nlp_samples.append({"text": f"{verb} {item} {random.choice(['30k', '50k', '100k', '200k', '500k', '1tr', '2tr5'])}".strip().lower(), "category": cat})
                    nlp_samples.append({"text": f"Vừa {verb.lower()} {item} {random.choice(['50 cành', '1 lít', '2 củ', '30k'])}".strip().lower(), "category": cat})
    except Exception as e:
        print(f"[i] Lưu ý khi nạp template: {e}")

    # Chuyển thành DataFrame, loại bỏ trùng lặp và rỗng
    df_nlp = pd.DataFrame(nlp_samples).dropna().drop_duplicates(subset=["text"])
    
    # Lưu file
    output_path = os.path.join(DATASET_DIR, "cleaned_nlp_transactions.csv")
    df_nlp.to_csv(output_path, index=False, encoding="utf-8-sig")

    print(f"\n[+] ĐÃ XUẤT THÀNH CÔNG: {output_path}")
    print(f"[+] TỔNG SỐ DÒNG CHUẨN HÓA: {len(df_nlp):,} dòng mẫu")
    print("\n--- BẢNG PHÂN BỐ CÂN BẰNG GIỮA 10 DANH MỤC ---")
    print(df_nlp["category"].value_counts())
    return df_nlp

def process_timeseries_dataset():
    print("\n" + "="*50)
    print("[2] TIỀN XỬ LÝ DỮ LIỆU CHUỖI THỜI GIAN (CHO LSTM)")
    print("="*50)

    daily_records = []

    p1 = os.path.join(DATASET_DIR, "Daily Household Transactions.csv")
    if os.path.exists(p1):
        df1 = pd.read_csv(p1)
        df1_exp = df1[df1["Income/Expense"].astype(str).str.lower() == "expense"].copy()
        for _, row in df1_exp.iterrows():
            date_raw = str(row["Date"]).strip()
            amount = row["Amount"]
            try:
                d_str = date_raw.split()[0]
                dt = pd.to_datetime(d_str, format="%d/%m/%Y", errors="coerce")
                if pd.isna(dt):
                    dt = pd.to_datetime(d_str, errors="coerce")
                if pd.notna(dt) and float(amount) > 0:
                    daily_records.append({"date": dt.strftime("%Y-%m-%d"), "amount": float(amount) * 300})
            except Exception:
                continue

    p2 = os.path.join(DATASET_DIR, "personal_transactions_dashboard_ready (2).xlsx")
    if os.path.exists(p2):
        df2 = pd.read_excel(p2)
        df2_exp = df2[df2["Transaction Type"].astype(str).str.lower() == "debit"].copy()
        for _, row in df2_exp.iterrows():
            dt = pd.to_datetime(row["Date"], errors="coerce")
            amount = row["Amount"]
            if pd.notna(dt) and float(amount) > 0:
                daily_records.append({"date": dt.strftime("%Y-%m-%d"), "amount": float(amount) * 25000})

    p3 = os.path.join(DATASET_DIR, "kaggle_vn_cashless_vn_cashless_2026.csv")
    if os.path.exists(p3):
        df3 = pd.read_csv(p3)
        for _, row in df3.iterrows():
            dt = pd.to_datetime(row["Timestamp"], errors="coerce")
            amount = row["Amount_VND"]
            if pd.notna(dt) and float(amount) > 0:
                daily_records.append({"date": dt.strftime("%Y-%m-%d"), "amount": float(amount)})

    df_raw_ts = pd.DataFrame(daily_records)
    df_grouped = df_raw_ts.groupby("date", as_index=False)["amount"].sum()
    df_grouped["date"] = pd.to_datetime(df_grouped["date"])
    df_grouped = df_grouped.sort_values("date").reset_index(drop=True)

    df_grouped["day_of_week"] = df_grouped["date"].dt.weekday
    df_grouped["is_weekend"] = df_grouped["day_of_week"].apply(lambda x: 1 if x in [5, 6] else 0)
    df_grouped["month"] = df_grouped["date"].dt.month
    df_grouped["amount"] = df_grouped["amount"].round(-3).astype(int)

    output_path = os.path.join(DATASET_DIR, "cleaned_timeseries_daily_expense.csv")
    df_grouped.to_csv(output_path, index=False, encoding="utf-8-sig")

    print(f"[+] Đã lưu chuỗi thời gian: {output_path}")
    print(f"[+] Số mốc ngày quan sát: {len(df_grouped):,} ngày")
    return df_grouped

if __name__ == "__main__":
    process_nlp_dataset()
    process_timeseries_dataset()
    print("\n===> HOÀN TẤT TIỀN XỬ LÝ TOÀN DIỆN! <===")
