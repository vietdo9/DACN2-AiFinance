FROM python:3.10-slim

# Thiết lập user UID 1000 theo chuẩn Hugging Face Spaces Docker
RUN useradd -m -u 1000 user
ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH

WORKDIR $HOME/app

# Cài đặt các gói hệ thống cần thiết cho OpenCV và PyTorch
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Cài đặt PyTorch CPU (để tối ưu dung lượng và RAM trên Hugging Face CPU Basic 16GB)
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu

# Cài đặt các thư viện Python
COPY --chown=user:user requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Tạo sẵn thư mục cache và cấp quyền cho user 1000
RUN mkdir -p /home/user/.cache /home/user/.EasyOCR && chown -R 1000:1000 /home/user

# Sao chép mã nguồn và mô hình
COPY --chown=user:user . .

USER user

# Hugging Face Spaces sử dụng cổng 7860 mặc định
EXPOSE 7860

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7860"]
