import json
import boto3
from urllib.parse import unquote

def lambda_handler(event, context):
    s3_client = boto3.client('s3')
    
    # イベントからバケット名とオブジェクトキーを抽出
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        # オブジェクトキーをURLデコード（日本語ファイル名対策）
        key = unquote(record['s3']['object']['key'])

        try:
            # S3からオブジェクトを取得
            response = s3_client.get_object(Bucket=bucket, Key=key)
            content = response['Body'].read().decode('utf-8')  # テキストファイルの場合
            
            # オブジェクトの内容をログに出力
            print(f"Content of {key}:")
            print(content)
            
        except Exception as e:
            print(f"Error getting object {key} from bucket {bucket}. Error: {str(e)}")
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('File content printed to logs.')
    }
