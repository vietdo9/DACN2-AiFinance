# -*- coding: utf-8 -*-
"""
Script tạo tài liệu Word tổng hợp các lỗi đã gặp và giải pháp khắc phục trong dự án FinWise.
"""

import os
import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

def set_cell_background(cell, fill_hex):
    """Đặt màu nền cho ô trong bảng"""
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), fill_hex)
    tcPr.append(shd)

def set_cell_margins(cell, top=100, bottom=100, left=150, right=150):
    """Đặt padding cho ô trong bảng"""
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = OxmlElement('w:tcMar')
    for m, val in [('top', top), ('bottom', bottom), ('left', left), ('right', right)]:
        node = OxmlElement(f'w:{m}')
        node.set(qn('w:w'), str(val))
        node.set(qn('w:type'), 'dxa')
        tcMar.append(node)
    tcPr.append(tcMar)

def add_callout(doc, title, text, bg_color="EEF2FF", border_color="4F46E5"):
    """Tạo hộp ghi chú đẹp mắt"""
    tbl = doc.add_table(rows=1, cols=1)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    cell = tbl.cell(0, 0)
    set_cell_background(cell, bg_color)
    set_cell_margins(cell, top=140, bottom=140, left=200, right=200)
    
    # Border trái
    tcPr = cell._tc.get_or_add_tcPr()
    tcBorders = OxmlElement('w:tcBorders')
    
    left = OxmlElement('w:left')
    left.set(qn('w:val'), 'single')
    left.set(qn('w:sz'), '24') # 3pt
    left.set(qn('w:space'), '0')
    left.set(qn('w:color'), border_color)
    tcBorders.append(left)
    
    for b in ['top', 'bottom', 'right']:
        node = OxmlElement(f'w:{b}')
        node.set(qn('w:val'), 'none')
        tcBorders.append(node)
    tcPr.append(tcBorders)
    
    p = cell.paragraphs[0]
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after = Pt(2)
    run_t = p.add_run(f"📌 {title}: ")
    run_t.bold = True
    run_t.font.name = 'Calibri'
    run_t.font.size = Pt(10.5)
    run_t.font.color.rgb = RGBColor(0x1E, 0x29, 0x3B)
    
    run_c = p.add_run(text)
    run_c.font.name = 'Calibri'
    run_c.font.size = Pt(10)
    run_c.font.color.rgb = RGBColor(0x33, 0x41, 0x55)
    
    doc.add_paragraph().paragraph_format.space_after = Pt(4)

def main():
    doc = docx.Document()
    
    # Cấu hình lề trang (1 inch = 72 pt)
    sections = doc.sections
    for s in sections:
        s.top_margin = Inches(0.8)
        s.bottom_margin = Inches(0.8)
        s.left_margin = Inches(0.85)
        s.right_margin = Inches(0.85)
        
    # --- HEADER / TIÊU ĐỀ CHÍNH ---
    p_sub = doc.add_paragraph()
    p_sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_sub.paragraph_format.space_after = Pt(2)
    r_sub = p_sub.add_run("ĐỒ ÁN CHUYÊN NGÀNH 2 - HỆ THỐNG QUẢN LÝ TÀI CHÍNH CÁ NHÂN FINWISE")
    r_sub.font.name = 'Calibri'
    r_sub.font.size = Pt(11)
    r_sub.bold = True
    r_sub.font.color.rgb = RGBColor(0x4F, 0x46, 0xE5) # Indigo
    
    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_title.paragraph_format.space_after = Pt(8)
    r_title = p_title.add_run("BÁO CÁO TỔNG HỢP CÁC LỖI ĐÃ GẶP\nVÀ GIẢI PHÁP KHẮC PHỤC TRIỆT ĐỂ")
    r_title.font.name = 'Calibri'
    r_title.font.size = Pt(20)
    r_title.bold = True
    r_title.font.color.rgb = RGBColor(0x0F, 0x17, 0x2A) # Dark slate
    
    p_meta = doc.add_paragraph()
    p_meta.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_meta.paragraph_format.space_after = Pt(18)
    r_meta = p_meta.add_run("Phiên bản: 1.0.6 | Nền tảng: Flutter Mobile + Node.js Backend + Supabase PostgreSQL + PhoBERT & LSTM AI")
    r_meta.font.name = 'Calibri'
    r_meta.font.size = Pt(9.5)
    r_meta.font.italic = True
    r_meta.font.color.rgb = RGBColor(0x64, 0x74, 0x8B)
    
    # Đường kẻ ngang phân cách
    p_line = doc.add_paragraph()
    p_line.paragraph_format.space_after = Pt(14)
    r_line = p_line.add_run("―" * 58)
    r_line.font.color.rgb = RGBColor(0xCB, 0xD5, 0xE1)
    p_line.alignment = WD_ALIGN_PARAGRAPH.CENTER

    # --- MỤC LỤC TÓM TẮT ---
    h_toc = doc.add_heading("I. TỔNG QUAN CÁC VẤN ĐỀ ĐÃ XỬ LÝ", level=1)
    h_toc.paragraph_format.space_before = Pt(8)
    h_toc.paragraph_format.space_after = Pt(8)
    for r in h_toc.runs:
        r.font.name = 'Calibri'
        r.font.color.rgb = RGBColor(0x1E, 0x29, 0x3B)
        
    p_intro = doc.add_paragraph(
        "Trong quá trình xây dựng, thử nghiệm thực tế và đồng bộ dữ liệu giữa thiết bị di động (Flutter), "
        "máy chủ trung gian (Node.js/Express) và cơ sở dữ liệu đám mây (Supabase PostgreSQL), hệ thống đã phát sinh "
        "các lỗi kỹ thuật từ mức độ kết nối hạ tầng đến xung đột dữ liệu và logic AI. Báo cáo này tài liệu hóa chi tiết "
        "nguyên nhân gốc rễ (Root Cause) và giải pháp kỹ thuật đã áp dụng nhằm đảm bảo hệ thống vận hành ổn định."
    )
    p_intro.paragraph_format.space_after = Pt(10)
    p_intro.paragraph_format.line_spacing = 1.15
    for r in p_intro.runs:
        r.font.name = 'Calibri'
        r.font.size = Pt(10.5)

    # Bảng tóm tắt nhanh
    table = doc.add_table(rows=7, cols=4)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    
    headers = ["STT", "Nhóm lỗi / Hiện tượng", "Nguyên nhân chính", "Mức độ"]
    col_widths = [Inches(0.5), Inches(2.3), Inches(3.0), Inches(0.9)]
    
    hdr_cells = table.rows[0].cells
    for i, title in enumerate(headers):
        hdr_cells[i].text = title
        set_cell_background(hdr_cells[i], "1E293B")
        set_cell_margins(hdr_cells[i], top=100, bottom=100, left=100, right=100)
        p = hdr_cells[i].paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        for run in p.runs:
            run.font.bold = True
            run.font.name = 'Calibri'
            run.font.size = Pt(9.5)
            run.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)

    summary_data = [
        ("1", "Chỉnh sửa Chi -> Thu không lưu được", "Lỗi Postgres 42703 (cột updated_at không tồn tại trong bảng transactions)", "Nghiêm trọng"),
        ("2", "Tiền cộng 250k bị nhận nhầm là Khoản Chi", "Thiếu phân cấp 2 tầng; PhoBERT ưu tiên nhãn chi tiêu khi chưa lọc hướng dòng tiền", "Cao"),
        ("3", "Thông báo ngân hàng không tự đồng bộ", "Chưa cấp quyền NotificationListenerService; thiếu package ShopeePay/VNPAY/MoMo", "Cao"),
        ("4", "Google Play Protect chặn cài APK", "Ứng dụng tự ký (Self-signed) có quyền Notification Listener nhạy cảm", "Trung bình"),
        ("5", "Lỗi mất kết nối / Timeout máy chủ", "Dịch vụ Render Free bị ngủ đông (Cold Start) sau 15 phút không dùng", "Trung bình"),
        ("6", "Độc lập dữ liệu tài khoản (Multi-User)", "Một số truy vấn trước đây chưa cách ly triệt để theo user_id định danh", "Nghiêm trọng"),
    ]

    for row_idx, data in enumerate(summary_data, start=1):
        row_cells = table.rows[row_idx].cells
        for col_idx, text in enumerate(data):
            row_cells[col_idx].text = text
            set_cell_margins(row_cells[col_idx], top=80, bottom=80, left=100, right=100)
            if row_idx % 2 == 0:
                set_cell_background(row_cells[col_idx], "F8FAFC")
            p = row_cells[col_idx].paragraphs[0]
            if col_idx in [0, 3]:
                p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            for run in p.runs:
                run.font.name = 'Calibri'
                run.font.size = Pt(9.5)
                if col_idx == 3:
                    if text == "Nghiêm trọng":
                        run.font.bold = True
                        run.font.color.rgb = RGBColor(0xDC, 0x26, 0x26)
                    elif text == "Cao":
                        run.font.bold = True
                        run.font.color.rgb = RGBColor(0xD9, 0x77, 0x06)
                    else:
                        run.font.color.rgb = RGBColor(0x25, 0x63, 0xEB)

    # Đặt độ rộng cột
    for row in table.rows:
        for idx, width in enumerate(col_widths):
            row.cells[idx].width = width

    doc.add_paragraph().paragraph_format.space_after = Pt(12)

    # --- CHI TIẾT TỪNG LỖI ---
    h_detail = doc.add_heading("II. NỘI DUNG CHI TIẾT CÁC LỖI & PHƯƠNG ÁN KHẮC PHỤC", level=1)
    h_detail.paragraph_format.space_before = Pt(14)
    h_detail.paragraph_format.space_after = Pt(10)

    errors = [
        {
            "id": "1",
            "title": "Lỗi Chỉnh Sửa Giao Dịch Không Lưu (Chi Tiêu -> Thu Nhập Không Đổi)",
            "symptom": (
                "Người dùng mở danh sách giao dịch, chọn một khoản chi tiêu cũ (ví dụ: Ăn uống 250.000đ), "
                "mở hộp thoại chỉnh sửa và đổi loại giao dịch sang 'Thu Nhập'. Sau khi bấm 'Lưu Thay Đổi', "
                "ứng dụng báo thành công nhưng ngay khi tải lại màn hình, giao dịch vẫn hiển thị là Khoản Chi."
            ),
            "root_cause": (
                "1. Trong Backend (routes/transaction.routes.js), câu lệnh supabase.from('transactions').update() "
                "có đính kèm trường: updated_at: new Date().toISOString().\n"
                "2. Kiểm tra schema cơ sở dữ liệu Supabase (supabase_schema.sql) cho thấy bảng 'transactions' CHỈ CÓ "
                "các cột: id, user_id, wallet_id, category_code, amount, type, note, transaction_date, ai_predicted, "
                "ai_confidence, created_at. Hoàn toàn KHÔNG CÓ cột updated_at.\n"
                "3. PostgreSQL bắn lỗi 42703 (column 'updated_at' of relation 'transactions' does not exist), "
                "khiến lệnh ghi vào Supabase bị từ chối. Khối catch nuốt lỗi và trả về dữ liệu LocalStore tạm thời. "
                "Khi điện thoại gọi GET /api/transactions tải lại từ Supabase thì vẫn là dữ liệu cũ chưa sửa."
            ),
            "solution": (
                "1. Backend: Xóa bỏ trường 'updated_at' trong payload gửi lên Supabase update.\n"
                "2. Ép kiểu danh mục an toàn: Khi đổi sang type='income', backend tự kiểm tra nếu category_code là danh mục "
                "chi tiêu (như AN_UONG), lập tức tự chuẩn hóa về 'THU_NHAP'.\n"
                "3. Foreign Key Fallback: Bổ sung cơ chế bắt lỗi 23503 (vi phạm khóa ngoại danh mục) để tự retry về mã 'THU_NHAP'.\n"
                "4. Mobile App: Cập nhật transactions_screen.dart tự đổi lưới danh mục sang Thu Nhập ngay khi bấm tab Thu Nhập."
            ),
            "files": "backend/routes/transaction.routes.js, finwise_mobile/lib/screens/transactions_screen.dart",
            "tested": "Đã kiểm thử: Chỉnh sửa giao dịch từ Chi sang Thu, lưu thành công, số dư ví tự động bù trừ chuẩn xác (+500k delta), reload không bị mất."
        },
        {
            "id": "2",
            "title": "Lỗi Tiền Được Cộng (250k) Bị Nhận Nhầm Là Khoản Chi",
            "symptom": (
                "Người dùng nhận được thông báo biến động số dư hoặc nhập tin nhắn ngân hàng có nội dung "
                "nhận tiền (ví dụ: 'TK 1234 +250k tien me cho' hoặc 'duoc cong 250.000d'), nhưng hệ thống lại "
                "tự động phân loại là 'Khoản Chi' và trừ tiền vào tổng chi tiêu tháng."
            ),
            "root_cause": (
                "1. Mô hình PhoBERT được huấn luyện nhận diện ngữ nghĩa câu (ví dụ: thấy từ 'tien me cho' hoặc tên món ăn). "
                "Nếu đưa trực tiếp toàn bộ ghi chú vào PhoBERT mà không lọc trước tính chất Thu/Chi, AI sẽ phân loại nhầm sang "
                "1 trong các nhãn chi tiêu.\n"
                "2. Thiếu kiến trúc phân cấp 2 tầng: Cần có Tầng 1 quyết định Hướng dòng tiền (Thu hay Chi) trước, sau đó "
                "Tầng 2 mới phân loại danh mục con."
            ),
            "solution": (
                "1. Triển khai kiến trúc 2 tầng (2-Tier Architecture):\n"
                "   - Tầng 1 (Cố định & Bắt buộc): Kiểm tra dấu hiệu cộng tiền thông qua Regex (+, cong, nhan tien, nap tien, vao tk). "
                "Nếu thỏa mãn, khóa cứng type = 'income' và category_code = 'THU_NHAP'. Tuyệt đối không cho PhoBERT ghi đè.\n"
                "   - Tầng 2: PhoBERT chỉ được kích hoạt phân loại danh mục khi type = 'expense' (Khoản Chi).\n"
                "2. Bổ sung hỗ trợ đơn vị tiền viết tắt: Nhận diện và quy đổi linh hoạt các cú pháp '250k', '250K', '250.000d' sang số thực 250000."
            ),
            "files": "finwise_mobile/lib/services/notification_sync_service.dart, finwise_mobile/lib/screens/add_transaction_screen.dart",
            "tested": "Đã kiểm thử: Tin nhắn '+250k chuyen khoan' được nhận diện chuẩn xác 100% là Thu Nhập, lưu vào cơ sở dữ liệu với màu xanh lá và cộng số dư ví."
        },
        {
            "id": "3",
            "title": "Lỗi Không Bắt Được Thông Báo Ngân Hàng & Ví Điện Tử Trên Android",
            "symptom": (
                "Người dùng thực hiện chuyển tiền qua ShopeePay, MoMo, ZaloPay, VNPAY nhưng ứng dụng không "
                "tự động ghi nhận giao dịch vào sổ thu chi."
            ),
            "root_cause": (
                "1. Trên hệ điều hành Android, quyền đọc thông báo là quyền riêng tư đặc biệt (Special App Access), "
                "phải cấu hình NotificationListenerService trong AndroidManifest.xml và người dùng phải cấp quyền thủ công trong Cài đặt hệ sinh thái.\n"
                "2. Danh sách gói ứng dụng (Package Names) theo dõi ban đầu bị thiếu các định danh của ví ShopeePay "
                "(com.airpay.consumer, com.shopee.vn), VNPAY Smart Account (vnpay.smartacccount), Viettel Money, Timo, Cake.\n"
                "3. Trình tối ưu mã R8/ProGuard khi build Release đã làm obfuscate (rút gọn) mã service native."
            ),
            "solution": (
                "1. Cập nhật AndroidManifest.xml: Khai báo đầy đủ dịch vụ NotificationListenerService với permission BIND_NOTIFICATION_LISTENER_SERVICE.\n"
                "2. Mở rộng danh sách _knownBankingPackages lên hơn 22 ứng dụng ngân hàng và ví điện tử phổ biến tại Việt Nam.\n"
                "3. Viết hàm tự động chuyển hướng người dùng đến trang Cài đặt cấp quyền đọc thông báo khi mở app lần đầu.\n"
                "4. Thêm quy tắc bảo vệ trong android/app/proguard-rules.pro để ProGuard không xóa service khi build Release APK."
            ),
            "files": "finwise_mobile/android/app/src/main/AndroidManifest.xml, finwise_mobile/lib/services/notification_sync_service.dart, finwise_mobile/android/app/proguard-rules.pro",
            "tested": "Đã kiểm thử: Ngay khi điện thoại nhận notification từ ngân hàng/ví, app lập tức bóc tách số tiền, tạo giao dịch ngầm và cập nhật số dư ví."
        },
        {
            "id": "4",
            "title": "Lỗi Google Play Protect Chặn Cài Đặt File APK",
            "symptom": (
                "Khi gửi file APK cho người dùng cài đặt thử nghiệm trên điện thoại Android, hệ thống Google Play Protect "
                "hiển thị hộp thoại màu đỏ cảnh báo 'Ứng dụng bị chặn bởi Play Protect / Ứng dụng không an toàn'."
            ),
            "root_cause": (
                "1. Bản build sử dụng khóa ký tạm thời (Debug Keystore) hoặc chứng chỉ tự ký chưa được đăng ký trên Google Play Console.\n"
                "2. Ứng dụng có xin quyền đọc thông báo (Notification Listener) – đây là quyền có mức độ nhạy cảm cao trên Android, "
                "nên thuật toán Play Protect mặc định sẽ cảnh báo thận trọng nếu ứng dụng chưa được quét qua cửa hàng Google Play."
            ),
            "solution": (
                "1. Tối ưu cấu hình build Release: Sử dụng lệnh 'flutter build apk --release' giúp loại bỏ các cờ debug và tối ưu hóa nhị phân.\n"
                "2. Xây dựng tài liệu hướng dẫn người dùng: Hướng dẫn bấm 'Xem thêm chi tiết (More details)' -> Chọn 'Vẫn cài đặt (Install anyway)'.\n"
                "3. Trong phiên bản thương mại/nộp đồ án: Tạo Release Keystore chính thức (JKS) và cấu hình signingConfigs trong app/build.gradle."
            ),
            "files": "finwise_mobile/android/app/build.gradle, finwise_mobile/build/app/outputs/flutter-apk/app-release.apk",
            "tested": "Đã xác nhận: File APK Release mới nhất (v1.0.6 - 53.6 MB) cài đặt êm thuận và hoạt động ổn định trên các dòng máy Android 11 đến Android 14."
        },
        {
            "id": "5",
            "title": "Lỗi Mất Kết Nối Server / Timeout Do Cơ Chế Ngủ Đông Của Cloud",
            "symptom": (
                "Khi mở ứng dụng vào buổi sáng hoặc sau nhiều giờ không sử dụng, lần đầu tiên đăng nhập hoặc tải danh sách "
                "giao dịch thường bị xoay tròn rất lâu rồi báo 'Mất kết nối server' hoặc 'Connection timeout'."
            ),
            "root_cause": (
                "1. Máy chủ Backend được triển khai trên Render Cloud gói Free (https://dacn2-aifinance.onrender.com). "
                "Theo chính sách của Render, nếu không có request trong vòng 15 phút, server sẽ tự động 'ngủ đông' (Spin down container) để tiết kiệm tài nguyên.\n"
                "2. Thời gian để Render khởi động lại container (Cold Start) mất từ 30 đến 50 giây. Trong khi đó, timeout mặc định của thư viện HTTP trên mobile chỉ là 10-15 giây, dẫn tới việc ứng dụng ngắt kết nối trước khi server kịp sẵn sàng."
            ),
            "solution": (
                "1. Tăng timeout phía Mobile App: Cấu hình ApiService với connectionTimeout và receiveTimeout lên 45-60 giây.\n"
                "2. Cơ chế Retry thông minh: Nếu gặp lỗi mạng ở lần gọi đầu, app tự động thử lại lần 2 sau 3 giây.\n"
                "3. Hiển thị chỉ báo thân thiện: Khi server đang thức giấc, hiển thị thông điệp 'Đang đánh thức máy chủ đám mây, vui lòng đợi trong giây lát...'.\n"
                "4. Lưu trữ đệm LocalStore: Khi offline hoặc mạng chập chờn, dữ liệu vẫn được lưu vào bộ nhớ cục bộ và tự đồng bộ khi có mạng."
            ),
            "files": "finwise_mobile/lib/services/api_service.dart, backend/server.js",
            "tested": "Đã kiểm thử: Khi server ngủ đông, ứng dụng kiên trì chờ và tự kết nối lại thành công sau khi Render thức dậy mà không văng lỗi ra màn hình."
        },
        {
            "id": "6",
            "title": "Lỗi Bảo Mật Cách Ly Dữ Liệu Đa Người Dùng (Multi-User Isolation)",
            "symptom": (
                "Trước đây khi người dùng A đăng nhập và tạo giao dịch, sau đó người dùng B đăng nhập trên thiết bị khác "
                "thì có nguy cơ nhìn thấy số liệu tổng quan hoặc số dư ví của người dùng A."
            ),
            "root_cause": (
                "1. Một số endpoint trong backend ban đầu sử dụng ví mặc định có ID cứng (hardcoded) hoặc chưa truyền đúng user_id vào câu truy vấn Supabase.\n"
                "2. Bộ nhớ LocalStore dùng chung một mảng transactions mà không nhóm theo user_id định danh."
            ),
            "solution": (
                "1. Chuẩn hóa Middleware Xác thực: 100% các route nghiệp vụ bắt buộc phải đi qua verifyToken để giải mã JWT lấy user.id.\n"
                "2. Lọc triệt để tại tầng dữ liệu: Tất cả các truy vấn Supabase đều bắt buộc có điều kiện: .eq('user_id', req.user.id).\n"
                "3. Viết kịch bản kiểm thử độc lập tự động: File backend/test_multi_user.js tạo đồng thời User A và User B, xác nhận 100% số liệu ví, giao dịch, biểu đồ thống kê và dự báo AI của 2 tài khoản hoàn toàn tách biệt."
            ),
            "files": "backend/middlewares/auth.js, backend/routes/transaction.routes.js, backend/routes/analytics.routes.js, backend/test_multi_user.js",
            "tested": "Đã kiểm thử tự động: Chạy test_multi_user.js thành công rực rỡ, không có hiện tượng rò rỉ hay lẫn lộn dữ liệu giữa các tài khoản."
        },
        {
            "id": "7",
            "title": "Lỗi Không Lưu Thay Đổi Phân Loại Chi Tiêu Lên Supabase (Ví dụ giao dịch 10.000đ)",
            "symptom": (
                "Người dùng mở modal chỉnh sửa một giao dịch chi tiêu có sẵn (ví dụ khoản chi 10.000đ từ MB Bank), "
                "thay đổi danh mục phân loại và bấm 'Lưu Thay Đổi', ứng dụng thông báo thành công nhưng trên Supabase và giao diện "
                "danh mục vẫn giữ nguyên giá trị cũ, không hề thay đổi."
            ),
            "root_cause": (
                "1. Backend Route Nuốt Lỗi (Silent Failure): Trong backend/routes/transaction.routes.js, khi Supabase gặp lỗi cập nhật "
                "(do câu lệnh gửi trường updated_at không tồn tại hoặc lỗi Foreign Key), khối catch bên ngoài đã nuốt lỗi và trả về "
                "HTTP 200 { success: true, data: null }. Ứng dụng di động nhận status 200 nên hiện thông báo xanh thành công giả.\n"
                "2. Timeout quá ngắn trên Mobile: finwise_mobile/lib/services/api_service.dart giới hạn timeout cập nhật chỉ 5 giây. "
                "Khi mạng di động chậm hoặc kết nối tới Render bị trễ, request bị hủy ngầm (TimeoutException) khiến server không nhận được lệnh.\n"
                "3. Kiểm tra danh mục ở UI bị giới hạn: Giao diện kiểm tra phân loại dựa trên mảng _categories có sẵn, nếu mảng rỗng thì tự động fallback về mã mặc định 'AN_UONG'."
            ),
            "solution": (
                "1. Sửa Backend PUT /:id: Bắt chặt lỗi từ Supabase, nếu cập nhật thất bại thì trả về HTTP 500 kèm chi tiết lỗi chính xác, "
                "tuyệt đối không trả về status 200 khi dữ liệu chưa được ghi.\n"
                "2. Tăng HTTP Timeout lên 15 giây: Tăng thời gian chờ cho toàn bộ các API cốt lõi trong api_service.dart lên 15s để thích ứng mạng 4G/Wifi yếu.\n"
                "3. Độc lập hóa danh mục kiểm tra: Dùng bảng mã danh mục chuẩn knownExpenseCodes và knownIncomeCodes trực tiếp, đảm bảo chọn danh mục nào thì gửi chính xác danh mục đó lên server.\n"
                "4. Đã chạy test script xác nhận trên Supabase: Cập nhật thành công giao dịch 10k ID 4a12263d... sang phân loại mới trên database."
            ),
            "files": "backend/routes/transaction.routes.js, finwise_mobile/lib/services/api_service.dart, finwise_mobile/lib/screens/transactions_screen.dart",
            "tested": "Đã kiểm thử: Cập nhật thành công trực tiếp lên bảng transactions của Supabase, backend trả về HTTP 500 nếu có lỗi thay vì nuốt lỗi ngầm."
        },
        {
            "id": "8",
            "title": "Lỗi Dữ Liệu Đồng Bộ Chậm / Không Tự Động Cập Nhật Giữa Các Màn Hình",
            "symptom": (
                "Khi có biến động số dư hoặc giao dịch mới từ thông báo ngân hàng / ví điện tử được bắt tự động, "
                "hoặc khi thêm/sửa/xóa giao dịch ở màn hình này thì màn hình khác (Dashboard, Lịch sử giao dịch) "
                "không cập nhật kịp thời, người dùng phải tắt app mở lại mới thấy dữ liệu mới."
            ),
            "root_cause": (
                "1. Thiếu cơ chế phát sóng sự kiện (Event Broadcast): Khi NotificationSyncService lưu thành công một giao dịch ngầm, "
                "hoặc khi TransactionsScreen sửa/xóa giao dịch, không có tín hiệu nào kích hoạt DashboardScreen tải lại dữ liệu.\n"
                "2. Thiếu Pull-To-Refresh: Màn hình Lịch sử giao dịch (TransactionsScreen) chưa có tính năng vuốt xuống để làm mới (RefreshIndicator) "
                "và thiếu nút đồng bộ nhanh trên thanh AppBar.\n"
                "3. Không tự động làm mới khi quay lại App: Người dùng chuyển qua app ngân hàng để chuyển khoản rồi quay lại FinWise "
                "thì app vẫn giữ nguyên trạng thái cũ (không lắng nghe sự kiện resumed của vòng đời ứng dụng)."
            ),
            "solution": (
                "1. Kiến trúc ValueNotifier Toàn cục: Bổ sung ValueNotifier<int> dataRefreshTrigger trong NotificationSyncService. Bất kỳ khi nào "
                "có giao dịch được bắt tự động, thêm mới, sửa hoặc xóa, bộ đếm này tăng lên và kích hoạt đồng bộ tức thì trên toàn bộ các màn hình.\n"
                "2. Tích hợp WidgetsBindingObserver: Cả DashboardScreen và TransactionsScreen đều tự động đồng bộ ngầm ngay khoảnh khắc người dùng "
                "mở lại ứng dụng (AppLifecycleState.resumed).\n"
                "3. Bổ sung Pull-To-Refresh & Nút Sync: Bổ sung RefreshIndicator cho cả danh sách rỗng và danh sách có dữ liệu, thêm nút đồng bộ tức thì "
                "trên thanh AppBar của cả màn hình Tổng quan và Lịch sử giao dịch."
            ),
            "files": "finwise_mobile/lib/services/notification_sync_service.dart, finwise_mobile/lib/screens/dashboard_screen.dart, finwise_mobile/lib/screens/transactions_screen.dart",
            "tested": "Đã kiểm thử: Đóng mở app, vuốt kéo làm mới và kích hoạt sự kiện đồng bộ chéo màn hình mượt mà, không giật lag."
        },
        {
            "id": "9",
            "title": "Lỗi 'Tổng Số Dư Hiện Tại' Luôn Bị Kẹt Ở 0đ Dù Đã Có Thu Nhập và Chi Tiêu",
            "symptom": (
                "Trên thẻ Gradient màu tím ở màn hình Trang chủ (Dashboard), dù người dùng đã có phát sinh giao dịch rõ ràng "
                "(ví dụ: Thu tháng này: 250.000đ, Chi tháng này: 53.000đ), nhưng ô lớn 'Tổng số dư hiện tại' vẫn luôn hiển thị '0 đ'."
            ),
            "root_cause": (
                "1. Logic Tính Số Dư Lấy Nhầm Bảng Tĩnh: Tại backend/routes/analytics.routes.js, biến total_balance chỉ lấy từ "
                "bảng wallets (wallets.reduce(w.balance)). Trong khi đó, ví mặc định được tạo lúc đăng ký với số dư khởi điểm 0đ, "
                "và ứng dụng di động không có giao diện chọn ví khi thêm giao dịch (giao dịch lưu wallet_id = null).\n"
                "2. Thiếu Cơ Chế Tính Số Dư Ròng (Net Balance): Backend chỉ truy vấn các giao dịch trong tháng hiện tại (gte firstDayOfMonth) "
                "để tính thu/chi tháng, mà không hề truy vấn toàn bộ lịch sử giao dịch để cộng dồn dòng tiền thực tế (All-time Income - All-time Expense)."
            ),
            "solution": (
                "1. Sửa Logic Tính Toán Tổng Số Dư: Trong analytics.routes.js, backend truy vấn toàn bộ lịch sử giao dịch tích lũy của user_id "
                "để tính: totalBalance = (Tổng toàn bộ Thu nhập) - (Tổng toàn bộ Chi tiêu) = 250.000 - 53.000 = 197.000đ.\n"
                "2. Tự Động Đồng Bộ Vào Bảng Wallets: Tự động cập nhật số dư này vào dòng ví mặc định trên Supabase và localStore để cơ sở dữ liệu luôn nhất quán.\n"
                "3. Bổ Sung Cơ Chế Tự Bảo Vệ Trên Mobile: Trong dashboard_screen.dart, nếu total_balance trả về 0 nhưng có phát sinh thu/chi, "
                "giao diện tự động tính ngay số dư ròng = income - expense để thẻ số dư luôn chính xác 100%."
            ),
            "files": "backend/routes/analytics.routes.js, finwise_mobile/lib/screens/dashboard_screen.dart",
            "tested": "Đã kiểm thử: Tài khoản người dùng ngay lập tức hiển thị Tổng số dư chính xác là 197.000 đ (+250k - 53k)."
        }
    ]

    for err in errors:
        p_err_h = doc.add_paragraph()
        p_err_h.paragraph_format.space_before = Pt(12)
        p_err_h.paragraph_format.space_after = Pt(4)
        r_num = p_err_h.add_run(f"Lỗi số {err['id']}: ")
        r_num.bold = True
        r_num.font.name = 'Calibri'
        r_num.font.size = Pt(13)
        r_num.font.color.rgb = RGBColor(0x4F, 0x46, 0xE5)
        
        r_t = p_err_h.add_run(err['title'])
        r_t.bold = True
        r_t.font.name = 'Calibri'
        r_t.font.size = Pt(13)
        r_t.font.color.rgb = RGBColor(0x0F, 0x17, 0x2A)
        
        # Hiện tượng
        p_s = doc.add_paragraph()
        p_s.paragraph_format.space_after = Pt(3)
        r_s_lbl = p_s.add_run("• Hiện tượng gặp phải: ")
        r_s_lbl.bold = True
        r_s_lbl.font.color.rgb = RGBColor(0xDC, 0x26, 0x26)
        r_s_val = p_s.add_run(err['symptom'])
        r_s_val.font.color.rgb = RGBColor(0x33, 0x41, 0x55)
        
        # Nguyên nhân gốc rễ
        p_r = doc.add_paragraph()
        p_r.paragraph_format.space_after = Pt(3)
        r_r_lbl = p_r.add_run("• Nguyên nhân gốc rễ (Root Cause):\n")
        r_r_lbl.bold = True
        r_r_lbl.font.color.rgb = RGBColor(0xD9, 0x77, 0x06)
        r_r_val = p_r.add_run(err['root_cause'])
        r_r_val.font.color.rgb = RGBColor(0x33, 0x41, 0x55)
        
        # Giải pháp khắc phục
        p_g = doc.add_paragraph()
        p_g.paragraph_format.space_after = Pt(3)
        r_g_lbl = p_g.add_run("• Giải pháp khắc phục triệt để:\n")
        r_g_lbl.bold = True
        r_g_lbl.font.color.rgb = RGBColor(0x16, 0xA3, 0x4A)
        r_g_val = p_g.add_run(err['solution'])
        r_g_val.font.color.rgb = RGBColor(0x33, 0x41, 0x55)
        
        # Callout kết quả và file liên quan
        add_callout(
            doc, 
            title="File chỉnh sửa & Kết quả nghiệm thu", 
            text=f"Files: {err['files']}\n=> {err['tested']}", 
            bg_color="F8FAFC", 
            border_color="10B981"
        )

    # --- BÀI HỌC KINH NGHIỆM & KẾT LUẬN ---
    h_concl = doc.add_heading("III. BÀI HỌC KINH NGHIỆM TRONG XÂY DỰNG HỆ THỐNG", level=1)
    h_concl.paragraph_format.space_before = Pt(14)
    h_concl.paragraph_format.space_after = Pt(8)

    lessons = [
        "1. Luôn đồng bộ chặt chẽ giữa Database Schema và Payload Backend: Tránh gửi các cột không tồn tại (như updated_at) khiến PostgreSQL báo lỗi schema và rollback toàn bộ transaction ngầm.",
        "2. Không dựa 100% vào AI cho các bài toán phân loại nhị phân nhạy cảm (Thu vs Chi): Luôn dùng Rule-based / Regex để khóa hướng dòng tiền trước, AI chỉ nên hỗ trợ gán nhãn danh mục chi tiết ở tầng dưới.",
        "3. Tính chịu lỗi (Fault Tolerance) & Trải nghiệm người dùng: Với các dịch vụ đám mây miễn phí có độ trễ khởi động (Cold Start), mobile app phải có cơ chế Retry và thông báo tải rõ ràng, tránh gây hiểu nhầm là app bị đơ.",
        "4. Bảo mật dữ liệu cá nhân là ưu tiên hàng đầu: Mọi truy vấn đọc/ghi đều phải gắn chặt với user_id được giải mã từ JWT, ngăn chặn triệt để lỗ hổng rò rỉ dữ liệu chéo (IDOR)."
    ]
    for ls in lessons:
        p_ls = doc.add_paragraph()
        p_ls.paragraph_format.space_after = Pt(4)
        r_ls = p_ls.add_run(ls)
        r_ls.font.name = 'Calibri'
        r_ls.font.size = Pt(10)
        r_ls.font.color.rgb = RGBColor(0x1E, 0x29, 0x3B)

    # Lưu tài liệu
    output_path = os.path.join(os.path.abspath("e:/DACN2"), "BAO_CAO_TONG_HOP_LOI_VA_GIAI_PHAP_FINWISE.docx")
    doc.save(output_path)
    print(f"[+] Successfully generated Word file at: {output_path}")

if __name__ == "__main__":
    main()
