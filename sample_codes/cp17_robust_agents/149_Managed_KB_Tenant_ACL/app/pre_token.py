"""管理者が登録した所属とメールをアクセストークンへ渡す。"""
import json
import os


def handler(event, context):
    attributes = event['request']['userAttributes']
    tenant = attributes.get('custom:tenant_id')
    email = attributes.get('email')
    if (tenant not in json.loads(os.environ['ALLOWED_TENANTS'])
            or not isinstance(email, str) or '@' not in email
            or attributes.get('email_verified') != 'true'):
        raise ValueError('Administrator-managed tenant and verified email are required')
    event.setdefault('response', {})['claimsAndScopeOverrideDetails'] = {
        'accessTokenGeneration': {'claimsToAddOrOverride': {
            'tenant_id': tenant, 'acl_email': email,
        }}
    }
    return event
