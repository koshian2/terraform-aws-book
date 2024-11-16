import json

def lambda_handler(event, context):
    # メッセージを取得
    message = event.get('message', {})
    
    # ここで成功時の処理を行う
    # 例として、メッセージ内容をログに出力
    print("Successfully handled message:", json.dumps(message))
    
    return {
        'status': 'success',
        'handledMessage': message
    }
