import json
import os
import boto3

# シークレットの真の値の取得（グローバルキャッシュして呼び出し回数を減らす）
ssm = boto3.client('ssm')
parameter_name = os.environ["PARAMETER_STORE_SECRET"]
response = ssm.get_parameter(
    Name=parameter_name,
    WithDecryption=True
)
secret_value = response['Parameter']['Value']


def lambda_handler(event, context):
    user_value = event.get("input_secrets", "")

    # シークレットでない値を環境変数から取得
    non_secret_value = os.environ.get("NON_SECRET_VALUE", "")

    # レスポンスペイロード
    login_success = user_value==secret_value and bool(secret_value)
    payload = {
        "message": f"Hello, {non_secret_value}!" if login_success else "Access denied.",
        "login_success": login_success
    }

    # 簡易認証のレスポンス
    return {
        'statusCode': 200,
        'body': json.dumps(payload)
    }
