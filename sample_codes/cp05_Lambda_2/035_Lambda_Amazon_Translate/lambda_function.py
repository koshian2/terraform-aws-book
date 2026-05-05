import json
import boto3

def lambda_handler(event, context):
    # イベントから入力データを取得 / Get input data from event
    try:
        input_text = event['input_text']
        source_language = event.get('source_language', 'ja')  # デフォルトは日本語 / Default is Japanese
        target_language = event.get('target_language', 'en')  # デフォルトは英語 / Default is English
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
