import json
import random

def lambda_handler(event, context):    
    # 失敗確率を設定（例: 50%）
    failure_probability = 0.5
    if random.random() < failure_probability:
        raise Exception("Intentional Failure for Retry Mechanism")
    
    # ここでメッセージの処理を行う
    message = event.get('message', {})
    # 例として、メッセージ内容をログに出力
    print("Successfully processed message: ", json.dumps(message))
    
    # 必要に応じて結果を返す
    return {
        'status': 'success',
        'processedMessage': message
    }
