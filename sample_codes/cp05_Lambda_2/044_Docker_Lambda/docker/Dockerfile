FROM public.ecr.aws/lambda/python:3.12

# 作業ディレクトリを設定 / Set working directory
WORKDIR /var/task

# 必要なシステムライブラリをインストール / Install required system libraries
RUN dnf install -y \
    mesa-libGL \
    mesa-libGL-devel \
    && dnf clean all

# 依存関係をインストール / Install dependencies
RUN pip install --no-cache-dir opencv-python opencv-contrib-python

# Lambda関数のコードをコピー / Copy Lambda function code
COPY app.py .

# Lambda関数のエントリポイントを指定 / Specify Lambda function entry point
CMD ["app.lambda_handler"]
