# ベースイメージとしてPython 3.9を使用
FROM python:3.12

# 作業ディレクトリを設定
WORKDIR /app

# 必要なシステムパッケージのインストール
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Pythonパッケージのインストール
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 8080ポートを開放
EXPOSE 8080

# アプリケーションのソースコードをコピー
COPY . .

# モデルのダウンロード
RUN python load_pretrained.py

# コンテナが起動したときに実行されるコマンド
CMD ["python", "app.py"]
