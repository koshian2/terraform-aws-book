"""Copy administrator-managed membership into the Cognito access token."""
import json
import os


def handler(event, context):
    tenant = event['request']['userAttributes'].get('custom:tenant_id')
    if not isinstance(tenant, str) or tenant not in json.loads(os.environ['ALLOWED_TENANTS']):
        raise ValueError('Missing or unknown tenant membership')
    event.setdefault('response', {})['claimsAndScopeOverrideDetails'] = {
        'accessTokenGeneration': {'claimsToAddOrOverride': {'tenant_id': tenant}}
    }
    return event
