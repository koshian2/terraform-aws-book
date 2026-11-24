"""比較対象のユーザー・所属・Tierを確認する。認証はGatewayが行う。"""
import base64
import json

from login import login
from session import browser_logout


def claims_for_report(token, user, config):
    # ローカルデコードはユーザー取り違え防止用。署名検証の代わりにはしない。
    payload = token.split('.')[1]
    claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
    tenant = config['demo_users'][user]
    tier = config['tenant_tiers'][tenant]
    if (claims.get('username'), claims.get('tenant_id'), claims.get('tier')) != (user, tenant, tier):
        raise RuntimeError(f'ログインしたユーザー・所属・Tierが期待と違います。{user}でログインし直してください。')
    if not claims.get('sub'):
        raise RuntimeError('ユーザー識別子がありません。')
    return {'user': user, 'tenant': tenant, 'tier': tier, 'sub': claims['sub']}


def login_user(config, user, *, no_browser=False):
    browser_logout(config, **({'open_browser': lambda _: None} if no_browser else {}))
    tenant = config['demo_users'][user]
    print(f'Cognitoに {user}（{tenant} / {config["tenant_tiers"][tenant]}）でログインしてください。', flush=True)
    token = login(config, no_browser=no_browser)
    identity = claims_for_report(token, user, config)
    return token, identity
