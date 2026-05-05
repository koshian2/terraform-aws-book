import json
import boto3
from urllib.parse import unquote
import os

def translate_text(input_json):
    # イベントから入力データを取得 / Get input data from event
    try:
        input_text = input_json['input_text']
        source_language = input_json.get('source_language', 'ja')  # デフォルトは日本語 / Default is Japanese
        target_language = input_json.get('target_language', 'en')  # デフォルトは英語 / Default is English
    except (KeyError, json.JSONDecodeError) as e:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid input format'})
        }
    
    # Amazon Translateクライアントを作成 / Create Amazon Translate client
    translate = boto3.client('translate')
    
    try:
        # 翻訳を実行 / Execute translation
        response = translate.translate_text(
            Text=input_text,
            SourceLanguageCode=source_language,
            TargetLanguageCode=target_language
        )
        translated_text = response['TranslatedText']
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
    
    # 成功レスポンスを返す / Return success response
    return {
        'statusCode': 200,
        'body': json.dumps({'translated_text': translated_text})
    }


def lambda_handler(event, context):
    s3_client = boto3.client('s3')
    
    # イベントからバケット名とオブジェクトキーを抽出 / Extract bucket name and object key from event
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        # オブジェクトキーをURLデコード（日本語ファイル名対策） / URL-decode the object key (for Japanese filename support)
        key = unquote(record['s3']['object']['key'])

        try:
            # S3からオブジェクトを取得 / Get object from S3
            response = s3_client.get_object(Bucket=bucket, Key=key)
            input_json = json.loads(response['Body'].read().decode('utf-8'))

            # 翻訳結果を取得 / Get translation result
            translate_payload = translate_text(input_json)
            translate_result = json.loads(translate_payload['body'])

            # 出力バケットに記録 / Write to output bucket
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
