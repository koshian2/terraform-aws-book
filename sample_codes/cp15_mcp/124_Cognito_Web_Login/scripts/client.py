"""Cognitoユーザーの作成と、トークン取得・検証・更新・失効のデモ。"""
import argparse
from datetime import datetime, timezone
import getpass
import json
from pathlib import Path
import subprocess

import boto3
from botocore import UNSIGNED
from botocore.config import Config
import jwt

ROOT = Path(__file__).resolve().parents[1]


def settings():
    result = subprocess.run(
        ["terraform", f"-chdir={ROOT / 'terraform'}", "output", "-json", "settings"],
        check=True, capture_output=True, text=True, encoding="utf-8",
    )
    return json.loads(result.stdout)


def create_user(config, username):
    password = getpass.getpass("Password (12+ chars, upper/lowercase, digit, symbol): ")
    if password != getpass.getpass("Confirm password: "):
        raise SystemExit("パスワードが一致しません。")
    client = boto3.Session(profile_name=config["aws_profile"], region_name=config["aws_region"]).client("cognito-idp")
    try:
        client.admin_create_user(UserPoolId=config["user_pool_id"], Username=username, MessageAction="SUPPRESS")
    except client.exceptions.UsernameExistsException:
        raise SystemExit("ユーザーが既に存在します。既存のパスワードを使ってください。")
    try:
        client.admin_set_user_password(UserPoolId=config["user_pool_id"], Username=username, Password=password, Permanent=True)
    except Exception:
        print("ユーザーは作成済みですが、パスワード設定に失敗しました。Cognitoコンソールで再設定してください。")
        raise
    print(f"Created user: {username}")


def verify(token, token_use, config, keys):
    key = keys.get_signing_key_from_jwt(token).key
    claims = jwt.decode(
        token, key, algorithms=["RS256"], issuer=config["issuer"],
        audience=config["client_id"] if token_use == "id" else None,
        options={"verify_aud": token_use == "id", "require": ["exp", "iat", "iss", "sub", "token_use"]},
    )
    if claims["token_use"] != token_use:
        raise ValueError("token_useが一致しません。")
    if token_use == "access" and claims.get("client_id") != config["client_id"]:
        raise ValueError("client_idが一致しません。")
    return claims


def inspect_tokens(result, config, keys):
    for name, use in [("IdToken", "id"), ("AccessToken", "access")]:
        claims = verify(result[name], use, config, keys)
        display = {key: claims[key] for key in ["iss", "sub", "token_use", "aud", "client_id", "scope", "iat", "exp"] if key in claims}
        display["expires_at_utc"] = datetime.fromtimestamp(claims["exp"], timezone.utc).isoformat()
        print(f"{name}（署名・発行元・期限・用途・クライアント検証済み）:")
        print(json.dumps(display, ensure_ascii=False, indent=2))
    print(f"ExpiresIn: {result['ExpiresIn']} seconds")


def tokens_demo(config, username):
    # ユーザーの認証にはIAM認証情報ではなく、ユーザープールのIDとパスワードを使う。
    client = boto3.client("cognito-idp", region_name=config["aws_region"], config=Config(signature_version=UNSIGNED))
    response = client.initiate_auth(
        ClientId=config["client_id"], AuthFlow="USER_PASSWORD_AUTH",
        AuthParameters={"USERNAME": username, "PASSWORD": getpass.getpass("Password: ")},
    )
    if "AuthenticationResult" not in response:
        raise SystemExit(f"追加の認証が必要です: {response.get('ChallengeName')}。このデモは作成済みユーザーのパスワード認証を対象とします。")
    result = response["AuthenticationResult"]
    refresh_token = result["RefreshToken"]
    keys = jwt.PyJWKClient(f"{config['issuer']}/.well-known/jwks.json")
    try:
        print("1. initiate_auth: 3種類のトークンを取得")
        inspect_tokens(result, config, keys)
        print("RefreshToken: 取得済み（不透明な文字列。JWTではありません）")
        user = client.get_user(AccessToken=result["AccessToken"])
        print(f"2. get_user: アクセストークンで本人を確認 → {user['Username']}")
        updated = client.initiate_auth(
            ClientId=config["client_id"], AuthFlow="REFRESH_TOKEN_AUTH",
            AuthParameters={"REFRESH_TOKEN": refresh_token},
        )["AuthenticationResult"]
        print("3. REFRESH_TOKEN_AUTH: パスワードを再送せず更新")
        inspect_tokens(updated, config, keys)
    finally:
        client.revoke_token(ClientId=config["client_id"], Token=refresh_token)
        print("4. revoke_token: リフレッシュトークンを失効")
    try:
        client.initiate_auth(ClientId=config["client_id"], AuthFlow="REFRESH_TOKEN_AUTH", AuthParameters={"REFRESH_TOKEN": refresh_token})
    except client.exceptions.NotAuthorizedException:
        print("5. 失効後の更新が拒否されることを確認しました。")
    else:
        raise RuntimeError("失効後も更新できました。想定外の結果です。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["create-user", "tokens"])
    parser.add_argument("--username", default="reader")
    args = parser.parse_args()
    config = settings()
    if args.command == "create-user":
        create_user(config, args.username)
    else:
        tokens_demo(config, args.username)


if __name__ == "__main__":
    main()
