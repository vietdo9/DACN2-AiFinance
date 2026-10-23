FROM python:3.10-slim

WORKDIR /app

# Cài đặt các gói hệ thống cần thiết cho OpenCV và PyTorch
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Cài đặt PyTorch CPU (để tối ưu dung lượng và RAM trên Hugging Face)
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu

# Cài đặt các thư viện Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir opencv-python-headless

# Sao chép mã nguồn và mô hình
COPY . .

# Hugging Face Spaces sử dụng cổng 7860 mặc định
EXPOSE 7860

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7860"]
