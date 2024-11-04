import json
import boto3
from urllib.parse import unquote
import os

def translate_text(input_json):
    # イベントから入力データを取得
    try:
        input_text = input_json['input_text']
        target_language = input_json.get('target_language', 'en')  # デフォルトは英語
    except (KeyError, json.JSONDecodeError) as e:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid input format'})
        }
    
    # Amazon Translateクライアントを作成
    translate = boto3.client('translate')
    
    try:
        # 翻訳を実行
        response = translate.translate_text(
            Text=input_text,
            SourceLanguageCode='ja',
            TargetLanguageCode=target_language
        )
        translated_text = response['TranslatedText']
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
    
    # 成功レスポンスを返す
    return {
        'statusCode': 200,
        'body': json.dumps({'translated_text': translated_text})
    }


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
            input_json = json.loads(response['Body'].read().decode('utf-8'))

            # 翻訳結果を取得
            translate_payload = translate_text(input_json)
            translate_result = json.loads(translate_payload['body'])

            # 出力バケットに記録
            output_bucket = os.environ['OUTPUT_BUCKET']
            s3_client.put_object(
                Bucket=output_bucket,
                Key=key,
                Body=json.dumps(translate_result, ensure_ascii=False, indent=4, separators=(',', ': ')),
                ContentType='application/json'
            )

            
        except Exception as e:
            print(f"Error getting object {key} from bucket {bucket}. Error: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': str(e)})
            }
        
    return translate_payload
