"""管理者がデモユーザーを登録する。パスワードは保存しない。"""
import argparse
import getpass
import boto3
from common import settings

USERS = {
    'alice': ('tenant-a', 'alice@tenant-a.example'),
    'ann': ('tenant-a', 'ann@tenant-a.example'),
    'bob': ('tenant-b', 'bob@tenant-b.example'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--username', choices=USERS, required=True)
    args = parser.parse_args()
    cfg = settings()
    client = boto3.Session(profile_name=cfg['aws_profile'], region_name=cfg['aws_region']).client('cognito-idp')
    tenant, email = USERS[args.username]
    expected = {'custom:tenant_id': tenant, 'email': email, 'email_verified': 'true'}
    try:
        user = client.admin_get_user(UserPoolId=cfg['user_pool_id'], Username=args.username)
    except client.exceptions.UserNotFoundException:
        user = None
    if user:
        attributes = {a['Name']: a['Value'] for a in user['UserAttributes']}
        if any(attributes.get(k) != v for k, v in expected.items()):
            raise SystemExit('Existing membership/email differs; no changes made.')
        if user['UserStatus'] == 'CONFIRMED' and user['Enabled']:
            print(f'Skipped existing user: {args.username} ({tenant}, {email})')
            return
        raise SystemExit('Existing user is not confirmed/enabled. Check the Cognito console.')
    password = getpass.getpass(f'{args.username}: new password (12+ chars, upper/lower/digit/symbol): ')
    if password != getpass.getpass('Confirm password: '):
        raise SystemExit('Passwords do not match')
    # .exampleは架空ID。管理者が所属と本人IDを割り当てるデモでメール送信はしない。
    client.admin_create_user(UserPoolId=cfg['user_pool_id'], Username=args.username,
        MessageAction='SUPPRESS', UserAttributes=[{'Name': k, 'Value': v} for k, v in expected.items()])
    client.admin_set_user_password(UserPoolId=cfg['user_pool_id'], Username=args.username,
                                  Password=password, Permanent=True)
    print(f'Created {args.username} ({tenant}, {email})')


if __name__ == '__main__':
    main()
