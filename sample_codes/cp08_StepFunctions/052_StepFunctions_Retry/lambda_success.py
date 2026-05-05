import json

def lambda_handler(event, context):
    # メッセージを取得 / Get message
    message = event.get('message', {})
    
    # ここで成功時の処理を行う / Handle success case here
    # 例として、メッセージ内容をログに出力 / As an example, log the message content
    print("Successfully handled message:", json.dumps(message))
    
    return {
        'status': 'success',
        'handledMessage': message
    }
