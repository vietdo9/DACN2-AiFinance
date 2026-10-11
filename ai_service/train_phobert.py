"""
Script huấn luyện Model 1: Phân loại giao dịch tiếng Việt (PhoBERT)
- Tối ưu hóa cho GPU NVIDIA RTX 4050 (sử dụng CUDA & Mixed Precision FP16)
- Tự động vẽ và xuất biểu đồ Loss/Accuracy và Confusion Matrix để dán vào báo cáo Đồ án!
"""

import os
import sys
import torch

# Cấu hình UTF-8 cho console Windows
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from transformers import AutoTokenizer, AutoModelForSequenceClassification, get_linear_schedule_with_warmup
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score
import matplotlib.pyplot as plt
import seaborn as sns

# Thiết lập thư mục
BASE_DIR = os.path.dirname(__file__)
DATASET_PATH = os.path.join(BASE_DIR, "dataset", "cleaned_nlp_transactions.csv")
MODEL_SAVE_DIR = os.path.join(BASE_DIR, "models", "phobert_classifier")
REPORTS_DIR = os.path.join(BASE_DIR, "reports")

os.makedirs(MODEL_SAVE_DIR, exist_ok=True)
os.makedirs(REPORTS_DIR, exist_ok=True)

# Kiểm tra GPU CUDA (RTX 4050)
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"==================================================")
print(f"[*] Thiết bị huấn luyện (Device): {device}")
if torch.cuda.is_available():
    print(f"[*] Tên Card GPU: {torch.cuda.get_device_name(0)}")
    print(f"[*] Bộ nhớ GPU (VRAM): {torch.cuda.get_device_properties(0).total_memory / 1e9:.2f} GB")
print(f"==================================================")

# 1. Dataset Class cho PyTorch
class FinanceDataset(Dataset):
    def __init__(self, texts, labels, tokenizer, max_len=64):
        self.texts = texts
        self.labels = labels
        self.tokenizer = tokenizer
        self.max_len = max_len

    def __len__(self):
        return len(self.texts)

    def __getitem__(self, item):
        text = str(self.texts[item])
        label = self.labels[item]

        encoding = self.tokenizer(
            text,
            truncation=True,
            padding="max_length",
            max_length=self.max_len,
            return_tensors="pt"
        )

        return {
            "input_ids": encoding["input_ids"].flatten(),
            "attention_mask": encoding["attention_mask"].flatten(),
            "label": torch.tensor(label, dtype=torch.long)
        }

def main():
    # 2. Đọc và tiền xử lý dữ liệu
    print("[*] Đang nạp dữ liệu...")
    df = pd.read_csv(DATASET_PATH)
    
    unique_categories = sorted(df["category"].unique())
    label2id = {cat: i for i, cat in enumerate(unique_categories)}
    id2label = {i: cat for i, cat in enumerate(unique_categories)}
    df["label_id"] = df["category"].map(label2id)

    num_classes = len(unique_categories)
    print(f"[+] Số lượng mẫu: {len(df)}")
    print(f"[+] Số lượng nhãn phân loại: {num_classes} ({unique_categories})")

    train_df, val_df = train_test_split(df, test_size=0.15, random_state=42, stratify=df["label_id"])
    print(f"[+] Tập Train: {len(train_df)} mẫu | Tập Validation: {len(val_df)} mẫu")

    # 3. Khởi tạo Tokenizer và Model PhoBERT
    model_name = "vinai/phobert-base-v2"
    print(f"[*] Đang tải mô hình gốc '{model_name}'...")
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    model = AutoModelForSequenceClassification.from_pretrained(
        model_name,
        num_labels=num_classes,
        id2label=id2label,
        label2id=label2id
    )
    model.to(device)

    # 4. Tạo DataLoader
    train_dataset = FinanceDataset(train_df["text"].values, train_df["label_id"].values, tokenizer)
    val_dataset = FinanceDataset(val_df["text"].values, val_df["label_id"].values, tokenizer)

    batch_size = 32  # Tối ưu cho RTX 4050 6GB
    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=batch_size, shuffle=False)

    # 5. Cấu hình Optimizer, Loss và Mixed Precision (FP16)
    epochs = 4
    optimizer = torch.optim.AdamW(model.parameters(), lr=2e-5, weight_decay=0.01)
    total_steps = len(train_loader) * epochs
    scheduler = get_linear_schedule_with_warmup(optimizer, num_warmup_steps=int(total_steps * 0.1), num_training_steps=total_steps)
    criterion = nn.CrossEntropyLoss()
    scaler = torch.cuda.amp.GradScaler(enabled=(device.type == "cuda"))

    # 6. Vòng lặp huấn luyện (Training Loop)
    history = {"train_loss": [], "val_loss": [], "val_acc": []}
    best_val_acc = 0.0

    print(f"\n[*] Bắt đầu huấn luyện {epochs} Epochs...")
    for epoch in range(epochs):
        model.train()
        total_train_loss = 0

        for step, batch in enumerate(train_loader):
            input_ids = batch["input_ids"].to(device)
            attention_mask = batch["attention_mask"].to(device)
            labels = batch["label"].to(device)

            optimizer.zero_grad()

            with torch.cuda.amp.autocast(enabled=(device.type == "cuda")):
                outputs = model(input_ids=input_ids, attention_mask=attention_mask, labels=labels)
                loss = outputs.loss

            scaler.scale(loss).backward()
            scaler.step(optimizer)
            scaler.update()
            scheduler.step()

            total_train_loss += loss.item()

            if (step + 1) % 50 == 0 or (step + 1) == len(train_loader):
                print(f"Epoch {epoch+1}/{epochs} | Step {step+1}/{len(train_loader)} | Loss: {loss.item():.4f}")

        avg_train_loss = total_train_loss / len(train_loader)

        # Đánh giá trên tập Validation
        model.eval()
        total_val_loss = 0
        all_preds = []
        all_labels = []

        with torch.no_grad():
            for batch in val_loader:
                input_ids = batch["input_ids"].to(device)
                attention_mask = batch["attention_mask"].to(device)
                labels = batch["label"].to(device)

                with torch.cuda.amp.autocast(enabled=(device.type == "cuda")):
                    outputs = model(input_ids=input_ids, attention_mask=attention_mask, labels=labels)
                    loss = outputs.loss

                total_val_loss += loss.item()
                preds = torch.argmax(outputs.logits, dim=1)
                all_preds.extend(preds.cpu().numpy())
                all_labels.extend(labels.cpu().numpy())

        avg_val_loss = total_val_loss / len(val_loader)
        val_acc = accuracy_score(all_labels, all_preds)

        history["train_loss"].append(avg_train_loss)
        history["val_loss"].append(avg_val_loss)
        history["val_acc"].append(val_acc)

        print(f"===> [Epoch {epoch+1} Kết thúc] Train Loss: {avg_train_loss:.4f} | Val Loss: {avg_val_loss:.4f} | Val Accuracy: {val_acc*100:.2f}%")

        if val_acc > best_val_acc:
            best_val_acc = val_acc
            print(f"[!] Độ chính xác cải thiện ({val_acc*100:.2f}%). Đang lưu mô hình tốt nhất...")
            model.save_pretrained(MODEL_SAVE_DIR)
            tokenizer.save_pretrained(MODEL_SAVE_DIR)

    # 7. Xuất Báo cáo & Đồ thị cho cuốn báo cáo đồ án
    print("\n[*] Đang tạo báo cáo & đồ thị đánh giá...")
    
    # 7.1. Đồ thị Loss & Accuracy
    plt.figure(figsize=(12, 5))
    plt.subplot(1, 2, 1)
    plt.plot(range(1, epochs + 1), history["train_loss"], label="Train Loss", marker='o')
    plt.plot(range(1, epochs + 1), history["val_loss"], label="Val Loss", marker='s')
    plt.title("Biểu đồ hàm mất mát (Loss)")
    plt.xlabel("Epoch")
    plt.ylabel("Loss")
    plt.legend()
    plt.grid(True)

    plt.subplot(1, 2, 2)
    plt.plot(range(1, epochs + 1), [acc * 100 for acc in history["val_acc"]], label="Val Accuracy (%)", color="green", marker='^')
    plt.title("Biểu đồ độ chính xác (Accuracy)")
    plt.xlabel("Epoch")
    plt.ylabel("Accuracy (%)")
    plt.legend()
    plt.grid(True)

    loss_chart_path = os.path.join(REPORTS_DIR, "phobert_training_metrics.png")
    plt.tight_layout()
    plt.savefig(loss_chart_path, dpi=300)
    plt.close()
    print(f"[+] Đã lưu biểu đồ Loss & Accuracy: {loss_chart_path}")

    # 7.2. Ma trận nhầm lẫn (Confusion Matrix)
    cm = confusion_matrix(all_labels, all_preds)
    plt.figure(figsize=(10, 8))
    sns.heatmap(cm, annot=True, fmt="d", cmap="Blues", xticklabels=unique_categories, yticklabels=unique_categories)
    plt.title("Ma trận nhầm lẫn (Confusion Matrix) - PhoBERT")
    plt.xlabel("Dự đoán (Predicted)")
    plt.ylabel("Thực tế (Actual)")
    plt.xticks(rotation=45, ha="right")
    cm_path = os.path.join(REPORTS_DIR, "phobert_confusion_matrix.png")
    plt.tight_layout()
    plt.savefig(cm_path, dpi=300)
    plt.close()
    print(f"[+] Đã lưu ảnh Ma trận nhầm lẫn: {cm_path}")

    # 7.3. Classification Report
    report = classification_report(all_labels, all_preds, target_names=unique_categories, digits=4)
    print("\n" + "="*50)
    print("KẾT QUẢ ĐÁNH GIÁ MÔ HÌNH (CLASSIFICATION REPORT):")
    print("="*50)
    print(report)
    
    report_text_path = os.path.join(REPORTS_DIR, "phobert_classification_report.txt")
    with open(report_text_path, "w", encoding="utf-8") as f:
        f.write(report)
    print(f"[+] Đã lưu báo cáo dạng text: {report_text_path}")

    print("\n===> HUẤN LUYỆN MODEL 1 (PHOBERT) HOÀN TẤT THÀNH CÔNG! <===")

if __name__ == "__main__":
    main()
