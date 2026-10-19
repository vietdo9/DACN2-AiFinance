"""
FinWise Bill / Receipt OCR Parser
Sử dụng EasyOCR (Clova AI CRAFT + CRNN) + PhoBERT để bóc tách thông tin hóa đơn tiếng Việt:
1. Merchant (Tên cửa hàng / thương hiệu)
2. Total Amount (Tổng tiền thanh toán)
3. Transaction Date (Ngày trên hóa đơn)
4. Category Code (Danh mục chi tiêu thông qua PhoBERT)
"""

import re
import datetime
from typing import List, Tuple, Dict, Any, Optional

# Danh sách từ khóa báo hiệu dòng Tổng tiền trên hóa đơn tiếng Việt & tiếng Anh
TOTAL_KEYWORDS = [
    "tổng cộng", "tong cong", "tổng tiền", "tong tien",
    "thanh toán", "thanh toan", "thành tiền", "thanh tien",
    "tổng thanh toán", "tong thanh toan", "phải trả", "phai tra",
    "tiền thanh toán", "tien thanh toan", "tổng cộng tiền", "tong cong tien",
    "số tiền", "so tien", "chuyển khoản", "chuyen khoan", "tiền mặt", "tien mat",
    "grand total", "total amount", "total", "amount due", "net amount", "tong"
]

# Các từ khóa tiêu đề chung cần bỏ qua (đặc biệt khi tìm tổng tiền và tên quán)
HEADER_IGNORE_KEYWORDS = [
    "hóa đơn thanh toán", "hoa don thanh toan", "phiếu thanh toán", "phieu thanh toan",
    "phiếu tính tiền", "phieu tinh tien", "hóa đơn bán lẻ", "hoa don ban le",
    "hóa đơn bán hàng", "hoa don ban hang", "hóa đơn vat", "hoa don vat",
    "hóa đơn gtgt", "hoa don gtgt", "hóa đơn", "hoa don",
    "receipt", "invoice", "bill", "tax invoice",
    "welcome", "xin chào", "xin chao", "cảm ơn quý khách", "cam on quy khach",
    "thu ngân", "nhân viên", "bàn", "so hd", "số hđ", "ma hd", "mã hđ"
]

# Các từ khóa chỉ dòng chứa thông tin phụ (ngày tháng, số điện thoại, mã số thuế)
NON_AMOUNT_KEYWORDS = [
    "ngày", "ngay", "date", "time", "giờ", "gio",
    "tel", "phone", "đt", "dt", "hotline", "mst", "tax", "wifi",
    "bàn", "ban", "table", "stt", "thu ngân", "nhan vien"
]

def extract_amount_from_line(raw: str) -> Optional[int]:
    """Trích xuất số tiền chuẩn từ một dòng text."""
    if not raw:
        return None
    raw_lower = raw.strip().lower()
    
    # Bỏ qua dòng chứa các từ khóa ngày tháng, số điện thoại
    if any(kw in raw_lower for kw in NON_AMOUNT_KEYWORDS):
        return None

    # Khắc phục lỗi OCR nhầm chữ 'O'/'o' thay cho số '0' ở các con số
    raw_fix = re.sub(r'(?<=\d)[oO]|(?<=[.,])[oO]|[oO](?=\d)|[oO](?=[.,])', '0', raw)
    
    # 1. Tìm pattern số có phân cách hàng nghìn rõ ràng (VD: 35.000, 90,000, 1.250.000)
    # Ưu tiên lấy số cuối dòng vì trên hóa đơn đơn giá/thành tiền luôn nằm ở bên phải
    pattern_formatted = r'(\d{1,3}(?:[.,]\d{3})+)'
    matches = list(re.finditer(pattern_formatted, raw_fix))
    if matches:
        best_str = matches[-1].group(1)
        val = int(best_str.replace('.', '').replace(',', ''))
        if 1000 <= val <= 500_000_000:
            return val
            
    # 2. Xử lý dạng "65k", "65.5k"
    k_match = re.search(r'(\d+([.,]\d+)?)\s*k\b', raw_fix.lower())
    if k_match:
        try:
            val = float(k_match.group(1).replace(',', '.'))
            return int(val * 1000)
        except Exception:
            pass

    # 3. Tìm số đứng độc lập (từ 4 đến 8 chữ số, ví dụ 90000 hoặc 50000)
    matches_plain = list(re.finditer(r'\b\d{4,8}\b', raw_fix))
    if matches_plain:
        for m in reversed(matches_plain):
            num_str = m.group(0)
            if len(num_str) == 8 and (num_str.startswith("202") or num_str.endswith("2026") or num_str.endswith("2025")):
                continue
            if len(num_str) == 10 and num_str.startswith("0"):
                continue
            val = int(num_str)
            if 1000 <= val <= 500_000_000:
                return val

    return None

def extract_date(text: str) -> Optional[str]:
    """Tìm ngày tháng định dạng DD/MM/YYYY hoặc YYYY-MM-DD từ chuỗi văn bản."""
    # Pattern: DD/MM/YYYY hoặc DD-MM-YYYY hoặc DD.MM.YYYY
    date_match = re.search(r'\b(0?[1-9]|[12][0-9]|3[01])[\/\-\.\'\"](0?[1-9]|1[012])[\/\-\.\'\"](202\d)\b', text)
    if date_match:
        day, month, year = date_match.groups()
        return f"{year}-{int(month):02d}-{int(day):02d}"
        
    # Pattern: YYYY-MM-DD hoặc YYYY/MM/DD
    date_match_iso = re.search(r'\b(202\d)[\/\-\.](0?[1-9]|1[012])[\/\-\.](0?[1-9]|[12][0-9]|3[01])\b', text)
    if date_match_iso:
        year, month, day = date_match_iso.groups()
        return f"{year}-{int(month):02d}-{int(day):02d}"
        
    # Pattern tiếng Việt: ngày ... tháng ... năm ...
    vn_date_match = re.search(r'ngày\s*([0-3]?\d)\s*tháng\s*([0-1]?\d)\s*năm\s*(202\d)', text, re.IGNORECASE)
    if vn_date_match:
        day, month, year = vn_date_match.groups()
        return f"{year}-{int(month):02d}-{int(day):02d}"
        
    return None

def merge_nearby_ocr_boxes(ocr_results: List[Tuple[Any, str, float]], y_threshold: float = 12.0) -> List[str]:
    """
    Gộp các từ hoặc cụm từ nằm trên cùng một dòng ngang lại với nhau theo tọa độ Bounding Box.
    Giúp ghép 'Tổng cộng' và '90.000 đ' thành một dòng hoàn chỉnh.
    """
    if not ocr_results:
        return []
        
    items = []
    for bbox, text, conf in ocr_results:
        text_clean = text.strip()
        if not text_clean:
            continue
        try:
            y_center = (bbox[0][1] + bbox[2][1]) / 2.0
            x_center = (bbox[0][0] + bbox[2][0]) / 2.0
            height = abs(bbox[2][1] - bbox[0][1])
            items.append((y_center, x_center, height, text_clean))
        except Exception:
            items.append((0.0, 0.0, 10.0, text_clean))
            
    if not items:
        return []
        
    items.sort(key=lambda item: item[0])
    
    lines = []
    current_line = [items[0]]
    
    for item in items[1:]:
        avg_y = sum(x[0] for x in current_line) / len(current_line)
        avg_h = sum(x[2] for x in current_line) / len(current_line)
        threshold = max(y_threshold, avg_h * 0.6)
        
        if abs(item[0] - avg_y) <= threshold:
            current_line.append(item)
        else:
            current_line.sort(key=lambda x: x[1])
            lines.append(" ".join(x[3] for x in current_line))
            current_line = [item]
            
    if current_line:
        current_line.sort(key=lambda x: x[1])
        lines.append(" ".join(x[3] for x in current_line))
        
    return lines

def parse_receipt_ocr_results(ocr_results: List[Tuple[Any, str, float]]) -> Dict[str, Any]:
    """
    Phân tích kết quả từ EasyOCR:
    ocr_results: List of (bbox, text, confidence)
    """
    raw_lines = merge_nearby_ocr_boxes(ocr_results)
    if not raw_lines:
        raw_lines = [res[1].strip() for res in ocr_results if res[1].strip()]
        
    if not raw_lines:
        return {
            "merchant": "Hóa đơn mua sắm",
            "total_amount": 0,
            "date": datetime.date.today().isoformat(),
            "raw_text": "",
            "all_lines": []
        }

    # 1. Bóc tách Merchant (Tên cửa hàng / Thương hiệu)
    merchant_candidates = []
    for line in raw_lines[:6]:
        line_lower = line.lower()
        if any(h in line_lower for h in HEADER_IGNORE_KEYWORDS):
            continue
        if any(h in line_lower for h in NON_AMOUNT_KEYWORDS):
            continue
        if re.search(r'^\d+$', re.sub(r'[\s\.\-\/\:]', '', line)):
            continue
        if len(line) >= 3:
            merchant_candidates.append(line)
            
    merchant = merchant_candidates[0] if merchant_candidates else "Hóa đơn thanh toán"
    if len(merchant) > 50:
        merchant = merchant[:50]

    # 2. Bóc tách Ngày giao dịch
    found_date = None
    for line in raw_lines:
        d = extract_date(line)
        if d:
            found_date = d
            break
    if not found_date:
        found_date = datetime.date.today().isoformat()

    # 3. Bóc tách Tổng tiền (Total Amount)
    detected_amount = None
    candidates_from_keywords = []
    
    for i, line in enumerate(raw_lines):
        line_lower = line.lower()
        
        # Bỏ qua nếu dòng là tiêu đề hóa đơn (ví dụ: Hóa đơn thanh toán)
        if any(h in line_lower for h in HEADER_IGNORE_KEYWORDS):
            continue
            
        has_total_keyword = any(kw in line_lower for kw in TOTAL_KEYWORDS)
        
        if has_total_keyword:
            amt = extract_amount_from_line(line)
            if amt:
                candidates_from_keywords.append(amt)
            else:
                for next_idx in [i + 1, i + 2]:
                    if next_idx < len(raw_lines):
                        next_line = raw_lines[next_idx]
                        amt_next = extract_amount_from_line(next_line)
                        if amt_next:
                            candidates_from_keywords.append(amt_next)
                            break

    if candidates_from_keywords:
        detected_amount = max(candidates_from_keywords)
        
    # Fallback tìm trong tất cả các dòng nếu không thấy từ khóa
    if not detected_amount:
        all_amounts = []
        for line in raw_lines:
            amt = extract_amount_from_line(line)
            if amt and amt >= 1000:
                all_amounts.append(amt)
        if all_amounts:
            detected_amount = max(all_amounts)

    if not detected_amount:
        detected_amount = 0

    return {
        "merchant": merchant,
        "total_amount": detected_amount,
        "date": found_date,
        "raw_text": "\n".join(raw_lines),
        "all_lines": raw_lines
    }
