"""Cognitoユーザーを作成します。登録済みなら既存のパスワードを使います。"""
import argparse
import getpass

import boto3
from common import settings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--username', default='reader')
    args = parser.parse_args()
    cfg = settings()
    api = boto3.Session(profile_name=cfg['aws_profile'], region_name=cfg['aws_region']).client('cognito-idp')
    params = {'UserPoolId': cfg['user_pool_id'], 'Username': args.username}
    try:
        user = api.admin_get_user(**params)
    except api.exceptions.UserNotFoundException:
        pass
    else:
        if not user.get('Enabled') or user.get('UserStatus') != 'CONFIRMED':
            raise RuntimeError('既存ユーザーがログイン可能な状態ではありません。Cognitoで状態を確認してください。')
        print(f"SKIP: {args.username} は登録済みです。既存のパスワードを使ってください。")
        return
    password = getpass.getpass('Password (12文字以上・英大文字/小文字/数字/記号): ')
    if password != getpass.getpass('Confirm password: '):
        raise SystemExit('Passwords do not match')
    api.admin_create_user(**params, MessageAction='SUPPRESS')
    api.admin_set_user_password(**params, Password=password, Permanent=True)
    print(f'Created user: {args.username}')


if __name__ == '__main__':
    main()
