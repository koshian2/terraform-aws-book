FROM public.ecr.aws/lambda/python:3.12

# 作業ディレクトリを設定
WORKDIR /var/task

# 必要なシステムライブラリをインストール
RUN dnf install -y \
    mesa-libGL \
    mesa-libGL-devel \
    && dnf clean all

# 依存関係をインストール
RUN pip install --no-cache-dir opencv-python opencv-contrib-python

# Lambda関数のコードをコピー
COPY app.py .

# Lambda関数のエントリポイントを指定
CMD ["app.lambda_handler"]
