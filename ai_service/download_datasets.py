"""
Script tự động tải các bộ dữ liệu công khai từ Hugging Face & Kaggle về máy
Lưu vào thư mục: e:\\DACN2\\ai_service\\dataset\\
"""

import os
import sys
import urllib.request

# Cấu hình UTF-8 cho console Windows
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

DATASET_DIR = os.path.join(os.path.dirname(__file__), "dataset")
os.makedirs(DATASET_DIR, exist_ok=True)

def download_file(url, save_path):
    print(f"[*] Đang tải từ: {url}")
    opener = urllib.request.build_opener()
    opener.addheaders = [('User-agent', 'Mozilla/5.0')]
    urllib.request.install_opener(opener)
    urllib.request.urlretrieve(url, save_path)
    print(f"[+] Đã tải xong và lưu vào: {save_path}")

def download_banking77():
    """Tải bộ dữ liệu Banking77 trực tiếp từ kho lưu trữ chính thức."""
    print("\n--- 1. TẢI BỘ DỮ LIỆU BANKING77 (HUGGING FACE / GITHUB) ---")
    train_url = "https://raw.githubusercontent.com/PolyAI-LDN/task-specific-datasets/master/banking_data/train.csv"
    test_url = "https://raw.githubusercontent.com/PolyAI-LDN/task-specific-datasets/master/banking_data/test.csv"

    train_path = os.path.join(DATASET_DIR, "banking77_train.csv")
    test_path = os.path.join(DATASET_DIR, "banking77_test.csv")

    try:
        download_file(train_url, train_path)
        download_file(test_url, test_path)

        with open(train_path, "r", encoding="utf-8") as f:
            line_count = sum(1 for _ in f) - 1
        print(f"[+] Banking77 Train: {line_count} dong mau")
    except Exception as e:
        print(f"[!] Loi khi tai Banking77: {e}")

def try_kagglehub_download():
    """Tải dataset từ Kaggle bằng kagglehub và copy vào thư mục dataset."""
    print("\n--- 2. TẢI TỪ KAGGLE BẰNG KAGGLEHUB ---")
    import shutil
    try:
        import kagglehub
        
        # 2.1 Vietnam Cashless Transactions
        print("[*] Đang tải 'Vietnam Cashless Transactions' từ Kaggle...")
        download_path1 = kagglehub.dataset_download("hnlieu/vietnam-cashless-transactions-2026")
        print(f"[+] Kagglehub đã tải về cache: {download_path1}")
        for fname in os.listdir(download_path1):
            if fname.endswith(".csv"):
                src = os.path.join(download_path1, fname)
                dst = os.path.join(DATASET_DIR, f"kaggle_vn_cashless_{fname}")
                shutil.copy2(src, dst)
                print(f"    -> Đã copy {fname} sang: {dst}")

        # 2.2 Daily Transactions Dataset (Saraswathy)
        print("\n[*] Đang tải 'Daily Transactions Dataset' từ Kaggle...")
        download_path2 = kagglehub.dataset_download("saraswathy/daily-transactions-dataset")
        print(f"[+] Kagglehub đã tải về cache: {download_path2}")
        for fname in os.listdir(download_path2):
            if fname.endswith(".csv"):
                src = os.path.join(download_path2, fname)
                dst = os.path.join(DATASET_DIR, f"kaggle_daily_trans_{fname}")
                shutil.copy2(src, dst)
                print(f"    -> Đã copy {fname} sang: {dst}")

        # 2.3 Hostel Life Daily Expense Tracker
        print("\n[*] Đang tải 'Hostel Life Daily Expense Tracker' từ Kaggle...")
        download_path3 = kagglehub.dataset_download("thedevastator/hostel-life-daily-expense-tracker-janmar-2025")
        print(f"[+] Kagglehub đã tải về cache: {download_path3}")
        for fname in os.listdir(download_path3):
            if fname.endswith(".csv"):
                src = os.path.join(download_path3, fname)
                dst = os.path.join(DATASET_DIR, f"kaggle_hostel_expense_{fname}")
                shutil.copy2(src, dst)
                print(f"    -> Đã copy {fname} sang: {dst}")

    except Exception as e:
        print(f"[!] Thông báo từ Kaggle: {e}")

if __name__ == "__main__":
    download_banking77()
    try_kagglehub_download()
    print("\n===> HOÀN TẤT KIỂM TRA TẢI DỮ LIỆU <===")
