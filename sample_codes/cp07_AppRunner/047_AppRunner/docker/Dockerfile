# ベースイメージとしてPython 3.9を使用 / Use Python 3.9 as the base image
FROM python:3.12

# 作業ディレクトリを設定 / Set working directory
WORKDIR /app

# 必要なシステムパッケージのインストール / Install required system packages
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Pythonパッケージのインストール / Install Python packages
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 8080ポートを開放 / Expose port 8080
EXPOSE 8080

# アプリケーションのソースコードをコピー / Copy application source code
COPY . .

# モデルのダウンロード / Download model
RUN python load_pretrained.py

# コンテナが起動したときに実行されるコマンド / Command to run when the container starts
CMD ["python", "app.py"]
