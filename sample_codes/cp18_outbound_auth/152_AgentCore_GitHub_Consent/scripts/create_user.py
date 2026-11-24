"""Create a Cognito reader; preserve an existing account."""
import argparse
import getpass
import boto3
from common import settings

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--username", default="reader")
    args = parser.parse_args()
    cfg = settings()
    client = boto3.Session(profile_name=cfg["aws_profile"], region_name=cfg["aws_region"]).client("cognito-idp")
    identity = dict(UserPoolId=cfg["user_pool_id"], Username=args.username)
    try:
        client.admin_get_user(**identity)
        print(f"既存ユーザー {args.username} を使用します。パスワードは変更しません。")
        return
    except client.exceptions.UserNotFoundException:
        pass
    password = getpass.getpass("パスワード（12文字以上・大小英字・数字・記号）: ")
    if password != getpass.getpass("確認: "):
        raise SystemExit("パスワードが一致しません。")
    try:
        client.admin_create_user(**identity, MessageAction="SUPPRESS")
    except client.exceptions.UsernameExistsException:
        print("既存のアカウントを使用してください。")
        return
    client.admin_set_user_password(**identity, Password=password, Permanent=True)
    print(f"Cognitoのログインユーザー: {args.username}")

if __name__ == "__main__":
    main()
