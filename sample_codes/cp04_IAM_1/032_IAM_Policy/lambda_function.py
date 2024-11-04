import os
import json
import boto3
from datetime import datetime, timezone

def lambda_handler(event, context):
    # 環境変数からS3バケット名を取得
    s3_bucket = os.environ.get('S3_BUCKET_NAME')
    if not s3_bucket:
        raise ValueError("Environment variable 'S3_BUCKET_NAME' is not set.")

    # S3クライアントを作成
    s3_client = boto3.client('s3')

    # 現在の日時を取得し、ISOフォーマットに変換
    current_datetime = datetime.now(timezone.utc)
    current_datetime_str = current_datetime.isoformat() + 'Z'

    # サンプルメッセージの作成
    sample_message = "これはサンプルメッセージです。"

    # JSONデータの作成
    data = {
        "timestamp": current_datetime_str,
        "message": sample_message
    }
    json_data = json.dumps(data, ensure_ascii=False, indent=4)

    # JSONファイル名の生成（例: log_20231001T123000Z.json）
    file_name = f"log_{current_datetime.strftime('%Y%m%dT%H%M%SZ')}.json"

    try:
        # S3にファイルをアップロード
        s3_client.put_object(
            Bucket=s3_bucket,
            Key=file_name,
            Body=json_data,
            ContentType='application/json'
        )
        print(f"File '{file_name}' has been uploaded to bucket '{s3_bucket}'.")
    except Exception as e:
        print(f"Error uploading file to S3: {e}")
        raise e

    # 必要に応じてレスポンスを返す
    return {
        'statusCode': 200,
        'body': json.dumps(f"File '{file_name}' successfully uploaded to '{s3_bucket}'.")
    }