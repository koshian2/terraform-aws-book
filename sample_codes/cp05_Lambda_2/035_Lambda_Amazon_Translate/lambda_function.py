import json
import boto3

def lambda_handler(event, context):
    # イベントから入力データを取得
    try:
        input_text = event['input_text']
        target_language = event.get('target_language', 'en')  # デフォルトは英語
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
