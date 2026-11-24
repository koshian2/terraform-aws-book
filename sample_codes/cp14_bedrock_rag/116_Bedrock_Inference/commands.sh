#!/bin/sh
set -eu

cd "$(dirname "$0")"

# uvプロジェクトの作成なしで、boto3を用意して実行する
uv run --no-project --with boto3 python bedrock_inference.py
