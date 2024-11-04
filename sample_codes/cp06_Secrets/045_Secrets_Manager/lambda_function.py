import json
import os
import boto3

# シークレットの真の値の取得（グローバルキャッシュして呼び出し回数を減らす）
secret_value = None

def get_secret_value():
    global secret_value
    # Create a Secrets Manager client
    client = boto3.client(
        service_name='secretsmanager'
    )
    secret_name = os.environ['SECRET_NAME']

    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
    except Exception as e:
        print(e)
        raise e

    # シークレットの取得
    secret = get_secret_value_response['SecretString']
    secret_value = json.loads(secret)
    return secret_value

def lambda_handler(event, context):
    secret_dict = get_secret_value()
    password = secret_dict['password']

    user_value = event.get("input_secrets", "")

    # レスポンスペイロード
    login_success = user_value==password and bool(password)
    payload = {
        "login_success": login_success
    }

    # 簡易認証のレスポンス
    return {
        'statusCode': 200,
        'body': json.dumps(payload)
    }
