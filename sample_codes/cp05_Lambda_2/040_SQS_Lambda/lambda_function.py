import json

def lambda_handler(event, context):
    for record in event['Records']:
        # メッセージ本文を取得
        body = record['body']
        print(f"Received message: {body}")
    return {
        'statusCode': 200,
        'body': json.dumps('Messages processed successfully')
    }
