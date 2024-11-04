import os
import json
import boto3
import time

def lambda_handler(event, context):
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    sns_client = boto3.client('sns')
    
    for record in event['Records']:
        body = record['body']
        # 必要に応じてメッセージを加工
        message = f"以下のメッセージを受信しました\n\n{body}" 
        
        try:
            response = sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=message,
                Subject="SNSからの通知メール"
            )
            print(f"Published message to SNS: {response['MessageId']}")
        except Exception as e:
            print(f"Error publishing to SNS: {e}")
            raise e  # 必要に応じて再試行やエラーハンドリングを実装

        time.sleep(3) # 次のメール送信との間にクールダウンをいれる
    
    return {
        'statusCode': 200,
        'body': json.dumps('Messages published to SNS successfully')
    }
