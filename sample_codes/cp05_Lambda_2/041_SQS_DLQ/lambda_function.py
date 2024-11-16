import json
import random

def lambda_handler(event, context):
    for record in event['Records']:
        # 30%の確率で例外
        failure_probability = 0.3
        if random.random() < failure_probability:
            raise Exception("Intentional Random Failure for Retry Mechanism")
        
        # 32の倍数のIDは絶対に失敗させる
        body = record.get('body', {})
        body = json.loads(body)
        if int(body['id']) % 32 == 0:
            raise Exception("Intentional Deterministic Failure for Retry Mechanism")

        print(f"Received message: {json.dumps(body)}")
        
    return {
        'statusCode': 200,
        'body': json.dumps('Messages processed successfully')
    }
