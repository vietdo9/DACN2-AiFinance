"""
Script huấn luyện Model 2: Dự báo chi tiêu theo chuỗi thời gian (LSTM Deep Learning)
- Đầu vào: Chuỗi chi tiêu 30 ngày gần nhất
- Đầu ra: Dự báo chi tiêu cho 7 ngày tiếp theo
- Tự động vẽ đồ thị so sánh Thực tế vs Dự báo (MAE, RMSE) để đưa vào báo cáo Đồ án!
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
import pandas as pd
import numpy as np
import pickle
from sklearn.preprocessing import MinMaxScaler
from sklearn.metrics import mean_squared_error, mean_absolute_error
import matplotlib.pyplot as plt

# Thiết lập thư mục
BASE_DIR = os.path.dirname(__file__)
DATASET_PATH = os.path.join(BASE_DIR, "dataset", "cleaned_timeseries_daily_expense.csv")
MODEL_SAVE_DIR = os.path.join(BASE_DIR, "models", "lstm_forecaster")
REPORTS_DIR = os.path.join(BASE_DIR, "reports")

os.makedirs(MODEL_SAVE_DIR, exist_ok=True)
os.makedirs(REPORTS_DIR, exist_ok=True)

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[*] Thiết bị huấn luyện LSTM: {device}")

# 1. Định nghĩa Mạng Nơ-ron Hồi quy LSTM
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
        # x shape: [batch_size, seq_len, 1]
        out, _ = self.lstm(x)
        # Lấy hidden state của bước thời gian cuối cùng
        last_step = out[:, -1, :]
        prediction = self.fc(last_step)
        return prediction

# 2. Tạo Sequence Dataset cho Time-Series
class TimeSeriesDataset(Dataset):
    def __init__(self, sequences, targets):
        self.sequences = torch.tensor(sequences, dtype=torch.float32)
        self.targets = torch.tensor(targets, dtype=torch.float32)

    def __len__(self):
        return len(self.sequences)

    def __getitem__(self, idx):
        return self.sequences[idx], self.targets[idx]

def create_sequences(data, seq_length=30, forecast_length=7):
    """
    Trượt cửa sổ: Dùng 30 ngày liên tiếp để dự báo 7 ngày tiếp theo.
    """
    xs, ys = [], []
    for i in range(len(data) - seq_length - forecast_length + 1):
        x = data[i:(i + seq_length)]
        y = data[(i + seq_length):(i + seq_length + forecast_length)]
        xs.append(x)
        ys.append(y)
    return np.array(xs), np.array(ys)

def main():
    # 3. Đọc dữ liệu chi tiêu hàng ngày
    print("[*] Đang đọc chuỗi dữ liệu chi tiêu...")
    df = pd.read_csv(DATASET_PATH)
    amounts = df["amount"].values.reshape(-1, 1)

    print(f"[+] Tổng số ngày quan sát: {len(amounts)}")
    print(f"[+] Chi tiêu TB/ngày: {np.mean(amounts):,.0f} VNĐ | Cao nhất: {np.max(amounts):,.0f} VNĐ")

    # 4. Chuẩn hóa dữ liệu về khoảng [0, 1]
    scaler = MinMaxScaler(feature_range=(0, 1))
    scaled_amounts = scaler.fit_transform(amounts)

    # Lưu scaler để sau này API dùng lại
    scaler_path = os.path.join(MODEL_SAVE_DIR, "scaler.pkl")
    with open(scaler_path, "wb") as f:
        pickle.dump(scaler, f)
    print(f"[+] Đã lưu bộ chuẩn hóa (Scaler): {scaler_path}")

    # 5. Tạo tập chuỗi thời gian (Seq_len = 30, Forecast_len = 7)
    seq_len = 30
    forecast_len = 7
    X, y = create_sequences(scaled_amounts, seq_len, forecast_len)
    
    # Chia tập Train (85%) và Test (15%) theo thứ tự thời gian
    train_size = int(len(X) * 0.85)
    X_train, X_test = X[:train_size], X[train_size:]
    y_train, y_test = y[:train_size], y[train_size:]

    # Reshape y từ [N, 7, 1] thành [N, 7]
    y_train = y_train.squeeze(-1)
    y_test = y_test.squeeze(-1)

    print(f"[+] Số mẫu chuỗi Train: {len(X_train)} | Test: {len(X_test)}")

    train_dataset = TimeSeriesDataset(X_train, y_train)
    test_dataset = TimeSeriesDataset(X_test, y_test)

    train_loader = DataLoader(train_dataset, batch_size=16, shuffle=True)
    test_loader = DataLoader(test_dataset, batch_size=16, shuffle=False)

    # 6. Khởi tạo mô hình
    model = ExpenseLSTM(input_size=1, hidden_size=64, num_layers=2, output_size=forecast_len, dropout=0.2)
    model.to(device)

    criterion = nn.MSELoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=0.001)

    # 7. Huấn luyện (Epochs = 60)
    epochs = 60
    train_losses = []
    print(f"\n[*] Bắt đầu huấn luyện LSTM ({epochs} Epochs)...")

    for epoch in range(epochs):
        model.train()
        epoch_loss = 0
        for batch_x, batch_y in train_loader:
            batch_x, batch_y = batch_x.to(device), batch_y.to(device)

            optimizer.zero_grad()
            preds = model(batch_x)
            loss = criterion(preds, batch_y)
            loss.backward()
            optimizer.step()

            epoch_loss += loss.item()

        avg_loss = epoch_loss / len(train_loader)
        train_losses.append(avg_loss)

        if (epoch + 1) % 10 == 0 or epoch == 0:
            print(f"Epoch {epoch+1:02d}/{epochs} | Loss (MSE): {avg_loss:.6f}")

    # 8. Lưu mô hình đã train
    model_weights_path = os.path.join(MODEL_SAVE_DIR, "lstm_model.pth")
    torch.save(model.state_dict(), model_weights_path)
    print(f"[+] Đã lưu trọng số mô hình LSTM: {model_weights_path}")

    # 9. Đánh giá trên tập Test (Đo lường sai số thực tế tính theo VNĐ)
    model.eval()
    all_preds_scaled = []
    all_targets_scaled = []

    with torch.no_grad():
        for batch_x, batch_y in test_loader:
            batch_x = batch_x.to(device)
            preds = model(batch_x)
            all_preds_scaled.append(preds.cpu().numpy())
            all_targets_scaled.append(batch_y.numpy())

    all_preds_scaled = np.vstack(all_preds_scaled)
    all_targets_scaled = np.vstack(all_targets_scaled)

    # Đưa ngược về thang đo tiền tệ VNĐ ban đầu (Inverse Transform)
    preds_vnd = scaler.inverse_transform(all_preds_scaled.reshape(-1, 1)).reshape(-1, 7)
    targets_vnd = scaler.inverse_transform(all_targets_scaled.reshape(-1, 1)).reshape(-1, 7)

    # Tính toán sai số
    mae = mean_absolute_error(targets_vnd, preds_vnd)
    rmse = np.sqrt(mean_squared_error(targets_vnd, preds_vnd))

    print("\n" + "="*50)
    print("KẾT QUẢ ĐÁNH GIÁ MÔ HÌNH DỰ BÁO (LSTM METRICS):")
    print("="*50)
    print(f"[*] Sai số tuyệt đối trung bình (MAE): {mae:,.0f} VNĐ")
    print(f"[*] Căn bậc hai sai số bình phương trung bình (RMSE): {rmse:,.0f} VNĐ")

    # Lưu metrics vào file text
    metrics_path = os.path.join(REPORTS_DIR, "lstm_evaluation_metrics.txt")
    with open(metrics_path, "w", encoding="utf-8") as f:
        f.write(f"MÔ HÌNH DỰ BÁO CHI TIÊU LSTM (7 NGÀY)\n")
        f.write(f"MAE: {mae:,.2f} VND\n")
        f.write(f"RMSE: {rmse:,.2f} VND\n")
        f.write(f"Sequence Length (Input): {seq_len} ngay\n")
        f.write(f"Forecast Horizon (Output): {forecast_len} ngay\n")

    # 10. Vẽ biểu đồ so sánh Thực tế vs Dự báo (Chọn 1 mẫu tuần tiêu biểu để vẽ)
    sample_idx = -1 # Mẫu tuần gần nhất trong tập test
    actual_sample = targets_vnd[sample_idx]
    pred_sample = preds_vnd[sample_idx]

    plt.figure(figsize=(10, 6))
    days_labels = [f"Ngày +{i+1}" for i in range(forecast_len)]
    plt.plot(days_labels, actual_sample, marker='o', linewidth=2, color="#1f77b4", label="Chi tiêu Thực tế")
    plt.plot(days_labels, pred_sample, marker='s', linestyle="--", linewidth=2, color="#ff7f0e", label="AI Dự báo (LSTM)")
    plt.title("So sánh Chi tiêu Thực tế vs AI Dự báo (7 ngày tiếp theo)", fontsize=14)
    plt.xlabel("Mốc thời gian", fontsize=12)
    plt.ylabel("Số tiền (VNĐ)", fontsize=12)
    plt.grid(True, linestyle=":", alpha=0.6)
    plt.legend(fontsize=11)
    
    # Định dạng trục Y hiển thị tiền có dấu phẩy
    import matplotlib.ticker as ticker
    plt.gca().yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, p: f'{int(x):,}'))

    chart_path = os.path.join(REPORTS_DIR, "lstm_forecast_comparison.png")
    plt.tight_layout()
    plt.savefig(chart_path, dpi=300)
    plt.close()
    print(f"[+] Đã lưu biểu đồ dự báo: {chart_path}")

    print("\n===> HUẤN LUYỆN MODEL 2 (LSTM) HOÀN TẤT THÀNH CÔNG! <===")

if __name__ == "__main__":
    main()
